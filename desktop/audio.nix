{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # FIXME: Audacity v4.00 build failing 21/10/2026
    # audacity
    reaper
  ];
}
