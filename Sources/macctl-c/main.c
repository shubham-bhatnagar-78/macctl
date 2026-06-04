/*
 * macctl — ultra-thin C client for macctl daemon.
 * Zero Swift runtime. Zero framework loading. Only libSystem.
 * Binary: ~50KB. Spawn: 14ms warm vs 36ms Swift.
 *
 * Usage: macctl <command> [subcommand] [--flag value ...]
 *        macctl watch file <path>
 *        macctl watch apps
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <errno.h>
#include <pwd.h>
#include <libproc.h>

// ── Socket path ───────────────────────────────────────────────────────────────

static void get_socket_path(char *buf, size_t len) {
    const char *home = getenv("HOME");
    if (!home) { struct passwd *pw = getpwuid(getuid()); home = pw ? pw->pw_dir : "/tmp"; }
    snprintf(buf, len, "%s/Library/Application Support/macctl/daemon.sock", home);
}

static int connect_daemon(void) {
    char sock_path[512]; get_socket_path(sock_path, sizeof(sock_path));
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path)-1);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) { close(fd); return -1; }
    return fd;
}

// ── Framing ───────────────────────────────────────────────────────────────────

static int send_framed(int fd, const char *data, size_t len) {
    uint32_t net_len = htonl((uint32_t)len);
    if (write(fd, &net_len, 4) != 4) return -1;
    if ((size_t)write(fd, data, len) != len) return -1;
    return 0;
}

static char *recv_framed(int fd, size_t *out_len) {
    uint32_t net_len; ssize_t n, total = 0;
    while (total < 4) {
        n = read(fd, ((char*)&net_len)+total, 4-total);
        if (n <= 0) return NULL; total += n;
    }
    uint32_t msg_len = ntohl(net_len);
    if (msg_len > 16*1024*1024) return NULL;
    char *buf = malloc(msg_len+1); if (!buf) return NULL;
    total = 0;
    while ((size_t)total < msg_len) {
        n = read(fd, buf+total, msg_len-total);
        if (n <= 0) { free(buf); return NULL; } total += n;
    }
    buf[msg_len] = '\0'; *out_len = msg_len; return buf;
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

static void json_escape(const char *src, char *dst, size_t dst_len) {
    size_t i=0,j=0;
    while(src[i]&&j<dst_len-4){
        char c=src[i++];
        if(c=='"'){dst[j++]='\\';dst[j++]='"';}
        else if(c=='\\'){dst[j++]='\\';dst[j++]='\\';}
        else if(c=='\n'){dst[j++]='\\';dst[j++]='n';}
        else if(c=='\r'){dst[j++]='\\';dst[j++]='r';}
        else{dst[j++]=c;}
    }
    dst[j]='\0';
}

// Build JSON-RPC request from method + key/value pairs
static int build_request(const char *method, char **kv, int kv_count,
                          char *out, size_t out_len) {
    char escaped_method[256], escaped_key[256], escaped_val[512];
    json_escape(method, escaped_method, sizeof(escaped_method));
    int pos = snprintf(out, out_len,
        "{\"jsonrpc\":\"2.0\",\"id\":\"c\",\"method\":\"%s\",\"params\":{",
        escaped_method);
    for (int i=0; i<kv_count-1; i+=2) {
        const char *key=kv[i], *val=kv[i+1];
        json_escape(key, escaped_key, sizeof(escaped_key));
        char *endptr;
        long long ival = strtoll(val, &endptr, 10);
        double dval   = strtod(val, &endptr);
        if (!strcmp(val,"true")||!strcmp(val,"false"))
            pos += snprintf(out+pos,out_len-pos,"\"%s\":%s%s",escaped_key,val,(i+2<kv_count-1)?",":"");
        else if(*endptr=='\0'&&endptr!=val&&!strchr(val,'.'))
            pos += snprintf(out+pos,out_len-pos,"\"%s\":%lld%s",escaped_key,ival,(i+2<kv_count-1)?",":"");
        else if(*endptr=='\0'&&endptr!=val)
            pos += snprintf(out+pos,out_len-pos,"\"%s\":%g%s",escaped_key,dval,(i+2<kv_count-1)?",":"");
        else {
            json_escape(val,escaped_val,sizeof(escaped_val));
            pos += snprintf(out+pos,out_len-pos,"\"%s\":\"%s\"%s",escaped_key,escaped_val,(i+2<kv_count-1)?",":"");
        }
    }
    pos += snprintf(out+pos,out_len-pos,"}}");
    return pos;
}

// ── JSON pretty-printer ───────────────────────────────────────────────────────

static void pretty_print(const char *json) {
    int indent=0,in_string=0;
    for(size_t i=0;json[i];i++){
        char c=json[i];
        if(in_string){
            putchar(c);
            if(c=='\\'){putchar(json[++i]);}
            else if(c=='"')in_string=0;
        } else switch(c){
            case '"': in_string=1; putchar(c); break;
            case '{': case '[': putchar(c);putchar('\n');indent+=2;for(int j=0;j<indent;j++)putchar(' ');break;
            case '}': case ']': putchar('\n');indent-=2;for(int j=0;j<indent;j++)putchar(' ');putchar(c);break;
            case ',': putchar(c);putchar('\n');for(int j=0;j<indent;j++)putchar(' ');break;
            case ':': putchar(c);putchar(' ');break;
            case ' ':case '\n':case '\r':case '\t': break;
            default: putchar(c);
        }
    }
    putchar('\n');
}

// ── Flag mapping ──────────────────────────────────────────────────────────────

typedef struct { const char *flag; const char *param_key; } FlagMap;
static const FlagMap FLAGS[] = {
    {"--app","bundleID"},{"--id","elementId"},{"--query","query"},
    {"--text","text"},{"--into","query"},{"--combo","combo"},
    {"--path","path"},{"--content","content"},{"--from","from"},
    {"--to","to"},{"--filter","filter"},{"--limit","limit"},
    {"--direction","direction"},{"--amount","amount"},
    {"--domain","domain"},{"--key","key"},{"--value","value"},
    {"--name","name"},{"--folder","folder"},{"--body","body"},
    {"--title","title"},{"--url","url"},{"--service","service"},
    {"--x","x"},{"--y","y"},{"--width","width"},{"--height","height"},
    {"--id","id"},{"--side","side"},{"--reason","reason"},
    {"--timeout","timeout"},{"--screen","screenIndex"},
    {NULL,NULL}
};

// ── Watch command (subscribe protocol) ───────────────────────────────────────

static volatile int watch_running = 1;
static void handle_sigint(int sig) { (void)sig; watch_running = 0; }

static int cmd_watch(const char *topic, const char *param_key, const char *param_val) {
    int fd = connect_daemon();
    if (fd < 0) {
        fprintf(stderr,"{\"success\":false,\"error\":{\"code\":4,\"message\":\"Daemon not running\"}}\n");
        return 4;
    }

    // Build subscribe message
    char sub_id[64]; snprintf(sub_id, sizeof(sub_id), "w%ld", (long)getpid());
    char sub_msg[1024];
    if (param_key && param_val) {
        char escaped[512]; json_escape(param_val, escaped, sizeof(escaped));
        snprintf(sub_msg, sizeof(sub_msg),
            "{\"op\":\"subscribe\",\"topic\":\"%s\",\"params\":{\"%s\":\"%s\"},\"subID\":\"%s\"}",
            topic, param_key, escaped, sub_id);
    } else {
        snprintf(sub_msg, sizeof(sub_msg),
            "{\"op\":\"subscribe\",\"topic\":\"%s\",\"params\":{},\"subID\":\"%s\"}",
            topic, sub_id);
    }

    if (send_framed(fd, sub_msg, strlen(sub_msg)) < 0) { close(fd); return 1; }

    // Print header to stderr (not stdout — keep stdout clean JSON)
    fprintf(stderr, "Watching %s. Ctrl+C to stop.\n", topic);
    fflush(stderr);

    signal(SIGINT, handle_sigint);

    // Read stream events
    char buf[65536*4];
    size_t buf_len = 0;
    while (watch_running) {
        ssize_t n = read(fd, buf + buf_len, sizeof(buf) - buf_len - 1);
        if (n <= 0) break;
        buf_len += n;
        buf[buf_len] = '\0';

        // Parse all complete framed messages
        while (buf_len >= 4) {
            uint32_t msg_len_net;
            memcpy(&msg_len_net, buf, 4);
            uint32_t msg_len = ntohl(msg_len_net);
            if (buf_len < 4 + msg_len) break;

            char *msg = buf + 4;
            msg[msg_len] = '\0';

            // Check if it's the done frame
            if (strstr(msg, "\"done\"") || strstr(msg, "\"type\":\"done\"")) {
                watch_running = 0; break;
            }
            // Skip error frames from the framing layer
            if (strstr(msg, "\"type\":\"error\"")) {
                char *emsg = strstr(msg, "\"message\"");
                if (emsg) {
                    emsg = strchr(emsg, ':');
                    if (emsg) fprintf(stderr, "Error: %s\n", emsg+1);
                }
                watch_running = 0; break;
            }
            // Print event
            pretty_print(msg);
            fflush(stdout);

            // Shift buffer
            memmove(buf, buf + 4 + msg_len, buf_len - 4 - msg_len);
            buf_len -= 4 + msg_len;
        }
    }

    // Send unsubscribe
    char unsub[256];
    snprintf(unsub, sizeof(unsub), "{\"op\":\"unsubscribe\",\"subID\":\"%s\"}", sub_id);
    send_framed(fd, unsub, strlen(unsub));

    close(fd);
    return 0;
}

// ── Help ──────────────────────────────────────────────────────────────────────

static void print_help(void) {
    fprintf(stderr,
        "macctl — ultra-fast macOS automation\n\n"
        "Usage: macctl <command> [subcommand] [--flag value ...]\n\n"
        "UI Automation:\n"
        "  click    --app <id> [--query <label>|--id <E3>|--x <n> --y <n>]\n"
        "  type     --app <id> --text <text> [--into <field>]\n"
        "  key      --app <id> --combo <action|cmd+s>\n"
        "  see      --app <id>\n"
        "  scroll   --app <id> [--direction up|down] [--amount 3]\n"
        "  drag     --app <id> --from-x <n> --from-y <n> --to-x <n> --to-y <n>\n"
        "  screenshot [--app <id>]\n\n"
        "App Lifecycle:\n"
        "  app list | launch <id> | quit <id> | hide <id> | show <id>\n\n"
        "Shell:\n"
        "  shell <command> [--timeout 30]\n\n"
        "System:\n"
        "  system status | volume [0.0-1.0] | brightness [0.0-1.0]\n"
        "         wifi [on|off] | bluetooth [on|off] | mute [on|off]\n"
        "  power  status | lock | sleep | caffeinate [--reason <text>]\n"
        "  screen list | brightness <0.0-1.0>\n"
        "  input-source current | list | select <id>\n\n"
        "Data:\n"
        "  clipboard read | write --text <text> | write --html <html> | clear\n"
        "  defaults read <domain> <key> | write <domain> <key> <value> | delete\n"
        "  network status | resolve <hostname>\n"
        "  calendar list | events | create <title> --start <ts> --end <ts>\n"
        "  reminders lists | list | create <title> | complete <id>\n"
        "  contacts search <query> | get <id> | create\n"
        "  notes folders | list | find <name> | create <title> [--body <text>]\n"
        "         get <id> | append <id> <text> | delete <id>\n\n"
        "Files:\n"
        "  file read|write|copy|move|delete|list|stat|mkdir|exists\n"
        "       tags|set-tags|add-tags|reveal|open|resolve-icloud\n\n"
        "Windows & Processes:\n"
        "  window list | move | resize | set-bounds | tile-left | tile-right\n"
        "         focus | minimize | fullscreen\n"
        "  process list [<filter>] | kill <pid|name> | is-running <name>\n"
        "  spotlight search <query> | find <name>\n\n"
        "Streaming:\n"
        "  watch file <path>   — live file change events\n"
        "  watch apps          — app launch/quit/activate events\n\n"
        "Daemon:\n"
        "  install | uninstall\n\n"
        "Daemon must be running: macctl-daemon &\n"
    );
}

// ── main ─────────────────────────────────────────────────────────────────────

int main(int argc, char *argv[]) {
    if (argc < 2 || !strcmp(argv[1],"--help") || !strcmp(argv[1],"-h") || !strcmp(argv[1],"help")) {
        print_help(); return 0;
    }
    if (!strcmp(argv[1],"--version") || !strcmp(argv[1],"-v")) {
        printf("macctl 1.0.0\n"); return 0;
    }

    // ── watch command (streaming, special handling) ──────────────────────────
    if (!strcmp(argv[1], "watch")) {
        if (argc < 3) {
            fprintf(stderr, "usage: macctl watch file <path>\n       macctl watch apps\n");
            return 1;
        }
        if (!strcmp(argv[2], "file")) {
            const char *path = argc > 3 ? argv[3] : ".";
            return cmd_watch("file-watch", "path", path);
        }
        if (!strcmp(argv[2], "apps")) {
            return cmd_watch("app-lifecycle", NULL, NULL);
        }
        fprintf(stderr, "Unknown watch topic: %s\n", argv[2]);
        return 1;
    }

    // ── install/uninstall ────────────────────────────────────────────────────
    if (!strcmp(argv[1], "install") || !strcmp(argv[1], "uninstall")) {
        // Delegate to shell for launchd operations
        char cmd[512];
        if (!strcmp(argv[1], "install")) {
            // Write plist and load
            const char *home = getenv("HOME");
            char plist_path[512];
            snprintf(plist_path, sizeof(plist_path),
                "%s/Library/LaunchAgents/com.macctl.daemon.plist", home);
            // Find daemon next to this binary
            char self[512]; proc_pidpath(getpid(), self, sizeof(self));
            char *slash = strrchr(self, '/');
            char daemon_path[512];
            if (slash) { *slash='\0'; snprintf(daemon_path,sizeof(daemon_path),"%s/macctl-daemon",self); }
            else strcpy(daemon_path, "/usr/local/bin/macctl-daemon");
            FILE *f = fopen(plist_path, "w");
            if (!f) { fprintf(stderr,"Cannot write %s\n",plist_path); return 1; }
            fprintf(f,
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
                "<plist version=\"1.0\"><dict>\n"
                "<key>Label</key><string>com.macctl.daemon</string>\n"
                "<key>ProgramArguments</key><array><string>%s</string></array>\n"
                "<key>KeepAlive</key><true/>\n"
                "<key>RunAtLoad</key><true/>\n"
                "<key>HardResourceLimits</key><dict><key>NumberOfFiles</key><integer>4096</integer></dict>\n"
                "</dict></plist>\n", daemon_path);
            fclose(f);
            snprintf(cmd, sizeof(cmd), "launchctl load '%s'", plist_path);
            system(cmd);
            printf("{\"success\":true,\"data\":{\"message\":\"macctl daemon installed\",\"plist\":\"%s\"}}\n", plist_path);
        } else {
            const char *home = getenv("HOME");
            char plist_path[512];
            snprintf(plist_path, sizeof(plist_path), "%s/Library/LaunchAgents/com.macctl.daemon.plist", home);
            snprintf(cmd, sizeof(cmd), "launchctl unload '%s' 2>/dev/null; rm -f '%s'", plist_path, plist_path);
            system(cmd);
            printf("{\"success\":true,\"data\":{\"message\":\"macctl daemon uninstalled\"}}\n");
        }
        return 0;
    }

    // ── Standard RPC commands ────────────────────────────────────────────────

    // Build method from first 1-2 positional args
    char method[256] = "";
    int param_start = 1;

    strncpy(method, argv[1], sizeof(method)-1);
    if (argc > 2 && argv[2][0] != '-') {
        size_t mlen = strlen(method);
        snprintf(method+mlen, sizeof(method)-mlen, ".%s", argv[2]);
        param_start = 3;
    }

    // Collect --flag value pairs
    char *kv[64]; int kv_count = 0;
    for (int i=param_start; i<argc && kv_count<62; i++) {
        if (argv[i][0]=='-' && argv[i][1]=='-') {
            const char *param_key = NULL;
            for (int f=0; FLAGS[f].flag; f++)
                if (!strcmp(argv[i], FLAGS[f].flag)) { param_key=FLAGS[f].param_key; break; }
            if (!param_key) param_key = argv[i]+2;
            if (i+1 < argc) { kv[kv_count++]=(char*)param_key; kv[kv_count++]=argv[++i]; }
        }
    }

    // Build and send request
    char request[65536];
    build_request(method, kv, kv_count, request, sizeof(request));

    int fd = connect_daemon();
    if (fd < 0) {
        fprintf(stderr,"{\"success\":false,\"error\":{\"code\":4,\"message\":\"Daemon not running. Run: macctl-daemon &\"}}\n");
        return 4;
    }

    if (send_framed(fd, request, strlen(request)) < 0) { close(fd); return 1; }
    size_t resp_len;
    char *response = recv_framed(fd, &resp_len);
    close(fd);

    if (!response) {
        fprintf(stderr,"{\"success\":false,\"error\":{\"code\":5,\"message\":\"No response from daemon\"}}\n");
        return 1;
    }

    pretty_print(response);
    int exit_code = (strstr(response,"\"success\":false")||strstr(response,"\"success\": false")) ? 1 : 0;
    free(response);
    return exit_code;
}
