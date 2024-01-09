{config, pkgs, ... }:

let
  i3blocks-config-dir = "${config.xdg.configHome}/i3blocks";
  i3blocks-contrib-dir = "${i3blocks-config-dir}/contrib";
in {
  # N.B. The following packages should be installed by the OS
  #      In a non-NixOS setup at least....
  # xorg, i3wm, i3lock-color
  home.packages = with pkgs; [
    xorg.xrandr
    dunst
    # Desktop background / compositor
    nitrogen
    picom
    # i3blocks
    # Tray control icons
    networkmanagerapplet
    #... these still valid when using pipewire
    pasystray
    paprefs
    pavucontrol
    # Utilities
    conky
    # blueman # Needs to be installed at OS level
    scrot
    j4-dmenu-desktop
    ranger
    xautolock
    #i3lock-color #unlock password fails if PAM owned by OS and i3lock owned by home-manager
  ];

  # This option added Jan 2024 -- not available outside of git as yet
  # programs.i3blocks = {
  #   enable = true;
  # };
  programs.i3status = {
    enable = true;
  };

  # Do this to have a symlinked read-only version
  # home.file."${config.xdg.configHome}/i3/config".source=.config/i3/config;
  # ... or this to keep it editable in-place, rather than have to 'home-manager switch ...' after each edit
  # ... N.B. doing this requires this repo to be checked out locally to $HOME/dotfiles -- i.e. prevents this flake being used remotely from a git repo
  # ... TODO: Make this optional based on some flag passed in the call to home-manager switch?
  home.file."${config.xdg.configHome}/i3/config".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/i3/i3config";


  # i3blocks
  # home.file."${i3blocks-config-dir}/config".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/i3/i3blocksconfig";

  # TODO: This should be set per host instead...
  xresources.properties = {
    "Xft.dpi" = 240;
  };

  home.file.".local/bin/i3exit".source=./i3exit;
}
