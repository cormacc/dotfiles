{ config, pkgs, ... }:
let
  # Source paths
  dotRoot = "${config.home.homeDirectory}/dotfiles";
  agentsRoot = "${dotRoot}/agents";
  piRoot = "${agentsRoot}/pi";
  skillsDir = "${agentsRoot}/skills";
  # Dest paths
  agentsConfig =  "${config.home.homeDirectory}/.agents";
  piConfig =  "${config.home.homeDirectory}/.pi/agent";
  # The xdg.configHome stuff causes pain / erratic detection...
  # piConfig = "${config.xdg.configHome}/pi";
  npmCache = "${config.xdg.cacheHome}/npm";
in
{
  # home.sessionVariables.PI_CODING_AGENT_DIR = "$piConfig";

  # npm's default global prefix points into the (read-only) Nix store when node
  # comes from nixpkgs. Redirect it to a writable location so `pi install` works.
  # This is philosophically unsound w.r.t. Nix, but a necessary hypocrisy...
  programs.npm = {
    enable = true;
    package = null; # nodejs is managed separately
    settings.prefix = "${npmCache}";
  };
  home.sessionPath = [ "${npmCache}/bin" ];

  home.packages = [
    #Pi + deps
    pkgs.llm-agents.pi
    pkgs.prettier
    pkgs.typescript-language-server
    #Claude code + deps
    pkgs.llm-agents.claude-code
    pkgs.meridian
    pkgs.llm-agents.codex
  ];

  home.file."${agentsConfig}/skills".source = config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills";
  home.file."${piConfig}/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/AGENTS.md";
  home.file."${piConfig}/prompts".source = config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/prompts";
  home.file."${piConfig}/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${piRoot}/settings.json";
  home.file."${piConfig}/extensions".source = config.lib.file.mkOutOfStoreSymlink "${piRoot}/extensions";
  # Keep pi-specific skills separate... these typically rely on specific pi extensions
  home.file."${piConfig}/skills".source = config.lib.file.mkOutOfStoreSymlink "${piRoot}/skills";
}
