{ config, pkgs, ... }:

{
  # ... MBT IOD bootloader configuration
  home.file.".mutebutton".source=./.mutebutton;
}
