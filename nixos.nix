# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, specialArgs, ... }:

{
  imports = [
    ./nixos-core.nix
  ];

  # Use latest kernel for workstations
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Keyboard and mouse
  services.xserver.xkb = {
    layout = "ie";
    variant = "";
  };

  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  services.blueman.enable = true;
  services.printing.enable = true;

  # Laptop bits
  services.thermald.enable = true;
  # This conflicts with services.power-profiles.daemon.enable... which appears to be true by default
  # services.tlp.enable = true;

  # Display manager etc.
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.gnome.gnome-keyring.enable = true;


  # Desktop environments
  services.xserver.desktopManager.gnome.enable = true;


  # Required to install sway via home-manager
  # ... but we're installing via nixos
  #security.polkit.enable = true;

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraOptions = [
      "--unsupported-gpu"
    ];
    extraSessionCommands = ''
    export _JAVA_AWT_WM_NONREPARENTING=1
    '';
  };

  programs.hyprland.enable = true;
  programs.hyprlock.enable = true;


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    waybar
    # Install GPU accelerated terminals at os level
    kitty
    ghostty
    # ... we use foot by default on wayland, but that's not GPU-accelerated so can be owned by home-manager
    # Install system python at OS level...
    # ... this keeps home-manager config compatible with Arch linux package management
    python3
    pipenv
    poetry
  ];
}
