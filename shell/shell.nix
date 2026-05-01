{ config, pkgs, ... }:

let
  dir-nav-posix = ".profile.d/dir-nav.sh";
  sharedPosixInit = ''
     . ~/${dir-nav-posix}
     export PATH="$HOME/.local/bin:$PATH"
  '';
in {

  home.packages = with pkgs; [
    babashka # shell scripting in clojure
    bbin
    unzip
    p7zip
    zsh-powerlevel10k
  ];

  #Folder nav shell shortcuts
  home.file."${dir-nav-posix}".source = ./dir-nav.sh;

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    #pinentry.package = pkgs.pinentry-gnome3;
  };

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  programs.ranger.enable = true;

  #Alternatives/enhancements to standard posix commands
  #fd (find) :: https://github.com/sharkdp/fd
  programs.fd.enable = true;
  #eza (ls) :: https://github.com/eza-community/eza
  programs.eza.enable = true;

  programs.bash = {
    enable = true;
    initExtra = ''${sharedPosixInit}
      _bb_tasks() {
    COMPREPLY=( $(compgen -W "$(bb tasks |tail -n +3 |cut -f1 -d ' ')" -- ''${COMP_WORDS[COMP_CWORD]}) );
}
# autocomplete filenames as well
complete -f -F _bb_tasks bb'';
  };

  programs.zsh = {
    enable = true;
    # This is the new default for stateversion >= 26.05
    dotDir = "${config.xdg.configHome}/zsh";
    autosuggestion.enable = true;
    syntaxHighlighting = {
      enable = true;
      styles.cursor = "fg=#ffffff";
    };
    initContent = ''${sharedPosixInit}
      _bb_tasks() {
         local matches=(`bb tasks |tail -n +3 |cut -f1 -d ' '`)
         compadd -a matches
         _files # autocomplete filenames as well
      }
      compdef _bb_tasks bb

      # Source your custom p10k configuration
      # [[ ! -f ~/.config/zsh/.p10k.zsh ]] || source ~/.config/zsh/.p10k.zsh
   '';
   antidote = {
      enable = true;
      useFriendlyNames = true;
      # See https://github.com/getantidote/zdotdir/blob/main/.zsh_plugins.txt
      plugins = [
        # Completions
        "mattmc3/ez-compinit"
        "zsh-users/zsh-completions path:src kind:fpath"
        # Completion styles
        "belak/zsh-utils path:completion/functions kind:autoload post:compstyle_zshzoo_setup"

        # Keybindings
        "belak/zsh-utils path:editor"

        # History
        "belak/zsh-utils path:history"

        # Prompt
        # "romkatv/powerlevel10k"

        # Utilities
        "belak/zsh-utils path:utility"
        "romkatv/zsh-bench kind:path"
        "ohmyzsh/ohmyzsh path:plugins/extract"

        # Other Fish-like features
        "zdharma-continuum/fast-syntax-highlighting"  # Syntax highlighting
        "zsh-users/zsh-autosuggestions"               # Auto-suggestions
        "zsh-users/zsh-history-substring-search"      # Up/Down to search history
      ];
    };
  };
  programs.fish = {
    enable = true;
    functions = {
      # Folder navigation
      n = "pushd ~/nmd/$argv[1]";
      p = "n products/$argv[1]";
      d = "pushd \"${config.home.homeDirectory}/Neuromod\ Devices\ Dropbox/$argv[1]\"";
      t = "d NMDProductTesting/$argv[1]";
      it = "d NMDIT/$argv[1]";
      pd = "d Product_Development/$argv[1]";
    };
  };

  home.file.".config/fish/completions/bb.fish".source = ./bb.fish;
  home.file.".local/bin/bbg".source=./bbg/bbg;
  home.file.".config/bbg".source=config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/shell/bbg";
}
