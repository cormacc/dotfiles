{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nerdfonts
    zeal # requires opengl

    babashka # shell scripting in clojure
    bundix

    # Tools to help with nixpkg development...
    bubblewrap
  ];
}
