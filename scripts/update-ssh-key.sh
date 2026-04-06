#!/usr/bin/env bash
set -euo pipefail

KEY_FILE="${1:-$HOME/.ssh/id_ed25519.pub}"
FLAKE_FILE="${2:-flake.nix}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Key file not found: $KEY_FILE" >&2
  exit 1
fi

python3 - "$FLAKE_FILE" "$KEY_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

flake_file = Path(sys.argv[1])
key_file = Path(sys.argv[2])

key = key_file.read_text().strip()
text = flake_file.read_text()
new_text, n = re.subn(
    r'sshPublicKey\s*=\s*".*?";',
    f'sshPublicKey = {json.dumps(key)};',
    text,
    count=1,
)

if n != 1:
    raise SystemExit(f"Could not find a unique sshPublicKey assignment in {flake_file}")

flake_file.write_text(new_text)
print(f"Updated {flake_file} with key from {key_file}")
PY
