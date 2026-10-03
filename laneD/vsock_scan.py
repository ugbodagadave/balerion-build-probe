#!/usr/bin/env python3
"""laneD vsock_scan.py — direct AF_VSOCK scan + node h2/gRPC probe.
Used in the --security=insecure build step (seccomp removed) where direct
socket(AF_VSOCK) is expected to work. Bounded: three /23-scale port ranges
with per-connect timeout and global abort.
"""
import os, socket, subprocess, sys, time

AF_VSOCK = getattr(socket, "AF_VSOCK", 40)
VMADDR_CID_ANY = 0xFFFFFFFF
VMADDR_PORT_ANY = 0xFFFFFFFF
NODE = os.environ.get("NODE") or "/mise/shims/node"
BUDGET = int(os.environ.get("SCAN_BUDGET", "300"))
P_MAX = int(os.environ.get("SCAN_PMAX", "12000"))
open_ports = []

def out(s):
    print(s, flush=True)

def local_cid():
    try:
        s = socket.socket(AF_VSOCK, socket.SOCK_STREAM)
        s.bind((VMADDR_CID_ANY, VMADDR_PORT_ANY))
        cid, port = s.getsockname()
        s.close()
        out("LOCAL_CID=%s LOCAL_PORT=%s" % (cid, port))
        return cid
    except Exception as e:
        out("LOCAL_CID_ERR %r" % (e,))
        return None

def dev_vsock_cid():
    try:
        import ctypes
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        try: os.unlink("/dev/vsock")
        except Exception: pass
        r = libc.mknod(b"/dev/vsock", 0o20666, os.makedev(10, 241))
        if r != 0:
            out("dev_vsock mknod errno=%d" % ctypes.get_errno()); return None
        fd = os.open("/dev/vsock", os.O_RDONLY)
        cid = ctypes.c_uint(0)
        ctypes.set_errno(0)
        r2 = libc.ioctl(fd, 0x7b9, ctypes.byref(cid))
        out("dev_vsock ioctl GET_LOCAL_CID rc=%d errno=%d cid=%s" % (r2, ctypes.get_errno(), cid.value))
        os.close(fd)
        return cid.value if r2 == 0 else None
    except Exception as e:
        out("dev_vsock EXC %r" % (e,)); return None

def scan(cid, p0, p1):
    t0 = time.time(); consec_to = 0
    out("SCAN cid=%d %d-%d" % (cid, p0, p1))
    p = p0
    while p <= p1:
        if time.time() - t0 > BUDGET:
            out("SCAN_ABORT budget cid=%d at port=%d" % (cid, p)); break
        s = None
        try:
            s = socket.socket(AF_VSOCK, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect((cid, p))
            out("OPEN cid=%d port=%d local=%s" % (cid, p, s.getsockname()))
            open_ports.append((cid, p))
            consec_to = 0
        except OSError as e:
            if e.errno in (110, 4):
                consec_to += 1
                if consec_to > 30:
                    out("SCAN_ABORT timeouts cid=%d at port=%d" % (cid, p)); break
            else:
                consec_to = 0
                if e.errno not in (111, 104):
                    out("ERR cid=%d port=%d errno=%d %s" % (cid, p, e.errno, e.strerror))
        except Exception as e:
            out("SCAN_EXC cid=%d port=%d %r" % (cid, p, e)); break
        finally:
            if s is not None:
                try: s.close()
                except Exception: pass
        p += 1
    out("SCAN_DONE cid=%d" % cid)

def probe(cid, port):
    out("--- vsock probe cid=%d port=%d ---" % (cid, port))
    try:
        s = socket.socket(AF_VSOCK, socket.SOCK_STREAM)
        s.settimeout(5)
        s.connect((cid, port))
        fd = s.fileno()
        os.set_inheritable(fd, True)
        env = dict(os.environ)
        env.update(VSOCK_FD=str(fd), VSOCK_CID=str(cid), VSOCK_PORT=str(port))
        r = subprocess.run([NODE, "/laneD/vsock_probe.js"], env=env, timeout=120,
                           capture_output=True, text=True)
        out(r.stdout)
        if r.stderr.strip(): out("STDERR: " + r.stderr[:2000])
        s.close()
    except Exception as e:
        out("PROBE_EXC %r" % (e,))

def main():
    out("=== insecure-context fingerprint ===")
    for line in open("/proc/self/status"):
        if any(k in line for k in ("Seccomp", "Cap", "NoNewPrivs")):
            out(line.rstrip())
    out("=== direct AF_VSOCK ===")
    try:
        s = socket.socket(AF_VSOCK, socket.SOCK_STREAM)
        out("direct socket(AF_VSOCK) OK fd=%d" % s.fileno())
        s.close()
    except Exception as e:
        out("direct socket(AF_VSOCK) EXC %r" % (e,))
        out("=== direct socket failed; stopping ===")
        return
    lc = local_cid()
    dev_vsock_cid()
    scan(1, 1, P_MAX)          # vsock loopback
    scan(2, 1, P_MAX)          # host
    if lc is not None and lc not in (1, 2):
        scan(lc, 1, P_MAX)     # own CID
    for c in (3, 4, 5):
        for p in (1024, 3000, 4000):
            scan(c, p, p)
    out("=== probing %d open ports ===" % len(open_ports))
    for (c, p) in open_ports[:20]:
        probe(c, p)

if __name__ == "__main__":
    main()
