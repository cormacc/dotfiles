{config, pkgs, ... }:

let
  hypr-dotfiles-root = "${config.home.homeDirectory}/dotfiles/wayland/hypr";
in {

  # N.B. Install the following packages at OS level
  # - hyprland
  # - waybar (as nix-installed variant has privilege issues with hyprland IPC)
  # This module also expects wayland.nix to be imported for common config

  # home.packages = with pkgs; [
  # ];

  home.file."${config.xdg.configHome}/hypr".source = config.lib.file.mkOutOfStoreSymlink "${hypr-dotfiles-root}/config";
}
