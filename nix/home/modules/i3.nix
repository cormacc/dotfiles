{ lib, config, pkgs, ... }:
with lib;
let
  dotRoot = config.my.i3.dotRoot;
in {
  options.my.i3 = {
    dotRoot = mkOption {
      type = types.path;
      default = "";
    };
  };
  config = {
    home.packages = with pkgs; [
      j4-dmenu-desktop
      picom
      #ranger #managed by arch as dependency of bmenu...
      dunst
      #i3-scrot #not in nixpgs
    ];
    home.file.".config/i3/config".source="${dotRoot}/i3/.config/i3/config";
  };
}
