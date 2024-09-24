# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, specialArgs, ... }:

{
  # Work around issues with mkOutOfStoreSymlink and nix 2.18.x (Jun 2024)
  nix.package = pkgs.nixVersions.latest;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Bootloader.
  # Now customised per-host in hosts/<host>/nixos-configuration.nix
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  # nixpkgs kernel version usually trailing a bit...
  boot.kernelPackages = pkgs.linuxPackages_latest;


  networking.hostName = specialArgs.hostName; # Define your hostname.

  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.cormacc = {
    isNormalUser = true;
    description = "Cormac Cannon";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [];
  };

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

  services.fwupd.enable = true;

  # Mount the moosefs cluster
  services.moosefs.client.enable = true;
  fileSystems."/mnt/mfs" = {
    device = "mfsmaster:/";
    fsType = "moosefs";
    options = [ # If you don't have this options attribute, it'll default to "defaults"
      # boot options for fstab. Search up fstab mount options you can use
      "nofail" # Prevent system from failing if this drive doesn't mount
      "_netdev"
    ];
  };

  # Keyboard and mouse
  console.keyMap = "ie";
  services.libinput.enable = true;

  # enable docker
  virtualisation.docker = {
    enable = true;

    # use docker without Root access (Rootless docker)
    # ... though this interferes with running supabase locally
    # rootless = {
    #   enable = true;
    #   setSocketVariable = true;
    # };

    # Enable remote access for supabase cli with rootless docker...
    # .... although this doesn't work currently...
    # ... see https://github.com/supabase/cli/issues/2588
    # ... also https://docs.docker.com/engine/daemon/remote-access/
    # daemon.settings = {
    #   hosts = [
    #     "tcp://127.0.0.1:2375"
    #   ];
    # };
  };


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    btrfs-progs
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    git
    home-manager
    lshw
    docker-compose
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
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
    };
  };

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
