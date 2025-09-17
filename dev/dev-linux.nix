{ config, pkgs, ... }:

{
  imports = [
    ./dev.nix
  ];

  home.packages = with pkgs; [
    zeal # requires opengl

    # Tools to help with nixpkg development...
    bubblewrap
  ];
}
