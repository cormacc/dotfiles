{ config, pkgs, ... }:

{
  #N.B. This is for hybrid use within home-manager
  #     If running nixos, probably better to use nixos level modules to install these
  #     May be easier to get GPU acceleration etc. up and running...
  home.packages = with pkgs; [
    # TODO: Add open-webui
    ollama
    llama-cpp
    #... this may cause issues with aur on arch - see wayland.nix
    (python3.withPackages (python-pkgs: with python-pkgs; [
      huggingface-hub
    ]))
  ];
}
