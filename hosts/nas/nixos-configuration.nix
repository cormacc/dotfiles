{ config, pkgs, ... }:

{

  # Bootloader configuration - may be host-specific (if we're dual booting or whatever)

  # NixOS default bootloader configuration... sufficient for non dual-boot cases
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  fileSystems = {
    "/mnt/data" = {
      device = "/dev/disk/by-uuid/c377f942-7a0c-4381-be14-c3f054aa8cf8";
      fsType = "btrfs";
    };
    "mnt/downloads" = {
      device = "/dev/disk/by-uuid/f92f15c2-6666-4ac1-ba76-0bdadbf8652d";
      fsType = "ext4";
    };
  };
}
