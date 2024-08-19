{ config, pkgs, ... }:

{
  # Additional luks entry from nixos /etc/nixos/configuration.nix
  # Appearing immediately after Bootloader section
  boot.initrd.luks.devices."luks-6b3ab332-729e-41c9-802c-f91904b0a150".device = "/dev/disk/by-uuid/6b3ab332-729e-41c9-802c-f91904b0a150";
}
