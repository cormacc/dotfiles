{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nerdfonts
    zeal # requires opengl

    # Tools to help with nixpkg development...
    bundix
    bubblewrap

    # Serial terminal
    minicom
  ];
}
