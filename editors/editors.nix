
{ config, pkgs, ... }:

{
  imports = [
    ./emacs/emacs.nix
  ];

  programs.neovim = {
    enable = true;
    withRuby = false;
    withPython3 = false;
    # viAlias = true;
    # vimAlias = true;
  };
  # See https://practical.li/neovim/install/neovim/#install-neovim
  home.file."${config.xdg.configHome}/nvim" = {
    recursive = true;
    # `rev` pinned for reproducibility -- without it, `builtins.fetchGit`
    # would refetch the upstream tip on every evaluation. Bump by
    # running `nix-prefetch-git --no-deepClone --quiet \
    #   https://github.com/practicalli/astro --rev refs/heads/main` and
    # pasting the reported `rev` here.
    source = builtins.fetchGit {
      url = "https://github.com/practicalli/astro";
      ref = "main";
      rev = "3ac63389d7da31df9afbf4d01f37064447e9e837";
    };
  };
  # Requires settings to be defined ... revisit
  # programs.neovide.enable = true;

  # programs.vscode = {
  #   enable = true;
  #   profiles.default.extensions = with pkgs.vscode-extensions; [
  #     dracula-theme.theme-dracula
  #     vscodevim.vim
  #     yzhang.markdown-all-in-one
  #   ];
  # };
}
