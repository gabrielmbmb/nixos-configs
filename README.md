# Raspberry Pi NixOS flake

This flake builds an `aarch64` NixOS SD image with:

- Hostname
- Your SSH public key
- `tmux`, `neovim`
- Docker + docker compose

## 1) Set your values

Edit `flake.nix`:

- `hostname`
- `username`

### Auto-fill `sshPublicKey` from your local key

Use the helper script:

```bash
./scripts/update-ssh-key.sh
```

Optional args:

```bash
./scripts/update-ssh-key.sh <path-to-public-key> <path-to-flake.nix>
```

## 2) Build the image

On an `aarch64-linux` builder:

```bash
nix build .#packages.aarch64-linux.sdImage
```

Result:

- `./result/sd-image/*.img`

## 3) Flash to SD card

Example (Linux):

```bash
sudo dd if=./result/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with your SD card device.

## 4) Boot and connect

After boot, SSH with your configured user:

```bash
ssh <username>@<hostname>.local
```

(Or use the device IP from your router.)

## GitHub Actions build artifact

A workflow is included at:

- `.github/workflows/build-rpi-image.yml`

It can be run manually (**Actions → Build Raspberry Pi NixOS image → Run workflow**) and will upload the SD image as a downloadable artifact.
