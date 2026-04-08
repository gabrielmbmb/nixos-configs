{ lib, pkgs, hostname, username, sshPublicKey, dotfiles, ... }:
let
  wakeUntilSsh = pkgs.writeShellScriptBin "wake-until-ssh"
    (builtins.readFile ../../scripts/wake-until-ssh.sh);
in
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
  programs.nix-ld.enable = true;
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
    python3
    python3Packages.pip
    wakeonlan
    openssh
    wakeUntilSsh
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Optional: keep image uncompressed to speed up local iteration.
  sdImage.compressImage = false;

  system.stateVersion = "25.11";
}
