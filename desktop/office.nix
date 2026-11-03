{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    simple-scan
    #graphics
    gimp3-with-plugins
    krita
    # -> libreoffice and deps...
    libreoffice
    hyphen
    hunspell
    hunspellDicts.en_GB-ise
    hunspellDicts.en_US
    # <- libreoffice and deps
  ];
}
