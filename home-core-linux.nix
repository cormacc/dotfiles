{ config, pkgs, ... }:

let
  username = builtins.getEnv "USER";
  homedir = builtins.getEnv "HOME";
in
{
  home.username = "${username}";
  home.homeDirectory = "${homedir}";

  imports = [
    ./home-core.nix
  ];
}
