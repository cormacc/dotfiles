{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    nerdfonts
    zeal # requires opengl

    # Tools to help with nixpkg development...
    bundix
    bubblewrap

    # llm
    ollama
    llama-cpp
    #... this may cause issues with aur on arch - see wayland.nix
    (python3.withPackages (python-pkgs: with python-pkgs; [
      huggingface-hub
    ]))
  ];
}
