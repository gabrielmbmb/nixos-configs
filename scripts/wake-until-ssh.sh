#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  wake-until-ssh.sh <mac-address> [host-or-ip|auto] [port] [interval-seconds] [max-wait-seconds] [ssh-target]

Examples:
  wake-until-ssh.sh 00:11:22:33:44:55
  wake-until-ssh.sh 00:11:22:33:44:55 auto
  wake-until-ssh.sh 00:11:22:33:44:55 192.168.1.42
  wake-until-ssh.sh 00:11:22:33:44:55 ml3090.local 22 5 600
  wake-until-ssh.sh 00:11:22:33:44:55 auto 22 5 600 gabriel@ml3090.local

Defaults:
  host-or-ip = auto (resolve from MAC via ARP/neighbor table)
  port = 22
  interval-seconds = 5
  max-wait-seconds = 300
  ssh-target = resolved/provided host-or-ip

Behavior:
  Sends Wake-on-LAN packets until SSH is reachable, then connects via ssh.

Notes:
  Auto-resolution works only when the target IP appears in your ARP/neighbor table
  (typically same L2 network/VLAN).
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

MAC="$1"
HOST_INPUT="${2:-auto}"
PORT="${3:-22}"
INTERVAL="${4:-5}"
MAX_WAIT="${5:-300}"
SSH_TARGET="${6:-}"

AUTO_RESOLVE=0
HOST="$HOST_INPUT"
if [[ -z "$HOST_INPUT" || "$HOST_INPUT" == "auto" || "$HOST_INPUT" == "-" ]]; then
  AUTO_RESOLVE=1
  HOST=""
fi

if ! command -v wakeonlan >/dev/null 2>&1; then
  echo "Error: wakeonlan is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "Error: ssh is not installed or not in PATH." >&2
  exit 1
fi

if (( AUTO_RESOLVE )) && ! command -v arp >/dev/null 2>&1 && ! command -v ip >/dev/null 2>&1; then
  echo "Error: neither 'arp' nor 'ip' is available for MAC -> IP auto-resolution." >&2
  exit 1
fi

normalize_mac() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '0-9a-f'
}

MAC_NORM="$(normalize_mac "$MAC")"
if [[ ${#MAC_NORM} -ne 12 ]]; then
  echo "Error: invalid MAC address format: $MAC" >&2
  exit 1
fi

resolve_host_from_mac() {
  local ip=""

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip neigh 2>/dev/null | awk -v want="$MAC_NORM" '
      function norm(s) { gsub(/[^0-9A-Fa-f]/, "", s); return tolower(s) }
      NF >= 5 {
        mac = norm($5)
        if (mac == want) { print $1; exit }
      }
    ')"
  fi

  if [[ -z "$ip" ]] && command -v arp >/dev/null 2>&1; then
    ip="$(arp -an 2>/dev/null | awk -v want="$MAC_NORM" '
      function norm(s) { gsub(/[^0-9A-Fa-f]/, "", s); return tolower(s) }
      {
        ip = ""
        mac = ""

        if (match($0, /\(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\)/, m)) {
          ip = m[1]
        } else if (match($0, /^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/, m)) {
          ip = m[1]
        }

        if (match($0, /([0-9A-Fa-f]{1,2}([:\.-][0-9A-Fa-f]{1,2}){5})/, mm)) {
          mac = norm(mm[1])
        }

        if (ip != "" && mac == want) { print ip; exit }
      }
    ')"
  fi

  [[ -n "$ip" ]] && printf '%s\n' "$ip"
}

refresh_host_from_mac() {
  if (( ! AUTO_RESOLVE )); then
    return
  fi

  local resolved=""
  resolved="$(resolve_host_from_mac || true)"

  if [[ -n "$resolved" && "$resolved" != "${HOST:-}" ]]; then
    HOST="$resolved"
    echo "🔎 Resolved $MAC -> $HOST"
  fi
}

check_ssh_port() {
  [[ -n "${HOST:-}" ]] || return 1

  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$HOST" "$PORT" >/dev/null 2>&1
  else
    timeout 2 bash -c "</dev/tcp/$HOST/$PORT" >/dev/null 2>&1
  fi
}

connect_ssh() {
  local target="${SSH_TARGET:-$HOST}"

  if [[ -z "$target" ]]; then
    echo "Error: SSH target is empty. Provide [ssh-target] or wait until host resolves." >&2
    exit 1
  fi

  echo "🔐 Connecting to $target on port $PORT..."
  exec ssh -p "$PORT" "$target"
}

start_ts=$(date +%s)
attempt=0
waiting_for_resolution_logged=0

refresh_host_from_mac
if check_ssh_port; then
  echo "✅ ${HOST}:$PORT is already reachable."
  connect_ssh
fi

while true; do
  attempt=$((attempt + 1))
  elapsed=$(( $(date +%s) - start_ts ))

  if (( elapsed > MAX_WAIT )); then
    if [[ -n "${HOST:-}" ]]; then
      echo "❌ Timed out after ${MAX_WAIT}s waiting for $HOST:$PORT" >&2
    else
      echo "❌ Timed out after ${MAX_WAIT}s waiting to resolve IP for MAC $MAC" >&2
    fi
    exit 1
  fi

  echo "[$attempt] Sending Wake-on-LAN magic packet to $MAC (elapsed: ${elapsed}s)..."
  wakeonlan "$MAC" >/dev/null

  sleep "$INTERVAL"

  refresh_host_from_mac
  if [[ -z "${HOST:-}" ]]; then
    if (( waiting_for_resolution_logged == 0 )); then
      echo "⌛ Waiting for IP resolution from MAC $MAC..."
      waiting_for_resolution_logged=1
    fi
    continue
  fi

  waiting_for_resolution_logged=0

  if check_ssh_port; then
    total=$(( $(date +%s) - start_ts ))
    echo "✅ $HOST is operational (port $PORT open) after ${total}s."
    connect_ssh
  fi
done
