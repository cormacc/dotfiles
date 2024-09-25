# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, specialArgs, ... }:

{
  imports = [
    ./nixos-core.nix
  ];

  # Use latest zfs-compatible kernel for servers
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  environment.systemPackages = with pkgs; [
    zfs
  ];
}
