{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # FIXME: Audacity v4.00 build failing 21/10/2026
    # audacity
    # Link REAPER's JACK backend to PipeWire's JACK library, not libjack2,
    # so that it needs no jackd and no global LD_LIBRARY_PATH.
    (reaper.override { jackLibrary = pipewire.jack; })
  ];
}
