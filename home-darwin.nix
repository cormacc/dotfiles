{ config, pkgs, lib, ... }:

{
  imports = [
    ./home-core.nix
    ./editors/editors.nix
    ./dev/dev.nix
    ./agents.nix
  ];

  services.syncthing = {
   enable = true;
  };
}
