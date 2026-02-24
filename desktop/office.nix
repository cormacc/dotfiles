{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    xsane
    #graphics
    gimp3-with-plugins
    krita
    # -> libreoffice and deps...
    libreoffice-fresh # -fresh avoids https://github.com/NixOS/nixpkgs/issues/495635 - March 2026
    hyphen
    hunspell
    hunspellDicts.en_GB-ise
    hunspellDicts.en_US
    # <- libreoffice and deps
  ];
}
