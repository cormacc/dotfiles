# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, specialArgs, ... }:

{
  imports = [
    ./nixos-core.nix
  ];

  # Use latest kernel when not using zfs
  # boot.kernelPackages = pkgs.linuxPackages_latest;

  # ZFS config
  services.zfs.trim.enable = true;
  #TODO: belongs in host/<host>/nixos-configuration.nix
  networking.hostId = "684e91bc";
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs.autoScrub.enable = true;

  environment.systemPackages = with pkgs; [
    zfs
  ];

  virtualisation.docker.storageDriver = "zfs";
  #TODO: Move to <host>/nixos-configuration.nix
  boot.zfs.extraPools = ["data"];
}
