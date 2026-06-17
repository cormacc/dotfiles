{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    zeal
    dirge

    # Tools to help with nixpkg development...
    bubblewrap
  ];

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
