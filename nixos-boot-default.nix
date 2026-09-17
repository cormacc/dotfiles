{ config, pkgs, ... }:

{

  # Bootloader configuration - may be host-specific (if we're dual booting or whatever)

  # NixOS default bootloader configuration... sufficient for non dual-boot cases
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Default `null` = unlimited, which eventually fills the ESP and breaks switch mid-copy.
  # Counts generations, not kernels: pairs are deduped by store hash. On a 512M
  # ESP at ~60 MiB per pair the ceiling is 8 distinct kernels.
  boot.loader.systemd-boot.configurationLimit = 10;
}
