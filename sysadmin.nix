{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    ventoy
  ];
}
