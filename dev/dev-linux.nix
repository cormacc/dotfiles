{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    zeal

    # Tools to help with nixpkg development...
    bubblewrap
  ];
}
