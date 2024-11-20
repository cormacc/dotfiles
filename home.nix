{ config, pkgs, specialArgs, ... }:

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
    ./nmd/nmd.nix
    ./wayland/wayland.nix
    ./wayland/sway/sway.nix
    ./wayland/hypr/hypr.nix
    ./editors/editors.nix
    # Bypass for now -- nix-installed chromium can't use hardware acceleration - on non NixOS at least
    # ./desktop/web.nix
    ./desktop/audio.nix
    ./programming.nix
    # Bypass for now -- nix installed llm tools can't access GPU
    # ./llm.nix
    ./desktop/office.nix
    ./sysadmin.nix
    # ./desktop/entertainment.nix
  ];

  services.syncthing = {
    enable = true;
    tray = {
      enable = true;
    };
  };
  # TODO: Add some configuration here?


  #TODO: Done in home-core.nix, but maybe shouldn't be...
  #xdg.enable = true;
}
