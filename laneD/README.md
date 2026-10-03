# Lane D — build microVM -> host control plane (vsock)

Authorized Railway security research (Bugcrowd, ireniumsecurity). Probe only; no destructive ops.

Files:
- `probe.sh` — build-step orchestrator (fingerprint, direct AF_VSOCK tests, socketcall bypass scans, node gRPC probes, otel socket probes).
- `vsock32.c` / `vsock32` — freestanding i386 tool. Creates AF_VSOCK sockets via `socketcall(2)`.
  Rationale: the stock Docker/containerd seccomp profile blocks `socket(AF_VSOCK)` for the direct
  x86_64 syscall but **allows `socketcall` unconditionally** (its own comments note the 32-bit ABI
  cannot be restricted). This tests whether the build container's filter is the stock profile.
- `vsock_probe.js` — HTTP/2 + gRPC probe over an inherited connected vsock fd (node builtins only).
- `otel_probe2.js` — checks whether control-plane gRPC services are multiplexed on /dev/otel-grpc.sock.
- `direct_vsock.py` — direct socket tests, mknod /dev/vsock + IOCTL_VM_SOCKETS_GET_LOCAL_CID.

Results are echoed to build stdout and exfiltrated to webhook.site (laneD token).
