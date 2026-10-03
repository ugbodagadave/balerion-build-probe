#!/usr/bin/env python3
"""laneD direct_vsock.py — direct (non-socketcall) AF_VSOCK tests + local CID via /dev/vsock."""
import ctypes, os, socket, sys

def section(t):
    print("\n=== %s ===" % t)

def main():
    section("direct AF_VSOCK tests")
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    # glibc socket()
    ctypes.set_errno(0)
    r = libc.socket(40, 1, 0)
    print("libc socket(AF_VSOCK=40, SOCK_STREAM, 0) =", r, "errno=", ctypes.get_errno())
    # python socket module
    try:
        s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        print("python AF_VSOCK socket =", s.fileno())
        s.close()
    except Exception as e:
        print("python AF_VSOCK socket EXC:", repr(e))
    # raw x86_64 socket syscall (41)
    ctypes.set_errno(0)
    r2 = libc.syscall(41, 40, 1, 0)
    print("raw syscall(41 socket, 40,1,0) =", r2, "errno=", ctypes.get_errno())
    # x32 ABI socket (41 | __X32_SYSCALL_BIT)
    ctypes.set_errno(0)
    r3 = libc.syscall(41 | 0x40000000, 40, 1, 0)
    print("x32 socket(0x40000029,40,1,0) =", r3, "errno=", ctypes.get_errno())
    # i386 socketcall from 64-bit mode (not valid on x86_64 table; 102=getuid)
    ctypes.set_errno(0)
    r4 = libc.syscall(102, 1, 0)
    print("syscall(102 in 64-bit mode) =", r4, "errno=", ctypes.get_errno())

    section("mknod /dev/vsock + IOCTL_VM_SOCKETS_GET_LOCAL_CID")
    try:
        os.unlink("/dev/vsock")
    except Exception:
        pass
    ctypes.set_errno(0)
    r5 = libc.mknod(b"/dev/vsock", 0o20666, os.makedev(10, 241))
    e5 = ctypes.get_errno()
    print("mknod(/dev/vsock, c 10 241) =", r5, "errno=", e5)
    if r5 == 0:
        try:
            fd = os.open("/dev/vsock", os.O_RDONLY)
            cid = ctypes.c_uint(0)
            ctypes.set_errno(0)
            r6 = libc.ioctl(fd, 0x7b9, ctypes.byref(cid))  # _IO(7, 0xb9)
            print("ioctl GET_LOCAL_CID =", r6, "errno=", ctypes.get_errno(), "cid=", cid.value)
            os.close(fd)
        except Exception as e:
            print("ioctl EXC:", repr(e))

    section("seccomp / AppArmor / caps")
    for line in open("/proc/self/status"):
        if any(k in line for k in ("Cap", "Seccomp", "NoNewPrivs")):
            print(line.rstrip())
    try:
        print("attr/current:", open("/proc/self/attr/current").read().strip())
    except Exception as e:
        print("attr/current EXC:", e)

if __name__ == "__main__":
    main()
