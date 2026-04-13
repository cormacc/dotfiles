{ inputs, system, config, pkgs, ... }:
let
  beads = inputs.beads-flake.packages.${system}.default;

  # Paths
  homedir = builtins.getEnv "HOME";
  dotRoot = "${homedir}/dotfiles";
  agentsRoot = "${dotRoot}/agents";
  skillsDir = "${agentsRoot}/skills";
  extensionsDir = "${agentsRoot}/pi/extensions";
in
{
  imports = [ inputs.coding-agents.homeManagerModules.default ];

  nixpkgs.overlays = [
    inputs.coding-agents.overlays.default
    # inputs.claude-code.overlays.default
    inputs.claude-desktop.overlays.default
  ];

  coding-agents = {
    claude-code.enable = true;
    skillsDir = skillsDir;
    pi-coding-agent = {
      enable = true;
      extensionsDir = extensionsDir;
    };
  };


  #N.B. This is for hybrid use within home-manager
  #     If running nixos, probably better to use nixos level modules to install these
  #     May be easier to get GPU acceleration etc. up and running...

  # Bypass local llm stuff for now -- nix installed llm tools can't access GPU
  # TODO: Check if this is the case after adding user to the 'render' group...
  home.packages = [
    # TODO: Add open-webui
    # pkgs.ollama
    # pkgs.llama-cpp
    # pkgs.claude-code
    pkgs.claude-desktop
    #... this may cause issues with aur on arch - see wayland.nix
    # (python3.withPackages (python-pkgs: with python-pkgs; [
    #   huggingface-hub
    # ]))
  ];
}
