# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, specialArgs, ... }:

{
  imports = [
    ./nixos-core.nix
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # Install system python at OS level...
    # ... this keeps home-manager config compatible with Arch linux package management
    # python3
    # pipenv
    # poetry
  ];
}
