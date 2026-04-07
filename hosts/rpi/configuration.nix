{ lib, pkgs, hostname, username, sshPublicKey, dotfiles, ... }:
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
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ sshPublicKey ];
  };

  programs.zsh.enable = true;
  programs.starship.enable = true;

  security.sudo.wheelNeedsPassword = false;

  systemd.tmpfiles.rules = [
    "d /home/${username}/.config 0755 ${username} users -"
    "L+ /home/${username}/.zshrc - - - - ${dotfiles}/.zshrc"
    "L+ /home/${username}/.config/nvim - - - - ${dotfiles}/.config/nvim"
  ];

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  environment.systemPackages = with pkgs; [
    tmux
    neovim
    zsh
    ghostty.terminfo
    ripgrep
    fd
    fzf
    starship
    uv
    pnpm
    nodejs
    rustc
    cargo
    zig
    go
    bun
    docker-compose
    git
    gh
    curl
    htop
    wakeonlan
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Optional: keep image uncompressed to speed up local iteration.
  sdImage.compressImage = false;

  system.stateVersion = "25.11";
}
