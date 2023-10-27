{ config, pkgs, ... }:

let
  sharedInit = ''
     . ./dotfiles/nmd/.profile.d/nmd-dir-nav.sh
  '';
in {
  home.sessionVariables = {
    EDITOR = "vim";
    #Use fish as default shell, but NOT login shell as not posix compliant
    TERMINAL = "kitty -e /usr/bin/fish";
  };

  #TODO: These trigger an opengl issue -- install via OS package manager for now and revisit
  #programs.alacritty.enable = true;
  #programs.kitty.enable = true;

  programs.bash = {
    enable = true;
    initExtra = sharedInit;
  };

  programs.zsh = {
    enable = true;
    initExtra = sharedInit;
    antidote = {
      enable = true;
      useFriendlyNames = true;
      # See https://github.com/getantidote/zdotdir/blob/main/.zsh_plugins.txt
      plugins = [
        "peterhurford/up.zsh"
        "rummik/zsh-tailf"
        "mattmc3/zman"
        "agkozak/zsh-z"
        "romkatv/powerlevel10k kind:fpath"
        "sindresorhus/pure"
        "ohmyzsh/ohmyzsh path:lib/clipboard.zsh"
        "ohmyzsh/ohmyzsh path:plugins/copybuffer"
        "ohmyzsh/ohmyzsh path:plugins/copyfile"
        "ohmyzsh/ohmyzsh path:plugins/copypath"
        "ohmyzsh/ohmyzsh path:plugins/extract"
        "ohmyzsh/ohmyzsh path:plugins/magic-enter"
        "ohmyzsh/ohmyzsh path:plugins/fancy-ctrl-z"
        "belak/zsh-utils path:history"
        "belak/zsh-utils path:utility"
        "belak/zsh-utils path:editor"
        "zdharma-continuum/fast-syntax-highlighting kind:defer"
        "zsh-users/zsh-completions path:src kind:fpath"
        "belak/zsh-utils path:completion"
        "zsh-users/zsh-autosuggestions kind:defer"
        "zsh-users/zsh-history-substring-search"
      ];
    };
  };
  programs.fish.enable = true;

}
