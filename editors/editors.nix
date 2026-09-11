
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
    source = builtins.fetchGit {
      url = "https://github.com/practicalli/nvim-astro";
      ref = "main";
    };
  };
}
