{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nerdfonts
    zeal # requires opengl

    babashka # shell scripting in clojure
    bundix

    # Tools to help with nixpkg development...
    bubblewrap

    # Should install these per project... but bridging the gap while flakifying all the things...
    # UPDATE: Install at OS-level instead -- nix-profile python complicates some package installation on arch linux
    # python3
    # pipenv
    # poetry
  ];
}
