{ config, pkgs, ... }:

let
  dir-nav-posix = ".profile.d/dir-nav.sh";
  sharedPosixInit = ''
     . ~/${dir-nav-posix}
     . ~/.profile
  '';
in {

  home.packages = with pkgs; [
    babashka # shell scripting in clojure
    unzip
    p7zip
  ];

  #Folder nav shell shortcuts
  home.file."${dir-nav-posix}".source = ./dir-nav.sh;

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    #pinentry.package = pkgs.pinentry-gnome3;
  };

  programs.starship.enable = true;

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
    initContent = ''${sharedPosixInit}
      _bb_tasks() {
    local matches=(`bb tasks |tail -n +3 |cut -f1 -d ' '`)
    compadd -a matches
    _files # autocomplete filenames as well
}
compdef _bb_tasks bb'';
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
}
