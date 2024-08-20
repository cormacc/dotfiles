{config, pkgs, ... }:

let
  sway-dotfiles-root = "${config.home.homeDirectory}/dotfiles/wayland/sway";
in {

  # N.B. Install the following packages at OS level
  # - sway
  # - waybar (as nix-installed variant has privilege issues with hyprland)
  # This module also expects wayland.nix to be imported for common config

  # The following packages have home-manager modules, but convenient to
  # install directly and link their config files using mkOutOfStoreSymlink
  # - waybar
  # - foot
  home.packages = with pkgs; [
    # ... screenshots
    sway-contrib.grimshot
    # Install this at system level -- PAM issues authenticating otherwise
    # swaylock
  ];

  # programs.swayr = {
  #   enable=true;
  #   systemd.enable = true;
  # };

  home.file."${config.xdg.configHome}/sway".source = config.lib.file.mkOutOfStoreSymlink "${sway-dotfiles-root}/config";
}
