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

  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/c377f942-7a0c-4381-be14-c3f054aa8cf8";
    fsType = "btrfs";
    options = [ # If you don't have this options attribute, it'll default to "defaults"
      # boot options for fstab. Search up fstab mount options you can use
      "users" # Allows any user to mount and unmount
      "nofail" # Prevent system from failing if this drive doesn't mount
    ];
  };
}
