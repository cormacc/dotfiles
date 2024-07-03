# TODO: Retained as an example of a more detailed syncthing config -- may revisit/adapt in the context of home-manager

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./t470p-hardware-configuration.nix
      # Binary cache - cachix generates config at this path by default
      /etc/nixos/cachix.nix
    ];

  nixpkgs.overlays = [
    (import (builtins.fetchTarball {
      url = https://github.com/nix-community/emacs-overlay/archive/master.tar.gz;
    }))
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # Setup keyfile
  boot.initrd.secrets = {
    "/crypto_keyfile.bin" = null;
  };

  # Enable swap on luks
  boot.initrd.luks.devices."luks-613d6de8-70e7-4806-9a4b-949a0f78c263".device = "/dev/disk/by-uuid/613d6de8-70e7-4806-9a4b-949a0f78c263";
  boot.initrd.luks.devices."luks-613d6de8-70e7-4806-9a4b-949a0f78c263".keyFile = "/crypto_keyfile.bin";

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Dublin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";

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

  # services.xserver.enable = true;


  #i3-related -- see NixOS wiki
  environment.pathsToLink = [ "/libexec" ]; # links /libexec from derivations to /run/current-system/sw

  fonts.fonts = with pkgs; [
    source-code-pro
    jetbrains-mono
  ];

  #High DPI support
  services.xserver.dpi = 180;
  environment.variables = {
    GDK_SCALE = "2";
    GDK_DPI_SCALE = "0.5";
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=2";
  };

  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;

    # Configure keymap in X11
    layout = "gb";
    xkbVariant = "";
    xkbOptions = "caps:swapescape";

    # Synaptics touchpad needs this
    libinput.enable = true;

    # Enable the GNOME Desktop Environment.
    #desktopManager.gnome.enable = true;
    #displayManager.gdm.enable = true;

    desktopManager = {
      xterm.enable = false;
    };

    displayManager = {
      defaultSession = "none+i3";
    };

    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu #application launcher most people use
        j4-dmenu-desktop #wrapper for dmenu that populates application lists
        i3status # gives you the default i3 status bar
        i3lock #default i3 screen locker
        i3blocks #if you are planning on using i3blocks over i3status
        alacritty
      ];
    };
  };

  # Configure console keymap
  console.keyMap = "uk";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  users.defaultUserShell = pkgs.zsh;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.cormacc = {
    isNormalUser = true;
    description = "Cormac Cannon";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      firefox
    #  thunderbird
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    cachix
    home-manager
    #Migrate all the below to home-manager flake(s)
    # desktop
    chromium
    # TODO libreoffice
    # TODO krita etc.
    # editing
    vim
    # .. emacs
    # emacs
    emacs-unstable
    aspell
    aspellDicts.en
    pandoc
    plantuml-c4
    # dev tools
    git
    # Languages
    # .. core
    python311
    ruby
    jdk
    # .. c/cpp
    clang
    gcc
    # .. clojure
    clojure
    leiningen
    babashka
  ];

  programs.zsh.enable = true;
  programs.nm-applet.enable = true;


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
  system.stateVersion = "22.11"; # Did you read the comment?

  nix.settings.experimental-features = ["nix-command" "flakes"];

  #See https://wes.today/nixos-syncthing/
  #Also https://docs.syncthing.net/users/versioning.html
  services.syncthing = {
    enable = true;
    dataDir = "/home/cormacc/sync";
    configDir = "/home/cormacc/.config/syncthing";
    user = "cormacc";
    group = "users";
    overrideDevices = true;     # overrides any devices added or deleted through the WebUI
    overrideFolders = true;     # overrides any folders added or deleted through the WebUI
    devices = {
      "t470p" = { id = "K4O7HR3-L6JNRER-JFMYW2B-IMAN6C4-BOZIBOE-AINVML7-QIOIDWC-D5VORQB"; };
      "mbp" = { id = "PSMHR32-7DEKOG2-I7R5BD7-PDJCM73-UGF6LDW-DA6CISQ-5KDYCIO-KHUBYAF"; };
    };
    folders = {
      "cormacc-dev" = {        # Name of folder in Syncthing, also the folder ID
        path = "/home/cormacc/dev";    # Which folder to add to Syncthing
        devices = [ "t470p" "mbp" ];      # Which devices to share the folder with
        versioning = {
          type = "staggered";
          params = {
            cleanInterval = "3600";
            maxAge = "15768000";
          };
        };
      };
      "cormacc-sync" = {
        path = "/home/cormacc/sync";
        devices = [ "t470p" "mbp" ];
        versioning = {
          type = "simple";
          params = {
            keep = "10";
          };
        };
        #ignorePerms = false;     # By default, Syncthing doesn't sync file permissions. This line enables it for this folder.
      };
    };
  };
}
