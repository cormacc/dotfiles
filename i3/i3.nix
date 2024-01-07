{config, pkgs, ... }:

{
  # N.B. The following packages should be installed by the OS
  #      In a non-NixOS setup at least....
  # xorg, i3wm, i3lock-color
  home.packages = with pkgs; [
    xorg.xrandr
    scrot
    j4-dmenu-desktop
    picom
    ranger
    dunst
    #i3lock-color #unlock password fails if PAM owned by OS and i3lock owned by home-manager
    #i3-scrot #not in nixpgs
  ];

  programs.i3status = {
    enable = true;
  };

  # Do this to have a symlinked read-only version
  # home.file."${config.xdg.configHome}/i3/config".source=.config/i3/config;
  # ... or this to keep it editable in-place, rather than have to 'home-manager switch ...' after each edit
  # ... N.B. doing this requires this repo to be checked out locally to $HOME/dotfiles -- i.e. prevents this flake being used remotely from a git repo
  # ... TODO: Make this optional based on some flag passed in the call to home-manager switch?
  home.file."${config.xdg.configHome}/i3/config".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/i3/.config/i3/config";

  # TODO: This should be set per host instead...
  xresources.properties = {
    "Xft.dpi" = 240;
  };

  home.file.".local/bin/i3exit".source=./i3exit;
}
