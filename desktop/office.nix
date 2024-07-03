{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # -> libreoffice and deps...
    libreoffice
    hyphen
    hunspell
    hunspellDicts.en_GB-ise
    hunspellDicts.en_US
    # <- libreoffice and deps
  ];
}
