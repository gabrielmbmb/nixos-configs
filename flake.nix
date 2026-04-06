{
  description = "NixOS images (Raspberry Pi + ML workstation installer)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    dotfiles = {
      url = "github:gabrielmbmb/dotfiles";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, dotfiles, ... }:
    let
      # Shared defaults (edit to match your setup)
      username = "gabriel";
      sshPublicKey = "ssh-ed25519 AAAA_REPLACE_WITH_YOUR_PUBLIC_KEY";

      mkHost =
        {
          system,
          hostname,
          modules,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = {
            inherit hostname username sshPublicKey dotfiles;
          };
        };

      rpiConfig = mkHost {
        system = "aarch64-linux";
        hostname = "rpi";
        modules = [
          ./hosts/rpi/configuration.nix
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ];
      };

      mlInstallerConfig = mkHost {
        system = "x86_64-linux";
        hostname = "ml3090";
        modules = [
          ./hosts/ml/installer.nix
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ];
      };
    in
    {
      nixosConfigurations = {
        rpi = rpiConfig;
        ml3090Installer = mlInstallerConfig;
      };

      packages.aarch64-linux.sdImage = rpiConfig.config.system.build.sdImage;
      packages.x86_64-linux.mlInstallerIso = mlInstallerConfig.config.system.build.isoImage;
    };
}
