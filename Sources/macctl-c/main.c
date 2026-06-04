/*
 * macctl-fast — ultra-thin C client for macctl daemon.
 * Zero Swift runtime. Zero framework loading. Only libSystem.
 * Binary: ~50KB. Spawn time: ~8-12ms vs ~55ms for Swift binary.
 *
 * Usage: macctl-fast <method> [--key value ...]
 * Translates args to JSON-RPC, sends over Unix socket, pretty-prints response.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <errno.h>
#include <pwd.h>

// ── Socket path (mirrors SocketServer.defaultSocketPath) ─────────────────────

static void get_socket_path(char *buf, size_t len) {
    const char *home = getenv("HOME");
    if (!home) {
        struct passwd *pw = getpwuid(getuid());
        home = pw ? pw->pw_dir : "/tmp";
    }
    snprintf(buf, len, "%s/Library/Application Support/macctl/daemon.sock", home);
}

// ── JSON builder (no library — just strings) ─────────────────────────────────

static void json_escape(const char *src, char *dst, size_t dst_len) {
    size_t i = 0, j = 0;
    while (src[i] && j < dst_len - 4) {
        char c = src[i++];
        if      (c == '"')  { dst[j++] = '\\'; dst[j++] = '"'; }
        else if (c == '\\') { dst[j++] = '\\'; dst[j++] = '\\'; }
        else if (c == '\n') { dst[j++] = '\\'; dst[j++] = 'n'; }
        else if (c == '\r') { dst[j++] = '\\'; dst[j++] = 'r'; }
        else                { dst[j++] = c; }
    }
    dst[j] = '\0';
}

// Build JSON-RPC request from (method, key/value pairs)
// argv: method key1 val1 key2 val2 ...
static int build_request(const char *method, char **kv, int kv_count,
                          char *out, size_t out_len) {
    char escaped_method[256], escaped_key[256], escaped_val[512];
    json_escape(method, escaped_method, sizeof(escaped_method));

    int pos = snprintf(out, out_len,
        "{\"jsonrpc\":\"2.0\",\"id\":\"c\",\"method\":\"%s\",\"params\":{",
        escaped_method);

    for (int i = 0; i < kv_count - 1; i += 2) {
        const char *key = kv[i];
        const char *val = kv[i+1];
        json_escape(key, escaped_key, sizeof(escaped_key));

        // Detect type: number, bool, or string
        char *endptr;
        long long ival = strtoll(val, &endptr, 10);
        double dval   = strtod(val, &endptr);

        if (strcmp(val,"true") == 0 || strcmp(val,"false") == 0) {
            pos += snprintf(out+pos, out_len-pos, "\"%s\":%s%s",
                escaped_key, val, (i+2 < kv_count-1) ? "," : "");
        } else if (*endptr == '\0' && endptr != val && strchr(val,'.') == NULL) {
            pos += snprintf(out+pos, out_len-pos, "\"%s\":%lld%s",
                escaped_key, ival, (i+2 < kv_count-1) ? "," : "");
        } else if (*endptr == '\0' && endptr != val) {
            pos += snprintf(out+pos, out_len-pos, "\"%s\":%g%s",
                escaped_key, dval, (i+2 < kv_count-1) ? "," : "");
        } else {
            json_escape(val, escaped_val, sizeof(escaped_val));
            pos += snprintf(out+pos, out_len-pos, "\"%s\":\"%s\"%s",
                escaped_key, escaped_val, (i+2 < kv_count-1) ? "," : "");
        }
    }
    pos += snprintf(out+pos, out_len-pos, "}}");
    return pos;
}

// ── Length-prefix framing ─────────────────────────────────────────────────────

static int send_framed(int fd, const char *data, size_t len) {
    uint32_t net_len = htonl((uint32_t)len);
    if (write(fd, &net_len, 4) != 4) return -1;
    if ((size_t)write(fd, data, len) != len) return -1;
    return 0;
}

static char *recv_framed(int fd, size_t *out_len) {
    uint32_t net_len;
    ssize_t n = 0, total = 0;
    while (total < 4) {
        n = read(fd, ((char*)&net_len) + total, 4 - total);
        if (n <= 0) return NULL;
        total += n;
    }
    uint32_t msg_len = ntohl(net_len);
    if (msg_len > 16*1024*1024) return NULL;
    char *buf = malloc(msg_len + 1);
    if (!buf) return NULL;
    total = 0;
    while ((size_t)total < msg_len) {
        n = read(fd, buf + total, msg_len - total);
        if (n <= 0) { free(buf); return NULL; }
        total += n;
    }
    buf[msg_len] = '\0';
    *out_len = msg_len;
    return buf;
}

// ── Minimal JSON pretty-printer ───────────────────────────────────────────────

static void pretty_print(const char *json) {
    int indent = 0;
    int in_string = 0;
    for (size_t i = 0; json[i]; i++) {
        char c = json[i];
        if (in_string) {
            putchar(c);
            if (c == '\\') { putchar(json[++i]); }
            else if (c == '"') in_string = 0;
        } else {
            switch (c) {
            case '"': in_string = 1; putchar(c); break;
            case '{': case '[':
                putchar(c); putchar('\n');
                indent += 2;
                for (int j=0;j<indent;j++) putchar(' ');
                break;
            case '}': case ']':
                putchar('\n');
                indent -= 2;
                for (int j=0;j<indent;j++) putchar(' ');
                putchar(c);
                break;
            case ',':
                putchar(c); putchar('\n');
                for (int j=0;j<indent;j++) putchar(' ');
                break;
            case ':':
                putchar(c); putchar(' ');
                break;
            case ' ': case '\n': case '\r': case '\t':
                break; // skip whitespace
            default:
                putchar(c);
            }
        }
    }
    putchar('\n');
}

// ── CLI arg → method + params mapping ────────────────────────────────────────
// Maps "app list" → "app.list", "key save --app X" → method="key" params={bundleID:X, combo:save}

typedef struct { const char *flag; const char *param_key; } FlagMap;

static const FlagMap FLAGS[] = {
    {"--app",       "bundleID"},
    {"--id",        "id"},
    {"--query",     "query"},
    {"--text",      "text"},
    {"--into",      "query"},
    {"--combo",     "combo"},
    {"--path",      "path"},
    {"--content",   "content"},
    {"--from",      "from"},
    {"--to",        "to"},
    {"--filter",    "filter"},
    {"--limit",     "limit"},
    {"--direction", "direction"},
    {"--amount",    "amount"},
    {"--domain",    "domain"},
    {"--key",       "key"},
    {"--value",     "value"},
    {"--name",      "name"},
    {"--folder",    "folder"},
    {"--body",      "body"},
    {"--title",     "title"},
    {"--url",       "url"},
    {"--service",   "service"},
    {NULL, NULL}
};

// ── main ─────────────────────────────────────────────────────────────────────

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "usage: macctl-fast <command> [subcommand] [--flag value ...]\n");
        fprintf(stderr, "  e.g: macctl-fast app list\n");
        fprintf(stderr, "       macctl-fast key save --app com.apple.TextEdit\n");
        return 1;
    }

    // Build method string from first 1-2 positional args
    char method[256] = "";
    int param_start = 1;

    strncpy(method, argv[1], sizeof(method)-1);
    // Check if argv[2] looks like a subcommand (not --flag)
    if (argc > 2 && argv[2][0] != '-') {
        size_t mlen = strlen(method);
        snprintf(method + mlen, sizeof(method) - mlen, ".%s", argv[2]);
        param_start = 3;
    }

    // Collect key=value params from --flag value pairs
    char *kv[64];
    int kv_count = 0;
    for (int i = param_start; i < argc && kv_count < 62; i++) {
        if (argv[i][0] == '-' && argv[i][1] == '-') {
            // Map --flag → param key
            const char *param_key = NULL;
            for (int f = 0; FLAGS[f].flag; f++) {
                if (strcmp(argv[i], FLAGS[f].flag) == 0) {
                    param_key = FLAGS[f].param_key;
                    break;
                }
            }
            if (!param_key) param_key = argv[i] + 2; // strip --
            if (i+1 < argc) {
                kv[kv_count++] = (char*)param_key;
                kv[kv_count++] = argv[++i];
            }
        }
    }

    // Build JSON request
    char request[65536];
    build_request(method, kv, kv_count, request, sizeof(request));

    // Connect to daemon
    char sock_path[512];
    get_socket_path(sock_path, sizeof(sock_path));

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        fprintf(stderr, "{\"success\":false,\"error\":{\"code\":5,\"message\":\"socket() failed\"}}\n");
        return 1;
    }
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path)-1);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd);
        fprintf(stderr, "{\"success\":false,\"error\":{\"code\":4,\"message\":\"Daemon not running. Run: macctl-daemon &\"}}\n");
        return 4;
    }

    // Send + receive
    if (send_framed(fd, request, strlen(request)) < 0) {
        close(fd); return 1;
    }
    size_t resp_len;
    char *response = recv_framed(fd, &resp_len);
    close(fd);

    if (!response) {
        fprintf(stderr, "{\"success\":false,\"error\":{\"code\":5,\"message\":\"No response from daemon\"}}\n");
        return 1;
    }

    pretty_print(response);

    // Check success for exit code
    int exit_code = 0;
    if (strstr(response, "\"success\":false") || strstr(response, "\"success\": false"))
        exit_code = 1;
    free(response);
    return exit_code;
}
