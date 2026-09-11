{ config, lib, pkgs, ... }:

let
  dir-nav-posix = ".profile.d/dir-nav.sh";

  # dir-nav.sh is the single definition of the folder-navigation shortcuts.
  # Fish cannot source POSIX shell, so translate it line by line: every
  # function there is `function NAME() {` ... `}` with `$1` as its argument.
  toFish = line:
    let m = builtins.match "function ([a-zA-Z0-9_]+)\\(\\) \\{" line;
    in if m != null then "function ${builtins.head m}"
       else if line == "}" then "end"
       else builtins.replaceStrings [ "$1" ] [ "$argv[1]" ] line;
  dir-nav-fish = lib.concatMapStringsSep "\n" toFish
    (lib.splitString "\n" (builtins.readFile ./dir-nav.sh));

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
  ];

  home.shell = {
    enableShellIntegration = true;
  };

  #Folder nav shell shortcuts
  home.file."${dir-nav-posix}".source = ./dir-nav.sh;

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    #pinentry.package = pkgs.pinentry-gnome3;
  };

  programs.starship = {
    enable = true;
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

        # Prompt: starship, configured via programs.starship above

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
    # Folder navigation, translated from the canonical shell/dir-nav.sh.
    interactiveShellInit = dir-nav-fish;
  };

  home.file.".config/fish/completions/bb.fish".source = ./bb.fish;
  home.file.".local/bin/bbg".source=./bbg/bbg;
  home.file.".config/bbg".source=config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/shell/bbg";

  programs.zellij.enable = true;
  programs.zoxide.enable = true;
  programs.lazygit.enable = true;

  programs.tmux = {
    enable = true;
    clock24 = true;
    keyMode = "vi";
    mouse = true;
    extraConfig = ''
      set -s extended-keys on
      set -s extended-keys-format csi-u
      set -as terminal-features 'xterm*:extkeys'
      set-option -g status-position top
    '';
    plugins = with pkgs.tmuxPlugins; [
        sensible
        yank
        {
            plugin = dracula;
            extraConfig = ''
                set -g @dracula-plugins "weather location"
                set -g @dracula-show-fahrenheit false
                set -g @dracula-fixed-location "Salthill"
                set -g @dracula-show-powerline true
                set -g @dracula-show-left-icon "#h | #S"
            '';
        }
     ];
  };
}
