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
  ];
}
