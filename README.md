# NixOS images (Raspberry Pi + ML workstation)

This flake builds:

1. **Raspberry Pi SD image** (`aarch64`)
2. **x86_64 installer ISO** for an ML workstation with NVIDIA + CUDA 13.0

## Included setup

- SSH server + your authorized public key
- `tmux`, `neovim`, `uv`, `llama-cpp`
- Docker + docker compose
- For ML ISO: headless NVIDIA driver + CUDA **13.0** + NVIDIA container toolkit (no UI)

## 1) Set your values

Edit `flake.nix`:

- `username`
- hostnames (`rpi`, `ml3090`) if you want

### Auto-fill `sshPublicKey` from your local key

```bash
./scripts/update-ssh-key.sh
```

Optional args:

```bash
./scripts/update-ssh-key.sh <path-to-public-key> <path-to-flake.nix>
```

### Raspberry Pi dotfiles sync

The RPi host is configured to pull from `github:gabrielmbmb/dotfiles` and link:

- `~/.zshrc` → `.zshrc`
- `~/.config/nvim` → `.config/nvim`

(These are pinned via `flake.lock`.)

## 2) Build Raspberry Pi image

On an `aarch64-linux` builder:

```bash
nix build .#packages.aarch64-linux.sdImage
```

Result:

- `./result/sd-image/*.img`

### Or download + flash latest CI image automatically

```bash
./scripts/flash-latest-rpi-image.sh /dev/rdisk4
```

The script downloads the latest successful GitHub Actions artifact (`rpi-sd-image`) and writes it to the SD card.

## 3) Build ML workstation installer ISO (x86_64)

On an `x86_64-linux` builder:

```bash
nix build .#packages.x86_64-linux.mlInstallerIso
```

Result:

- `./result/iso/*.iso`

## 4) ML post-install checks

On the installed ML machine, run:

```bash
./scripts/ml-post-install-check.sh
```

This validates:

- `nvidia-smi` and GPU visibility
- CUDA toolkit version (`nvcc`, expects 13.0)
- `llama-cpp` CLI availability (`llama`)
- Docker daemon access
- GPU access from Docker (`docker run --gpus all ... nvidia-smi`)

## 5) GitHub Actions build artifact (Raspberry Pi)

Workflow:

- `.github/workflows/build-rpi-image.yml`

Run manually via **Actions → Build Raspberry Pi NixOS image → Run workflow**.
