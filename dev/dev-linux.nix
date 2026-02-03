{ config, pkgs, nixgl, ... }:

{
  home.packages = with pkgs; [
    (config.lib.nixGL.wrap zeal)
  ];
}
