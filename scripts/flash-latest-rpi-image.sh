#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Download the latest Raspberry Pi image artifact from GitHub Actions and flash it to an SD card.

Usage:
  ./scripts/flash-latest-rpi-image.sh <device> [options]

Arguments:
  <device>                     Target device (e.g. /dev/disk4, /dev/rdisk4, /dev/sdb)

Options:
  -r, --repo <owner/repo>      GitHub repo (default: inferred from git remote, fallback gabrielmbmb/nixos-configs)
  -w, --workflow <file>        Workflow file name (default: build-rpi-image.yml)
  -a, --artifact <name>        Artifact name (default: rpi-sd-image)
  -o, --output-dir <dir>       Directory to store downloaded image (default: ./downloads/rpi)
  -f, --force-download         Force re-download even if local image already exists
  -y, --yes                    Skip confirmation prompt
  -h, --help                   Show this help

Examples:
  ./scripts/flash-latest-rpi-image.sh /dev/rdisk4
  ./scripts/flash-latest-rpi-image.sh /dev/rdisk4 --force-download
  ./scripts/flash-latest-rpi-image.sh /dev/sdb --repo gabrielmbmb/nixos-configs --yes
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

find_downloaded_image() {
  local dir="$1"
  local candidate

  # Prefer uncompressed image first.
  candidate="$(find "$dir" -maxdepth 3 -type f -name '*.img' | head -n1 || true)"
  if [[ -n "$candidate" ]]; then
    echo "$candidate"
    return
  fi

  # Fallback to common compressed forms.
  for ext in gz xz zst; do
    candidate="$(find "$dir" -maxdepth 3 -type f -name "*.img.${ext}" | head -n1 || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  echo ""
}

DEVICE="${1:-}"
REPO="$(infer_repo)"
WORKFLOW="build-rpi-image.yml"
ARTIFACT="rpi-sd-image"
OUTPUT_DIR="./downloads/rpi"
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
FINAL_IMG="$OUTPUT_DIR/${ARTIFACT}.img"

echo "Repo:      $REPO"
echo "Workflow:  $WORKFLOW"
echo "Artifact:  $ARTIFACT"
echo "Device:    $DEVICE"
echo "Output dir:$OUTPUT_DIR"

if [[ -f "$FINAL_IMG" && "$FORCE_DOWNLOAD" != true ]]; then
  echo "Using cached image: $FINAL_IMG"
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

  IMG_PATH="$(find_downloaded_image "$TMP_DIR")"

  if [[ -z "$IMG_PATH" ]]; then
    echo "Could not find an image file in downloaded artifact." >&2
    find "$TMP_DIR" -maxdepth 4 -type f -print >&2
    exit 1
  fi

  case "$IMG_PATH" in
    *.img.gz|*.img.xz|*.img.zst)
      echo "Downloaded image is compressed: $IMG_PATH" >&2
      echo "Please decompress it first, then flash manually with dd." >&2
      exit 1
      ;;
  esac

  cp "$IMG_PATH" "$FINAL_IMG"
  echo "Image downloaded: $FINAL_IMG"
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

  echo "Flashing to $RAW_DEVICE..."
  sudo dd if="$FINAL_IMG" of="$RAW_DEVICE" bs=4m
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

  echo "Flashing to $DEVICE..."
  sudo dd if="$FINAL_IMG" of="$DEVICE" bs=4M status=progress conv=fsync
  sync
else
  echo "Unsupported OS: $OS" >&2
  exit 1
fi

echo "Done ✅ SD card flashed with $FINAL_IMG"
