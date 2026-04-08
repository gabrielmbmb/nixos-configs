#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  wake-until-ssh.sh <mac-address> <host-or-ip> [port] [interval-seconds] [max-wait-seconds] [ssh-target]

Examples:
  wake-until-ssh.sh 00:11:22:33:44:55 192.168.1.42
  wake-until-ssh.sh 00:11:22:33:44:55 ml3090.local 22 5 600
  wake-until-ssh.sh 00:11:22:33:44:55 192.168.1.42 22 5 600 gabriel@ml3090.local

Defaults:
  port = 22
  interval-seconds = 5
  max-wait-seconds = 300
  ssh-target = host-or-ip

Behavior:
  Sends Wake-on-LAN packets until SSH is reachable, then connects via ssh.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

MAC="$1"
HOST="$2"
PORT="${3:-22}"
INTERVAL="${4:-5}"
MAX_WAIT="${5:-300}"
SSH_TARGET="${6:-$HOST}"

if ! command -v wakeonlan >/dev/null 2>&1; then
  echo "Error: wakeonlan is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "Error: ssh is not installed or not in PATH." >&2
  exit 1
fi

check_ssh_port() {
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$HOST" "$PORT" >/dev/null 2>&1
  else
    timeout 2 bash -c "</dev/tcp/$HOST/$PORT" >/dev/null 2>&1
  fi
}

connect_ssh() {
  echo "🔐 Connecting to $SSH_TARGET on port $PORT..."
  exec ssh -p "$PORT" "$SSH_TARGET"
}

start_ts=$(date +%s)
attempt=0

if check_ssh_port; then
  echo "✅ $HOST:$PORT is already reachable."
  connect_ssh
fi

while true; do
  attempt=$((attempt + 1))
  elapsed=$(( $(date +%s) - start_ts ))

  if (( elapsed > MAX_WAIT )); then
    echo "❌ Timed out after ${MAX_WAIT}s waiting for $HOST:$PORT" >&2
    exit 1
  fi

  echo "[$attempt] Sending Wake-on-LAN magic packet to $MAC (elapsed: ${elapsed}s)..."
  wakeonlan "$MAC" >/dev/null

  sleep "$INTERVAL"

  if check_ssh_port; then
    total=$(( $(date +%s) - start_ts ))
    echo "✅ $HOST is operational (port $PORT open) after ${total}s."
    connect_ssh
  fi
done
