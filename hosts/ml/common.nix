{ config, lib, pkgs, hostname, username, sshPublicKey, dotfiles, ... }:
let
  cudaPkgs = pkgs.cudaPackages_13_0;
  gpuPowerLimitWatts = 300;
  nvidiaSmi = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi";
in
{
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # NVIDIA/CUDA are unfree; enable CUDA-dependent package builds.
  nixpkgs.config = {
    allowUnfree = true;
    cudaSupport = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ sshPublicKey ];
  };

  programs.zsh.enable = true;
  programs.nix-ld.enable = true;
  programs.starship.enable = true;

  security.sudo.wheelNeedsPassword = false;

  systemd.tmpfiles.rules = [
    "d /home/${username}/.config 0755 ${username} users -"
    "L+ /home/${username}/.zshrc - - - - ${dotfiles}/.zshrc"
    "L+ /home/${username}/.config/nvim - - - - ${dotfiles}/.config/nvim"
  ];

  # Docker + Compose
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  # Headless GPU stack for RTX 3090s (no desktop/UI)
  services.xserver.enable = false;

  # This enables the NVIDIA kernel driver without enabling a graphical desktop.
  services.xserver.videoDrivers = [ "nvidia" ];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.graphics.enable = true;

  hardware.nvidia = {
    open = false;
    modesetting.enable = lib.mkForce false;
    nvidiaSettings = false;
    nvidiaPersistenced = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Enables NVIDIA runtime/CDI support for containers.
  hardware.nvidia-container-toolkit.enable = true;

  systemd.services.pi-coding-agent-install = {
    description = "Install pi-coding-agent globally for ${username}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = username;
    };

    script = ''
      set -eu
      export HOME="/home/${username}"
      export PNPM_HOME="$HOME/.local/share/pnpm"
      export PATH="$PNPM_HOME:${pkgs.pnpm}/bin:${pkgs.nodejs}/bin:/run/current-system/sw/bin"

      mkdir -p "$PNPM_HOME"
      if [ -x "$PNPM_HOME/pi" ]; then
        exit 0
      fi

      ${pkgs.pnpm}/bin/pnpm install -g @mariozechner/pi-coding-agent
    '';
  };

  # Cap all NVIDIA GPUs (e.g. dual RTX 3090) to a fixed power limit on boot.
  systemd.services.nvidia-power-limit = {
    description = "Set NVIDIA GPU power limit";
    wantedBy = [ "multi-user.target" ];
    after = [ "nvidia-persistenced.service" ];
    wants = [ "nvidia-persistenced.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      # If GPUs are not available yet, do not fail the whole boot.
      if ! ${nvidiaSmi} -L >/dev/null 2>&1; then
        echo "nvidia-power-limit: nvidia-smi not ready, skipping"
        exit 0
      fi

      for gpu in $(${nvidiaSmi} --query-gpu=index --format=csv,noheader,nounits); do
        echo "Setting GPU $gpu power limit to ${toString gpuPowerLimitWatts}W"
        ${nvidiaSmi} -i "$gpu" -pl ${toString gpuPowerLimitWatts}
      done
    '';
  };

  environment.systemPackages = with pkgs; [
    tmux
    neovim
    zsh
    ghostty.terminfo
    uv
    ripgrep
    fd
    fzf
    starship
    pnpm
    nodejs
    rustc
    cargo
    cmake
    zig
    go
    bun
    docker-compose
    git
    gh
    curl
    wget
    unzip
    htop
    ruby
    colorls
    cacert
    python3
    python3Packages.pip
    pciutils
    cudaPkgs.cudatoolkit
    llama-cpp
  ];

  environment.variables = {
    CUDA_HOME = "${cudaPkgs.cudatoolkit}";
    CUDA_PATH = "${cudaPkgs.cudatoolkit}";
    # Ensure libcuda.so.1 is discoverable by tools that rely on LD_LIBRARY_PATH.
    LD_LIBRARY_PATH = lib.concatStringsSep ":" [
      "/run/opengl-driver/lib"
      "${config.hardware.nvidia.package}/lib"
    ];
    # CA bundle for TLS/SSL in tooling (curl/git/python/node/non-Nix binaries).
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  system.stateVersion = "25.11";
}
