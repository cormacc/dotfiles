{ config, pkgs, ... }:

{
  # Bootloader configuration - host-specific (if we're dual booting or whatever)

  # NixOS default bootloader configuration...
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
