{config, pkgs, ... }:

let
  sway-config-dir =  "${config.xdg.configHome}/sway";
  waybar-config-dir =  "${config.xdg.configHome}/waybar";
  sway-dotfiles-root = "${config.home.homeDirectory}/dotfiles/sway";
in {
  # N.B. This sway config is predicated on an install of Manjaro sway edition
  #      i.e. far from pure nix
  #TODO Add packages

  home.file."${sway-config-dir}".source = config.lib.file.mkOutOfStoreSymlink "${sway-dotfiles-root}/sway-config";

  home.file."${waybar-config-dir}/config.jsonc".source = config.lib.file.mkOutOfStoreSymlink "${sway-dotfiles-root}/waybar-config.jsonc";
}
