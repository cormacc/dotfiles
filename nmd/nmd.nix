{ config, pkgs, ... }:

{
  # ... MBT IOD bootloader configuration
  home.file.".mutebutton".source=./.mutebutton;

  # Dropbox account
  # N.B. This is broken as of 2024-1-11 -- pending merging of this fix in nixpkgs
  # https://github.com/NixOS/nixpkgs/pull/277422
  # services.dropbox = {
  #   enable = true;
  #   path = "${config.home.homeDirectory}/dropbox";
  # };

  # OneDrive etc.
  # See https://github.com/abraunegg/onedrive
  home.packages = with pkgs; [
    onedrive
  ];
  home.file."${config.xdg.configHome}/onedrive/config".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nmd/onedrive-config";
  #Manually link to systemd service, as home-manager not doing it for us here
  home.file."${config.xdg.configHome}/systemd/user/onedrive.service".source = "${pkgs.onedrive}/lib/systemd/user/onedrive.service";

  # Zephyr development config
  home.sessionVariables = {
    ZEPHYR_BASE="${config.home.homeDirectory}/dev/ncs/zephyr";
  };
}
