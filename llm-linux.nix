{ pkgs, ... }:

{
  # Bypass local llm stuff for now -- nix installed llm tools can't access GPU
  # TODO: Check if this is the case after adding user to the 'render' group...
  home.packages = [
    # TODO: Add open-webui
    # pkgs.ollama
    # pkgs.llama-cpp
    # pkgs.claude-desktop
    #... this may cause issues with aur on arch - see wayland.nix
    # (python3.withPackages (python-pkgs: with python-pkgs; [
    #   huggingface-hub
    # ]))
  ];
}
