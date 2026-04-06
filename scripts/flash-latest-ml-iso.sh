#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Download the latest ML installer ISO artifact from GitHub Actions and write it to a USB drive.

Usage:
  ./scripts/flash-latest-ml-iso.sh <device> [options]

Arguments:
  <device>                     Target device (e.g. /dev/disk4, /dev/rdisk4, /dev/sdb)

Options:
  -r, --repo <owner/repo>      GitHub repo (default: inferred from git remote, fallback gabrielmbmb/nixos-configs)
  -w, --workflow <file>        Workflow file name (default: build-ml-iso.yml)
  -a, --artifact <name>        Artifact name (default: ml-installer-iso)
  -o, --output-dir <dir>       Directory to store downloaded ISO (default: ./downloads/ml)
  -f, --force-download         Force re-download even if local ISO already exists
  -y, --yes                    Skip confirmation prompt
  -h, --help                   Show this help

Examples:
  ./scripts/flash-latest-ml-iso.sh /dev/rdisk4
  ./scripts/flash-latest-ml-iso.sh /dev/sdb --yes
  ./scripts/flash-latest-ml-iso.sh /dev/disk4 --force-download
EOF
}

infer_repo() {
  local remote_url
  remote_url="$(git config --get remote.origin.url 2>/dev/null || true)"

  if [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return
  fi

  if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return
  fi

  echo "gabrielmbmb/nixos-configs"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

find_downloaded_iso() {
  local dir="$1"
  local candidate

  candidate="$(find "$dir" -maxdepth 3 -type f -name '*.iso' | head -n1 || true)"
  if [[ -n "$candidate" ]]; then
    echo "$candidate"
    return
  fi

  for ext in gz xz zst; do
    candidate="$(find "$dir" -maxdepth 3 -type f -name "*.iso.${ext}" | head -n1 || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  echo ""
}

DEVICE="${1:-}"
REPO="$(infer_repo)"
WORKFLOW="build-ml-iso.yml"
ARTIFACT="ml-installer-iso"
OUTPUT_DIR="./downloads/ml"
FORCE_DOWNLOAD=false
ASSUME_YES=false

if [[ "$DEVICE" == "-h" || "$DEVICE" == "--help" || -z "$DEVICE" ]]; then
  usage
  exit 0
fi
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--repo)
      REPO="$2"; shift 2 ;;
    -w|--workflow)
      WORKFLOW="$2"; shift 2 ;;
    -a|--artifact)
      ARTIFACT="$2"; shift 2 ;;
    -o|--output-dir)
      OUTPUT_DIR="$2"; shift 2 ;;
    -f|--force-download)
      FORCE_DOWNLOAD=true; shift ;;
    -y|--yes)
      ASSUME_YES=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

require_cmd dd
require_cmd find

if [[ ! -e "$DEVICE" ]]; then
  echo "Device does not exist: $DEVICE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
FINAL_ISO="$OUTPUT_DIR/${ARTIFACT}.iso"

echo "Repo:      $REPO"
echo "Workflow:  $WORKFLOW"
echo "Artifact:  $ARTIFACT"
echo "Device:    $DEVICE"
echo "Output dir:$OUTPUT_DIR"

if [[ -f "$FINAL_ISO" && "$FORCE_DOWNLOAD" != true ]]; then
  echo "Using cached ISO: $FINAL_ISO"
  echo "(pass --force-download to fetch latest artifact)"
else
  require_cmd gh

  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated. Run: gh auth login" >&2
    exit 1
  fi

  RUN_ID="$(gh run list \
    -R "$REPO" \
    --workflow "$WORKFLOW" \
    --status success \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId')"

  if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
    echo "No successful workflow run found for $WORKFLOW in $REPO" >&2
    exit 1
  fi

  echo "Latest successful run id: $RUN_ID"

  TMP_DIR="$(mktemp -d)"
  cleanup() {
    rm -rf "$TMP_DIR"
  }
  trap cleanup EXIT

  echo "Downloading artifact..."
  gh run download "$RUN_ID" -R "$REPO" -n "$ARTIFACT" -D "$TMP_DIR"

  ISO_PATH="$(find_downloaded_iso "$TMP_DIR")"

  if [[ -z "$ISO_PATH" ]]; then
    echo "Could not find an ISO file in downloaded artifact." >&2
    find "$TMP_DIR" -maxdepth 4 -type f -print >&2
    exit 1
  fi

  case "$ISO_PATH" in
    *.iso.gz|*.iso.xz|*.iso.zst)
      echo "Downloaded ISO is compressed: $ISO_PATH" >&2
      echo "Please decompress it first, then flash manually with dd." >&2
      exit 1
      ;;
  esac

  cp "$ISO_PATH" "$FINAL_ISO"
  echo "ISO downloaded: $FINAL_ISO"
fi

if [[ "$ASSUME_YES" != true ]]; then
  echo
  read -r -p "This will ERASE all data on $DEVICE. Type YES to continue: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

sudo -v

OS="$(uname -s)"
if [[ "$OS" == "Darwin" ]]; then
  require_cmd diskutil

  if [[ "$DEVICE" =~ ^/dev/rdisk[0-9]+$ ]]; then
    RAW_DEVICE="$DEVICE"
    BLOCK_DEVICE="/dev/${DEVICE#/dev/r}"
  elif [[ "$DEVICE" =~ ^/dev/disk[0-9]+$ ]]; then
    BLOCK_DEVICE="$DEVICE"
    RAW_DEVICE="/dev/r${DEVICE#/dev/}"
  else
    echo "On macOS, device must look like /dev/diskN or /dev/rdiskN" >&2
    exit 1
  fi

  echo "Unmounting $BLOCK_DEVICE..."
  sudo diskutil unmountDisk "$BLOCK_DEVICE"

  echo "Writing ISO to $RAW_DEVICE..."
  sudo dd if="$FINAL_ISO" of="$RAW_DEVICE" bs=4m
  sync

  echo "Ejecting $BLOCK_DEVICE..."
  diskutil eject "$BLOCK_DEVICE" || true

elif [[ "$OS" == "Linux" ]]; then
  if [[ ! -b "$DEVICE" ]]; then
    echo "On Linux, target must be a block device (got: $DEVICE)" >&2
    exit 1
  fi

  echo "Unmounting partitions on $DEVICE..."
  sudo umount "${DEVICE}"* 2>/dev/null || true

  echo "Writing ISO to $DEVICE..."
  sudo dd if="$FINAL_ISO" of="$DEVICE" bs=4M status=progress conv=fsync
  sync
else
  echo "Unsupported OS: $OS" >&2
  exit 1
fi

echo "Done ✅ USB written with $FINAL_ISO"
