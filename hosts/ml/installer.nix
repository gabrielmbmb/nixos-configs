{ config, lib, pkgs, hostname, username, sshPublicKey, ... }:
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
    openssh.authorizedKeys.keys = [ sshPublicKey ];
  };

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
    uv
    ripgrep
    fd
    fzf
    starship
    pnpm
    nodejs
    rustc
    cargo
    zig
    go
    bun
    docker-compose
    git
    curl
    htop
    pciutils
    cudaPkgs.cudatoolkit
    llama-cpp
  ];

  environment.variables = {
    CUDA_HOME = "${cudaPkgs.cudatoolkit}";
    CUDA_PATH = "${cudaPkgs.cudatoolkit}";
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
