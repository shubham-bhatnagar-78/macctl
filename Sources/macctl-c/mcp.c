/*
 * macctl-mcp-fast — ultra-thin C MCP server for macctl daemon.
 *
 * Architecture:
 *   Claude → stdin (MCP JSON-RPC) → this binary → Unix socket → macctl-daemon
 *
 * vs macctl-mcp (Swift):
 *   Swift: 4 JSON encode/decode layers, ~28ms/call
 *   C:     2 layers (MCP parse + MCP format), ~8ms/call
 *
 * MCP protocol: https://modelcontextprotocol.io
 * Transport: stdio (newline-delimited JSON)
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

// ── Socket helpers (same as macctl-fast) ─────────────────────────────────────

static void get_socket_path(char *buf, size_t len) {
    const char *home = getenv("HOME");
    if (!home) { struct passwd *pw = getpwuid(getuid()); home = pw ? pw->pw_dir : "/tmp"; }
    snprintf(buf, len, "%s/Library/Application Support/macctl/daemon.sock", home);
}

static int sock_fd = -1;  // persistent connection

static int ensure_connected(void) {
    if (sock_fd >= 0) return 0;
    char path[512]; get_socket_path(path, sizeof(path));
    sock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock_fd < 0) return -1;
    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path)-1);
    if (connect(sock_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(sock_fd); sock_fd = -1; return -1;
    }
    return 0;
}

static int send_framed(const char *data, size_t len) {
    uint32_t net_len = htonl((uint32_t)len);
    if (write(sock_fd, &net_len, 4) != 4) return -1;
    if ((size_t)write(sock_fd, data, len) != len) return -1;
    return 0;
}

static char *recv_framed(size_t *out_len) {
    uint32_t net_len; ssize_t total = 0, n;
    while (total < 4) {
        n = read(sock_fd, ((char*)&net_len)+total, 4-total);
        if (n <= 0) { close(sock_fd); sock_fd=-1; return NULL; }
        total += n;
    }
    uint32_t msg_len = ntohl(net_len);
    if (msg_len > 16*1024*1024) return NULL;
    char *buf = malloc(msg_len+1); if (!buf) return NULL;
    total = 0;
    while ((size_t)total < msg_len) {
        n = read(sock_fd, buf+total, msg_len-total);
        if (n <= 0) { free(buf); close(sock_fd); sock_fd=-1; return NULL; }
        total += n;
    }
    buf[msg_len] = '\0';
    *out_len = msg_len;
    return buf;
}

// ── Simple JSON helpers ───────────────────────────────────────────────────────

static void json_esc(const char *s, char *d, size_t n) {
    size_t i=0,j=0;
    while(s[i]&&j<n-4){
        char c=s[i++];
        if(c=='"'){d[j++]='\\';d[j++]='"';}
        else if(c=='\\'){d[j++]='\\';d[j++]='\\';}
        else if(c=='\n'){d[j++]='\\';d[j++]='n';}
        else if(c=='\r'){d[j++]='\\';d[j++]='r';}
        else if(c=='\t'){d[j++]='\\';d[j++]='t';}
        else{d[j++]=c;}
    }
    d[j]='\0';
}

// Extract string value for a key from flat JSON (simple, not recursive)
static char *jget(const char *json, const char *key, char *out, size_t out_len) {
    char search[128]; snprintf(search, sizeof(search), "\"%s\"", key);
    const char *p = strstr(json, search);
    if (!p) { out[0]='\0'; return NULL; }
    p += strlen(search);
    while(*p==' '||*p==':') p++;
    if (*p == '"') {
        p++; size_t i=0;
        while(*p && *p!='"' && i<out_len-2) {
            if(*p=='\\' && *(p+1)) { p++; out[i++]=*p++; } else out[i++]=*p++;
        }
        out[i]='\0'; return out;
    }
    // number or keyword
    size_t i=0;
    while(*p && *p!=',' && *p!='}' && *p!=']' && *p!=' ' && i<out_len-1) out[i++]=*p++;
    out[i]='\0'; return out;
}

// ── Tool list ────────────────────────────────────────────────────────────────
#include "tools.h"


// Build daemon JSON-RPC from MCP tool name + JSON args object
static int build_daemon_rpc(const char *tool, const char *args_json, char *out, size_t out_len) {
    char v[512]={0}, method[128]={0};
    char a1[256]={0},a2[256]={0},a3[256]={0},a4[256]={0},a5[256]={0};

    // Extract common args
    jget(args_json,"app",      a1, sizeof(a1));
    jget(args_json,"bundleID", a2, sizeof(a2));
    const char *bid = *a1 ? a1 : a2;

    #define RPC(m, params) do { \
        snprintf(method, sizeof(method), "%s", m); \
        snprintf(out, out_len, "{\"jsonrpc\":\"2.0\",\"id\":\"m\",\"method\":\"%s\",\"params\":{%s}}", m, params); \
        return (int)strlen(out); \
    } while(0)

    char ea[256]={0},eb[256]={0},ec[256]={0},ed[256]={0},ee[256]={0};
    json_esc(bid, ea, sizeof(ea));

    if (!strcmp(tool,"macctl_app_list"))   { RPC("app.list",""); }
    if (!strcmp(tool,"macctl_app_launch")) { RPC("app.launch",snprintf(v,sizeof(v),"\"bundleID\":\"%s\"",ea)?v:""); }
    if (!strcmp(tool,"macctl_app_quit")) {
        jget(args_json,"force",a3,sizeof(a3));
        snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"force\":%s",ea,*a3?a3:"false");
        RPC("app.quit",v);
    }
    if (!strcmp(tool,"macctl_click")) {
        char eid[64]={0}; jget(args_json,"id",eid,sizeof(eid));
        char query[256]={0}; jget(args_json,"query",query,sizeof(query));
        char xv[32]={0},yv[32]={0}; jget(args_json,"x",xv,sizeof(xv)); jget(args_json,"y",yv,sizeof(yv));
        json_esc(query,ec,sizeof(ec)); json_esc(eid,ed,sizeof(ed));
        if (*eid) snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"elementId\":\"%s\"",ea,ed);
        else if (*query) snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"query\":\"%s\"",ea,ec);
        else snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"x\":%s,\"y\":%s",ea,xv,yv);
        RPC("click",v);
    }
    if (!strcmp(tool,"macctl_type")) {
        char text[512]={0},into[256]={0};
        jget(args_json,"text",text,sizeof(text)); jget(args_json,"into",into,sizeof(into));
        json_esc(text,ec,sizeof(ec)); json_esc(into,ed,sizeof(ed));
        if (*into) snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"text\":\"%s\",\"query\":\"%s\"",ea,ec,ed);
        else snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"text\":\"%s\"",ea,ec);
        RPC("type",v);
    }
    if (!strcmp(tool,"macctl_key")) {
        char combo[128]={0}; jget(args_json,"combo",combo,sizeof(combo));
        json_esc(combo,ec,sizeof(ec));
        snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"combo\":\"%s\"",ea,ec);
        RPC("key",v);
    }
    if (!strcmp(tool,"macctl_see"))        { snprintf(v,sizeof(v),"\"bundleID\":\"%s\"",ea); RPC("see",v); }
    if (!strcmp(tool,"macctl_screenshot")) { snprintf(v,sizeof(v),*bid?"\"bundleID\":\"%s\"":"",ea); RPC("screenshot",v); }
    if (!strcmp(tool,"macctl_scroll")) {
        char dir[32]={0},amt[32]={0};
        jget(args_json,"direction",dir,sizeof(dir)); jget(args_json,"amount",amt,sizeof(amt));
        snprintf(v,sizeof(v),"\"bundleID\":\"%s\",\"direction\":\"%s\",\"amount\":%s",ea,*dir?dir:"down",*amt?amt:"3");
        RPC("scroll",v);
    }
    if (!strcmp(tool,"macctl_shell")) {
        char cmd[1024]={0},to[32]={0};
        jget(args_json,"command",cmd,sizeof(cmd)); jget(args_json,"timeout",to,sizeof(to));
        json_esc(cmd,ec,sizeof(ec));
        if(*to) snprintf(v,sizeof(v),"\"command\":\"%s\",\"timeout\":%s",ec,to);
        else snprintf(v,sizeof(v),"\"command\":\"%s\"",ec);
        RPC("shell",v);
    }
    if (!strcmp(tool,"macctl_system_status")) { RPC("system.status",""); }
    if (!strcmp(tool,"macctl_system_volume")) {
        char val[32]={0}; jget(args_json,"value",val,sizeof(val));
        if(*val) snprintf(v,sizeof(v),"\"value\":%s",val); else v[0]='\0';
        RPC("system.volume",v);
    }
    if (!strcmp(tool,"macctl_file_read"))  { char p[512]={0}; jget(args_json,"path",p,sizeof(p)); json_esc(p,ec,sizeof(ec)); snprintf(v,sizeof(v),"\"path\":\"%s\"",ec); RPC("file.read",v); }
    if (!strcmp(tool,"macctl_file_write")) {
        char p[512]={0},c2[4096]={0}; jget(args_json,"path",p,sizeof(p)); jget(args_json,"content",c2,sizeof(c2));
        json_esc(p,ec,sizeof(ec)); json_esc(c2,ed,sizeof(ed));
        snprintf(v,sizeof(v),"\"path\":\"%s\",\"content\":\"%s\"",ec,ed); RPC("file.write",v);
    }
    if (!strcmp(tool,"macctl_file_list"))  { char p[512]={0}; jget(args_json,"path",p,sizeof(p)); json_esc(p,ec,sizeof(ec)); snprintf(v,sizeof(v),"\"path\":\"%s\"",*p?ec:"."); RPC("file.list",v); }
    if (!strcmp(tool,"macctl_file_stat"))  { char p[512]={0}; jget(args_json,"path",p,sizeof(p)); json_esc(p,ec,sizeof(ec)); snprintf(v,sizeof(v),"\"path\":\"%s\"",ec); RPC("file.stat",v); }
    if (!strcmp(tool,"macctl_clipboard_read"))  { RPC("clipboard.read",""); }
    if (!strcmp(tool,"macctl_clipboard_write")) {
        char tx[512]={0},ht[512]={0}; jget(args_json,"text",tx,sizeof(tx)); jget(args_json,"html",ht,sizeof(ht));
        json_esc(*ht?ht:tx,ec,sizeof(ec));
        if(*ht) snprintf(v,sizeof(v),"\"html\":\"%s\"",ec); else snprintf(v,sizeof(v),"\"text\":\"%s\"",ec);
        RPC("clipboard.write",v);
    }
    if (!strcmp(tool,"macctl_calendar_events")) {
        char s[32]={0},e[32]={0}; jget(args_json,"startTimestamp",s,sizeof(s)); jget(args_json,"endTimestamp",e,sizeof(e));
        if(*s&&*e) snprintf(v,sizeof(v),"\"startTimestamp\":%s,\"endTimestamp\":%s",s,e);
        else if(*s) snprintf(v,sizeof(v),"\"startTimestamp\":%s",s);
        else v[0]='\0';
        RPC("calendar.fetch-events",v);
    }
    if (!strcmp(tool,"macctl_calendar_create")) {
        char ti[256]={0},st[32]={0},et[32]={0},no[512]={0},lo[256]={0};
        jget(args_json,"title",ti,sizeof(ti)); jget(args_json,"startTimestamp",st,sizeof(st));
        jget(args_json,"endTimestamp",et,sizeof(et)); jget(args_json,"notes",no,sizeof(no)); jget(args_json,"location",lo,sizeof(lo));
        json_esc(ti,ec,sizeof(ec)); json_esc(no,ed,sizeof(ed)); json_esc(lo,ee,sizeof(ee));
        snprintf(v,sizeof(v),"\"title\":\"%s\",\"startTimestamp\":%s,\"endTimestamp\":%s",ec,st,et);
        if(*no){char tmp[4096]; snprintf(tmp,sizeof(tmp),"%s,\"notes\":\"%s\"",v,ed); strncpy(v,tmp,sizeof(v)-1);}
        if(*lo){char tmp[4096]; snprintf(tmp,sizeof(tmp),"%s,\"location\":\"%s\"",v,ee); strncpy(v,tmp,sizeof(v)-1);}
        RPC("calendar.create-event",v);
    }
    if (!strcmp(tool,"macctl_reminders_list"))   { RPC("reminder.fetch","{\"completed\":false}"); }
    if (!strcmp(tool,"macctl_reminders_create")) {
        char ti[256]={0},no[512]={0}; jget(args_json,"title",ti,sizeof(ti)); jget(args_json,"notes",no,sizeof(no));
        json_esc(ti,ec,sizeof(ec)); json_esc(no,ed,sizeof(ed));
        if(*no) snprintf(v,sizeof(v),"\"title\":\"%s\",\"notes\":\"%s\"",ec,ed);
        else snprintf(v,sizeof(v),"\"title\":\"%s\"",ec);
        RPC("reminder.create",v);
    }
    if (!strcmp(tool,"macctl_contacts_search")) {
        char q[256]={0},lim[32]={0}; jget(args_json,"query",q,sizeof(q)); jget(args_json,"limit",lim,sizeof(lim));
        json_esc(q,ec,sizeof(ec));
        snprintf(v,sizeof(v),"\"query\":\"%s\",\"limit\":%s",ec,*lim?lim:"25");
        RPC("contact.search",v);
    }
    if (!strcmp(tool,"macctl_window_list")) {
        if(*bid) snprintf(v,sizeof(v),"\"bundleID\":\"%s\"",ea); else v[0]='\0';
        RPC("window.list",v);
    }
    if (!strcmp(tool,"macctl_window_set_bounds")) {
        char wid[32]={0},x[32]={0},y[32]={0},w[32]={0},h[32]={0};
        jget(args_json,"windowID",wid,sizeof(wid)); jget(args_json,"x",x,sizeof(x));
        jget(args_json,"y",y,sizeof(y)); jget(args_json,"width",w,sizeof(w)); jget(args_json,"height",h,sizeof(h));
        snprintf(v,sizeof(v),"\"windowID\":%s,\"x\":%s,\"y\":%s,\"width\":%s,\"height\":%s",wid,x,y,w,h);
        RPC("window.set-bounds",v);
    }
    if (!strcmp(tool,"macctl_window_tile")) {
        char wid[32]={0},side[16]={0};
        jget(args_json,"windowID",wid,sizeof(wid)); jget(args_json,"side",side,sizeof(side));
        if(!strcmp(side,"right")) { snprintf(v,sizeof(v),"\"windowID\":%s",wid); RPC("window.tile-right",v); }
        else { snprintf(v,sizeof(v),"\"windowID\":%s",wid); RPC("window.tile-left",v); }
    }
    if (!strcmp(tool,"macctl_window_fullscreen")) {
        char wid[32]={0},en[16]={0}; jget(args_json,"windowID",wid,sizeof(wid)); jget(args_json,"enabled",en,sizeof(en));
        snprintf(v,sizeof(v),"\"windowID\":%s,\"enabled\":%s",wid,*en?en:"true"); RPC("window.fullscreen",v);
    }
    if (!strcmp(tool,"macctl_process_list")) {
        char f[128]={0}; jget(args_json,"filter",f,sizeof(f));
        if(*f){json_esc(f,ec,sizeof(ec)); snprintf(v,sizeof(v),"\"filter\":\"%s\"",ec);} else v[0]='\0';
        RPC("process.list",v);
    }
    if (!strcmp(tool,"macctl_process_kill")) {
        char pid[32]={0},nm[128]={0},fo[16]={0};
        jget(args_json,"pid",pid,sizeof(pid)); jget(args_json,"name",nm,sizeof(nm)); jget(args_json,"force",fo,sizeof(fo));
        if(*pid) snprintf(v,sizeof(v),"\"pid\":%s,\"force\":%s",pid,*fo?fo:"false");
        else { json_esc(nm,ec,sizeof(ec)); snprintf(v,sizeof(v),"\"name\":\"%s\",\"force\":%s",ec,*fo?fo:"false"); }
        RPC("process.kill",v);
    }
    if (!strcmp(tool,"macctl_spotlight_search")) {
        char q[256]={0},lim[32]={0}; jget(args_json,"query",q,sizeof(q)); jget(args_json,"limit",lim,sizeof(lim));
        json_esc(q,ec,sizeof(ec));
        snprintf(v,sizeof(v),"\"query\":\"%s\",\"limit\":%s",ec,*lim?lim:"50"); RPC("spotlight.search",v);
    }
    if (!strcmp(tool,"macctl_screen_list"))          { RPC("screen.list",""); }
    if (!strcmp(tool,"macctl_input_source_list"))    { RPC("input-source.list",""); }
    if (!strcmp(tool,"macctl_input_source_select"))  {
        char id[128]={0}; jget(args_json,"id",id,sizeof(id)); json_esc(id,ec,sizeof(ec));
        snprintf(v,sizeof(v),"\"id\":\"%s\"",ec); RPC("input-source.select",v);
    }
    if (!strcmp(tool,"macctl_defaults_read")) {
        char dom[256]={0},key[256]={0}; jget(args_json,"domain",dom,sizeof(dom)); jget(args_json,"key",key,sizeof(key));
        json_esc(dom,ec,sizeof(ec)); json_esc(key,ed,sizeof(ed));
        snprintf(v,sizeof(v),"\"domain\":\"%s\",\"key\":\"%s\"",ec,ed); RPC("defaults.read",v);
    }
    if (!strcmp(tool,"macctl_defaults_write")) {
        char dom[256]={0},key[256]={0},val[512]={0};
        jget(args_json,"domain",dom,sizeof(dom)); jget(args_json,"key",key,sizeof(key)); jget(args_json,"value",val,sizeof(val));
        json_esc(dom,ec,sizeof(ec)); json_esc(key,ed,sizeof(ed)); json_esc(val,ee,sizeof(ee));
        snprintf(v,sizeof(v),"\"domain\":\"%s\",\"key\":\"%s\",\"value\":\"%s\"",ec,ed,ee); RPC("defaults.write",v);
    }

    // Unknown tool
    snprintf(out, out_len, "UNKNOWN");
    return -1;
}

// ── MCP response formatters ───────────────────────────────────────────────────

static void send_mcp(const char *id, const char *result_json) {
    printf("{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":%s}\n", id, result_json);
    fflush(stdout);
}

static void send_error(const char *id, int code, const char *msg) {
    char esc[512]; json_esc(msg, esc, sizeof(esc));
    printf("{\"jsonrpc\":\"2.0\",\"id\":%s,\"error\":{\"code\":%d,\"message\":\"%s\"}}\n", id, code, esc);
    fflush(stdout);
}

// ── Main loop ─────────────────────────────────────────────────────────────────

int main(void) {
    char line[65536];
    setvbuf(stdout, NULL, _IOLBF, 0);

    while (fgets(line, sizeof(line), stdin)) {
        // Strip newline
        size_t len = strlen(line);
        while (len > 0 && (line[len-1]=='\n'||line[len-1]=='\r')) line[--len]='\0';
        if (!len) continue;

        char method[128]={0}, id[64]={0};
        jget(line, "method", method, sizeof(method));
        jget(line, "id", id, sizeof(id));
        // id might be number — keep as-is for response

        if (!strcmp(method, "initialize")) {
            send_mcp(id,
                "{\"protocolVersion\":\"2024-11-05\","
                "\"serverInfo\":{\"name\":\"macctl-fast\",\"version\":\"1.0.0\"},"
                "\"capabilities\":{\"tools\":{\"listChanged\":false}}}");

        } else if (!strcmp(method, "tools/list")) {
            char resp[1024];
            snprintf(resp, sizeof(resp), "{\"tools\":%s}", TOOLS_JSON);
            send_mcp(id, resp);

        } else if (!strcmp(method, "tools/call")) {
            char tool[128]={0}, args_json[16384]={0};
            jget(line, "name", tool, sizeof(tool));

            // Extract arguments object
            const char *ap = strstr(line, "\"arguments\"");
            if (ap) {
                ap = strchr(ap, '{');
                if (ap) {
                    int depth=0; size_t i=0, j=0;
                    do {
                        char c = ap[i++];
                        if(c=='{')depth++; else if(c=='}')depth--;
                        args_json[j++]=c;
                        if(!depth) break;
                    } while(ap[i] && j<sizeof(args_json)-1);
                    args_json[j]='\0';
                }
            }
            if (!args_json[0]) strcpy(args_json, "{}");

            // Build and forward to daemon
            char rpc_req[65536]={0};
            int rpc_len = build_daemon_rpc(tool, args_json, rpc_req, sizeof(rpc_req));

            if (rpc_len < 0) {
                char esc[256]; json_esc(tool, esc, sizeof(esc));
                char content[512]; snprintf(content, sizeof(content),
                    "{\"content\":[{\"type\":\"text\",\"text\":\"Unknown tool: %s\"}],\"isError\":true}", esc);
                send_mcp(id, content);
                continue;
            }

            if (ensure_connected() < 0) {
                send_mcp(id,
                    "{\"content\":[{\"type\":\"text\",\"text\":\"Error: macctl daemon not running. Run: macctl-daemon &\"}],"
                    "\"isError\":true}");
                continue;
            }

            if (send_framed(rpc_req, rpc_len) < 0) {
                // Retry once on broken pipe
                close(sock_fd); sock_fd=-1;
                if (ensure_connected()<0 || send_framed(rpc_req,rpc_len)<0) {
                    send_mcp(id,"{\"content\":[{\"type\":\"text\",\"text\":\"Error: send failed\"}],\"isError\":true}");
                    continue;
                }
            }

            size_t resp_len=0;
            char *resp = recv_framed(&resp_len);
            if (!resp) {
                send_mcp(id,"{\"content\":[{\"type\":\"text\",\"text\":\"Error: no response\"}],\"isError\":true}");
                continue;
            }

            // Extract data field from daemon response
            const char *dp = strstr(resp, "\"data\"");
            const char *data_str = "{}";
            char data_buf[32768]={0};
            if (dp) {
                dp = strchr(dp, ':');
                if (dp) {
                    dp++;
                    while(*dp==' ') dp++;
                    if (*dp=='{' || *dp=='[') {
                        int depth=0; size_t i=0,j=0;
                        do {
                            char c=dp[i++];
                            if(c=='{'||c=='[')depth++;
                            else if(c=='}'||c==']')depth--;
                            data_buf[j++]=c;
                            if(!depth) break;
                        } while(dp[i]&&j<sizeof(data_buf)-2);
                        data_buf[j]='\0';
                        data_str = data_buf;
                    } else if (*dp=='"') {
                        // string value
                        size_t i=1,j=1; data_buf[0]='"';
                        while(dp[i]&&dp[i]!='"'&&j<sizeof(data_buf)-2){
                            if(dp[i]=='\\'){data_buf[j++]=dp[i++];} data_buf[j++]=dp[i++];
                        }
                        data_buf[j++]='"'; data_buf[j]='\0';
                        data_str = data_buf;
                    }
                }
            }

            int is_error = strstr(resp,"\"success\":false")||strstr(resp,"\"success\": false") ? 1 : 0;
            const char *text = data_str;
            char errmsg[512]={0};
            if (is_error) {
                const char *ep = strstr(resp,"\"message\"");
                if (ep) { ep=strchr(ep,'"'); if(ep){ep++;ep=strchr(ep,'"');if(ep){ep++;jget(resp,"message",errmsg,sizeof(errmsg));}}}
                if(!errmsg[0]) strcpy(errmsg,"Operation failed");
                text = errmsg;
            }

            char esc_text[16384]={0};
            json_esc(text, esc_text, sizeof(esc_text));

            char content[32768];
            snprintf(content, sizeof(content),
                "{\"content\":[{\"type\":\"text\",\"text\":\"%s\"}],\"isError\":%s}",
                esc_text, is_error ? "true" : "false");
            send_mcp(id, content);
            free(resp);

        } else if (!strcmp(method,"ping")) {
            send_mcp(id, "{}");
        } else if (!strcmp(method,"notifications/initialized")||!strcmp(method,"notifications/cancelled")) {
            // no response
        } else {
            char esc[128]; json_esc(method, esc, sizeof(esc));
            send_error(id, -32601, esc);
        }
    }
    if (sock_fd >= 0) close(sock_fd);
    return 0;
}
