{ config, pkgs, ... }:

{
  # Bootloader configuration - host-specific (if we're dual booting or whatever)

  # NixOS default bootloader configuration...
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Bypassing for now due to issues with external drive enclosure
  # fileSystems = {
  #   "/mnt/downloads" = {
  #     # device = "/dev/sdd";
  #     device = "/dev/disk/by-id/ata-WDC_WD40EZRX-00SPEB0_WD-WCC4ENEJ9DVN";
  #     fsType = "ext4";
  #   };
  # };
}
