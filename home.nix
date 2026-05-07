{ config, pkgs, ... }:

{
  imports = [
    ./home-linux.nix
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
