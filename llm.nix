{ inputs, system, config, pkgs, ... }:

{
  #N.B. This is for hybrid use within home-manager
  #     If running nixos, probably better to use nixos level modules to install these
  #     May be easier to get GPU acceleration etc. up and running...

  # Bypass local llm stuff for now -- nix installed llm tools can't access GPU
  # TODO: Check if this is the case after adding user to the 'render' group...
  home.packages = [
    # TODO: Add open-webui
    # pkgs.ollama
    # pkgs.llama-cpp
    # pkgs.cherry-studio
    pkgs.claude-code
    pkgs.nur.repos.charmbracelet.crush
    inputs.claude.packages.${system}.claude-desktop
    #... this may cause issues with aur on arch - see wayland.nix
    # (python3.withPackages (python-pkgs: with python-pkgs; [
    #   huggingface-hub
    # ]))
  ];
}
