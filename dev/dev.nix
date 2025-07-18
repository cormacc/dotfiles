{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nerd-fonts.roboto-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.inconsolata
    nerd-fonts.hack
    nerd-fonts.fira-code
    nerd-fonts.caskaydia-cove

    zeal # requires opengl

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
    rust-bin.stable.latest.default

    # Misc tools
    libxml2

    # Programming assistance
    aider-chat
  ];

  imports = [
    ./clojure/clojure.nix
  ];
}
