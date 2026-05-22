# Minimal /etc/nixos/configuration.nix for the live-ISO -> first switch
# step. The dotfiles flake isn't on the machine yet, so this file has to
# be self-contained -- it cannot import nixos-base.nix.
#
# Workflow:
#   1. Boot the official NixOS ISO and partition / mount in the usual way.
#   2. Run `nixos-generate-config --root /mnt` to produce
#      /mnt/etc/nixos/hardware-configuration.nix.
#   3. Drop this file over /mnt/etc/nixos/configuration.nix (or merge it
#      with the generated one).
#   4. `nixos-install`, set a root password, reboot.
#   5. Log in, clone the dotfiles repo, set the identity env vars
#      (see README), and run ./bootstrap.sh for the chosen host. That
#      script copies /etc/nixos/hardware-configuration.nix into
#      hosts/<host>/ and runs `nixos-rebuild switch --flake .#<host>`,
#      after which nixos-base.nix takes over the rest of the system
#      (locale, user, packages, services).
#
# Keep this file lean: only the bits needed to get networking + ssh +
# git up so the flake can be fetched and applied. Anything else belongs
# in nixos-base.nix.

{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Required to apply the dotfiles flake on the next step.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Bootloader -- nixos-base.nix delegates this to per-host modules, so
  # we still need defaults here.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # Just enough of a user to log in and clone the repo; nixos-base.nix
  # will then declare the full account.
  users.users.cormacc = {
    isNormalUser = true;
    description = "Cormac Cannon";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Smallest possible package set -- git to clone, curl/wget for any
  # ad-hoc fetches, vim because nano is fine but vim is muscle memory.
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    vim
  ];

  # Headless first boot via SSH is the common path; the full hardened
  # config lands once the flake is applied.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  system.stateVersion = "24.05";
}
