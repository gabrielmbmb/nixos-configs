{ lib, ... }:
let
  hasHardwareConfig = builtins.pathExists ./hardware-configuration.nix;
in
{
  imports =
    [ ./common.nix ]
    ++ lib.optional hasHardwareConfig ./hardware-configuration.nix;

  boot.loader = if hasHardwareConfig then {
    # Bootloader for the installed ML machine (UEFI).
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  } else {
    grub.enable = false;
  };

  # Keep evaluation readable when hardware config is missing.
  fileSystems = lib.mkIf (!hasHardwareConfig) {
    "/" = {
      device = "none";
      fsType = "tmpfs";
    };
  };

  assertions = [
    {
      assertion = hasHardwareConfig;
      message = ''
        Missing hosts/ml/hardware-configuration.nix.

        Copy it from the installed ML machine and commit it:
          sudo cp /etc/nixos/hardware-configuration.nix <repo>/hosts/ml/hardware-configuration.nix
      '';
    }
  ];
}
