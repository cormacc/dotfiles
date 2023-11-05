{config, pkgs, ... }:

{
  home.packages = with pkgs; [
    j4-dmenu-desktop
    picom
    #ranger #managed by arch as dependency of bmenu...
    dunst
    #i3-scrot #not in nixpgs
  ];
  home.file.".config/i3/config".source=.config/i3/config;
}
