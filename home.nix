{ config, pkgs, nixgl, system, specialArgs, ... }:

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
  # nixgl config -- a np for nixos, but useful on hybrid config...
  targets.genericLinux.nixGL = {
    packages = nixgl.packages.${system};
    defaultWrapper = "mesa";
    offloadWrapper = "nvidiaPrime";
    installScripts = [ "mesa" ];
  };

  imports = [
    ./home-linux.nix
    # Include these at flake level instead?
    ./nmd/nmd.nix
    ./wayland/wayland.nix
    ./wayland/sway/sway.nix
    ./wayland/hypr/hypr.nix
    ./editors/editors.nix
    ./desktop/web.nix
    ./desktop/audio.nix
    ./dev/dev.nix
    ./dev/dev-linux.nix
    ./agents.nix
    ./desktop/office.nix
    # ./sysadmin.nix
    # ./desktop/entertainment.nix
  ];

  services.syncthing = {
    enable = true;
    # tray = {
    #   enable = true;
    # };
  };
  # TODO: Add some configuration here?


  #TODO: Done in home-core.nix, but maybe shouldn't be...
  #xdg.enable = true;
}
