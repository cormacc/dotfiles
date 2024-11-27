{ config, pkgs, ... }:

{
  # ... MBT IOD bootloader configuration
  home.file.".mutebutton".source=./.mutebutton;

  # Dropbox account
  # N.B. This doesn't seem to install the tray widget
  # services.dropbox = {
  #   enable = true;
  #   path = "${config.home.homeDirectory}/dropbox";
  # };

  # OneDrive etc.
  # See https://github.com/abraunegg/onedrive
  home.packages = with pkgs; [
    #File sharing etc
    onedrive
    # Dropbox alternative -- use one or the other
    maestral
    maestral-gui

    # Microchip dev environment - from my overlay
    mplab-x
  ];
  home.file."${config.xdg.configHome}/onedrive/config".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nmd/onedrive-config";
  #Manually link to systemd service, as home-manager not doing it for us here
  home.file."${config.xdg.configHome}/systemd/user/onedrive.service".source = "${pkgs.onedrive}/lib/systemd/user/onedrive.service";

  # Zephyr development config
  home.sessionVariables = {
    ZEPHYR_BASE="${config.home.homeDirectory}/dev/ncs/zephyr";
  };
}
