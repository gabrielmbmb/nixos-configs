{ config, lib, pkgs, hostname, username, sshPublicKey, ... }:
let
  cudaPkgs = pkgs.cudaPackages_13_0;
in
{
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # NVIDIA drivers + CUDA are unfree.
  nixpkgs.config.allowUnfree = true;

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

  environment.systemPackages = with pkgs; [
    tmux
    neovim
    uv
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

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
