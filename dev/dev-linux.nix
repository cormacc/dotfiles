{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    zeal

    # Tools to help with nixpkg development...
    bubblewrap

    # Local package (pkgs/limux/default.nix)
    limux
  ];

  #This isn't available in nixpkgs for darwin for some reason...
  programs.ghostty = {
    enable = true;
    settings = {
      keybind = [
        # See https://pi.dev/docs/latest/terminal-setup
        "alt+backspace=text:\x1b\x7f"
      ];
    };
  };
}
