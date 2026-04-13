{ config, pkgs, ... }:
let
  # Paths
  dotRoot = "${config.home.homeDirectory}/dotfiles";
  agentsRoot = "${dotRoot}/agents";
  piRoot = "${agentsRoot}/pi";
  skillsDir = "${agentsRoot}/skills";
in
{
  home.packages = [
    pkgs.llm-agents.pi
    pkgs.llm-agents.claude-code
  ];

  home.file.".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${piRoot}/settings.json";
  home.file.".pi/agent/extensions".source = config.lib.file.mkOutOfStoreSymlink "${piRoot}/extensions";
  home.file.".pi/agent/skills".source = config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills";
  home.file.".pi/agent/prompts".source = config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/prompts";

}
