{ lib, pkgs, hostname, username, sshPublicKey, ... }:
{
  networking.hostName = hostname;
  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

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
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [ sshPublicKey ];
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  environment.systemPackages = with pkgs; [
    tmux
    neovim
    docker-compose
    git
    curl
    htop
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Optional: keep image uncompressed to speed up local iteration.
  sdImage.compressImage = false;

  system.stateVersion = "25.11";
}
