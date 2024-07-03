
{ config, pkgs, ... }:

{
  imports = [
    ./emacs/emacs.nix
  ];

  home.file.".editorconfig".source=./doteditorconfig;

  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      dracula-theme.theme-dracula
      vscodevim.vim
      yzhang.markdown-all-in-one
    ];
  };
}
