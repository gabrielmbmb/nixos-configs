{
  description = "NixOS Raspberry Pi image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      hostname = "kitty";
      username = "gabriel";
      sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINjwlAP3H2QIyCtXySAUalJ8y5QwyQauE3s09XlVRwKm gabrielmbmb@Gabriels-MacBook-Pro-2.local-20260406";
    in
    {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit hostname username sshPublicKey;
        };
        modules = [
          ./hosts/rpi/configuration.nix
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ];
      };

      packages.${system}.sdImage =
        self.nixosConfigurations.${hostname}.config.system.build.sdImage;
    };
}
