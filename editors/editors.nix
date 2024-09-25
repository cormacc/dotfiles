
{ config, pkgs, ... }:

{
  imports = [
    ./emacs/emacs.nix
  ];

  programs.neovim = {
    enable = true;
    # viAlias = true;
    # vimAlias = true;
  };
  # See https://practical.li/neovim/install/neovim/#install-neovim
  home.file."${config.xdg.configHome}/nvim" = {
    recursive = true;
    source = builtins.fetchGit {
      url = "https://github.com/practicalli/astro";
      ref = "main";
    };
  };
  # Requires settings to be defined ... revisit
  # programs.neovide.enable = true;

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      dracula-theme.theme-dracula
      vscodevim.vim
      yzhang.markdown-all-in-one
    ];
  };
}
