{ config, pkgs, ... }:

{
  imports = [
    ./home-core-linux.nix
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

  # This is duplicated here and in home-darwin - should these be consolidated?
  services.syncthing = {
    enable = true;
  };
}
