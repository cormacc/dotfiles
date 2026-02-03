{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nerd-fonts.roboto-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.inconsolata
    nerd-fonts.hack
    nerd-fonts.fira-code
    nerd-fonts.caskaydia-cove

    # Tools to help with nixpkg development...
    bundix
    bubblewrap

    # Serial terminal
    minicom

    # Compilers etc. for evaluating 3rd party repos without a flake...
    # ... js
    nodejs
    bun
    # ... rust
    #rust-bin.stable.latest.default
    cargo
    rustc

    # Misc tools
    libxml2
  ];

  imports = [
    ./clojure/clojure.nix
  ];
}
