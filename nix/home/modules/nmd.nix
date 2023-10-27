{ lib, config, pkgs, ... }:
with lib;
let
  dotRoot = config.my.nmd.dotRoot;
in {
  options.my.nmd = {
    dotRoot = mkOption {
      type = types.path;
      default = "";
    };
  };
  config = {
    # ... MBT IOD bootloader configuration
    home.file.".mutebutton".source="${dotRoot}/nmd/.mutebutton";
  };
}
