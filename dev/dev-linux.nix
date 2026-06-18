{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    zeal
    dirge

    # Tools to help with nixpkg development...
    bubblewrap
  ];

  # dirge ':' shell plugin -- type `:<prompt>` at the zsh prompt to talk to
  # dirge headlessly, sharing one session per shell. Sourced from the dirge
  # source tree; DIRGE_BIN pins it to the installed binary so it doesn't rely
  # on PATH ordering. See pkgs/dirge and
  # https://github.com/dirge-code/dirge/blob/main/shell-plugin/README.md
  programs.zsh.initContent = lib.mkAfter ''
    export DIRGE_BIN=${lib.getExe pkgs.dirge}
    source ${pkgs.dirge.src}/shell-plugin/dirge.plugin.zsh
  '';

  #This isn't available in nixpkgs for darwin for some reason...
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "Dracula+";
      keybind = [
        # See https://pi.dev/docs/latest/terminal-setup
        "alt+backspace=text:\x1b\x7f"
      ];
    };
  };
}
