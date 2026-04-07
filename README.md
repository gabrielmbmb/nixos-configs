# NixOS images + host configs (Raspberry Pi + ML workstation)

This flake provides:

1. **Raspberry Pi SD image** (`aarch64`)
2. **x86_64 installer ISO** for an ML workstation with NVIDIA + CUDA 13.0
3. **x86_64 installed system config** (`nixosConfigurations.ml3090`)

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

### Or download + write latest CI ISO automatically

```bash
./scripts/flash-latest-ml-iso.sh /dev/rdisk4
```

The script downloads the latest successful GitHub Actions artifact (`ml-installer-iso`) and writes it to your USB drive.

## 4) Apply ML config after installation

Booting from the installer ISO does **not** automatically apply the final host config.

After installing NixOS on the ML machine:

1. Copy generated hardware config into this repo:

```bash
sudo cp /etc/nixos/hardware-configuration.nix hosts/ml/hardware-configuration.nix
```

2. Commit/push `hosts/ml/hardware-configuration.nix`.

3. On the ML machine, apply the flake host config:

```bash
sudo nixos-rebuild switch --flake .#ml3090
```

## 5) ML post-install checks

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

## 6) GitHub Actions build artifacts

Workflows:

- `.github/workflows/build-rpi-image.yml`
- `.github/workflows/build-ml-iso.yml`

Run manually via **Actions** tab.
