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
  imports = [
    ./home-core.nix
    # Include these at flake level instead?
    #./nmd/nmd.nix
    ./editors/editors.nix
    ./dev/dev.nix
    #./desktop/office.nix
  ];

  services.syncthing = {
   enable = true;
  };
}
