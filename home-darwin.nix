{ config, pkgs, lib, ... }:

{
  imports = [
    ./home-core.nix
    ./editors/editors.nix
    ./dev/dev.nix
    ./agents.nix
  ];

  # HM 25.11 flipped the macOS default from linkApps -> copyApps, which on
  # macOS 26.1 requires granting "App Management" permission to the invoking
  # terminal (Privacy & Security > App Management). Stay on the older symlink
  # behaviour so `darwin-rebuild switch` does not need that permission.
  targets.darwin.copyApps.enable = false;
  targets.darwin.linkApps.enable = true;

  services.syncthing = {
   enable = true;
  };
}
