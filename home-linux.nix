{ config, pkgs, nixgl, specialArgs, ... }:

let
  # Input parameters
  inherit (specialArgs) cfgName;

  # Personal Info
  name = builtins.getEnv "NAME";
  email = builtins.getEnv "EMAIL";
  username = builtins.getEnv "USER";

  # Paths
  homedir = builtins.getEnv "HOME";
  dotRoot = "${homedir}/dotfiles";
  flakePath = "${dotRoot}#${cfgName}";
in
{

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "${username}";
  home.homeDirectory = "${homedir}";

  imports = [
    ./home-core.nix
  ];
}
