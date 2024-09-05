{ config, pkgs, ... }:

{

  # Bootloader configuration - may be host-specific (if we're dual booting or whatever)

  # NixOS default bootloader configuration... sufficient for non dual-boot cases
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Customised grub bootloader configuration (as systemd-boot can't chainload another efi partition)
  # boot.loader.systemd-boot.enable = false;
  # boot.loader.grub = {
  #   enable = true;
  #   useOSProber = true;
  #   efiSupport = true;
  #   copyKernels = true;
  #   default = "saved";
  #   device = "nodev"; # Necessary for EFI, otherwise grub installs MBR bits
  #   # For chainloading, either Boot/bootx64.efi or systemd/systemd-bootx64.efi works
  #   extraEntries = ''
  #         # Chainload another disk / efi partition
  #         menuentry "Arch Linux" {
  #           set root=(hd0,1)
  #           chainloader /EFI/Boot/bootx64.efi
  #         }
  #   '';
  # };
  # boot.loader.efi = {
  #   canTouchEfiVariables = true;
  #   efiSysMountPoint = "/boot";
  # };

  # Additional luks entry from nixos /etc/nixos/configuration.nix
  # Appearing immediately after Bootloader section
  # This is an example from current xps15 config
  # boot.initrd.luks.devices."luks-6b3ab332-729e-41c9-802c-f91904b0a150".device = "/dev/disk/by-uuid/6b3ab332-729e-41c9-802c-f91904b0a150";
}
