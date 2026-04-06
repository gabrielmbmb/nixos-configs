#!/usr/bin/env bash
set -euo pipefail

failures=0

ok() {
  echo "[OK] $*"
}

warn() {
  echo "[WARN] $*"
}

err() {
  echo "[ERROR] $*"
  failures=$((failures + 1))
}

run() {
  local label="$1"
  shift
  printf "\n==> %s\n" "$label"
  if "$@"; then
    ok "$label"
  else
    err "$label"
  fi
}

echo "ML workstation post-install checks"
echo "User: $(whoami)"
echo "Host: $(hostname)"

# 1) NVIDIA driver + GPU visibility
run "nvidia-smi is available and sees GPUs" nvidia-smi -L

# 2) CUDA toolkit is installed and is 13.0
if command -v nvcc >/dev/null 2>&1; then
  printf "\n==> CUDA toolkit version check\n"
  nvcc_out="$(nvcc --version || true)"
  echo "$nvcc_out"
  if echo "$nvcc_out" | grep -q "release 13.0"; then
    ok "CUDA toolkit reports release 13.0"
  else
    err "CUDA toolkit is not reporting release 13.0"
  fi
else
  err "nvcc not found in PATH"
fi

# 3) llama.cpp binary presence
run "llama-cpp CLI is available" bash -lc 'llama --help >/dev/null'

# 4) Docker daemon availability
if groups "$(whoami)" | grep -qw docker; then
  ok "Current user is in docker group"
else
  warn "Current user is NOT in docker group (docker may require sudo)"
fi

if docker info >/dev/null 2>&1; then
  ok "Docker daemon is reachable"
else
  err "Docker daemon is reachable"
fi

# 5) NVIDIA in Docker
# Pulls a CUDA base image and runs nvidia-smi in container.
printf "\n==> Docker + GPU runtime check (this may pull an image)\n"
if docker run --rm --gpus all nvidia/cuda:13.0.0-base-ubuntu24.04 nvidia-smi; then
  ok "Docker container can access NVIDIA GPUs"
else
  err "Docker container could not access NVIDIA GPUs"
fi

if [[ "$failures" -eq 0 ]]; then
printf "\nAll checks passed ✅\n"
else
printf "\n%s check(s) failed ❌\n" "$failures"
  exit 1
fi
