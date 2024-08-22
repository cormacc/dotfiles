# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, specialArgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      # ./hardware-configuration.nix
    ];

  # Work around issues with mkOutOfStoreSymlink and nix 2.18.x (Jun 2024)
  nix.package = pkgs.nixVersions.latest;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # nixpkgs kernel version usually trailing a bit...
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Required to install sway via home-manager
  # ... but we're installing via nixos
  #security.polkit.enable = true;


  networking.hostName = specialArgs.hostName; # Define your hostname.

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Dublin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_IE.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IE.UTF-8";
    LC_IDENTIFICATION = "en_IE.UTF-8";
    LC_MEASUREMENT = "en_IE.UTF-8";
    LC_MONETARY = "en_IE.UTF-8";
    LC_NAME = "en_IE.UTF-8";
    LC_NUMERIC = "en_IE.UTF-8";
    LC_PAPER = "en_IE.UTF-8";
    LC_TELEPHONE = "en_IE.UTF-8";
    LC_TIME = "en_IE.UTF-8";
  };

  # Display manager etc.
  services.fwupd.enable = true;
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # Keyboard and mouse
  services.xserver.xkb = {
    layout = "ie";
    variant = "";
  };
  console.keyMap = "ie";
  services.libinput.enable = true;

  services.printing.enable = true;

  # Audio
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };


  # Desktop environments
  services.xserver.desktopManager.gnome.enable = true;

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

  # enable docker
  virtualisation.docker.enable = true;

  # use docker without Root access (Rootless docker)
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.cormacc = {
    isNormalUser = true;
    description = "Cormac Cannon";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    git
    home-manager
    lshw
    chromium
    waybar
    kitty
    # Install system python at OS level...
    # ... this keeps home-manager config compatible with Arch linux package management
    python3
    pipenv
    poetry
  ];

  environment.variables.EDITOR = "vim";

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
