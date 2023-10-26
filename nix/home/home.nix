{ config, pkgs, ... }:

let
  # Personal Info
  name = "Cormac Cannon";
  email = "cormacc@gmail.com";
  username = "cormacc";
  # Paths
  dotfiles = "/home/cormacc/dotfiles";
  # Preferences
  #font = "Hack";
  #backgroundColor = "#243442"; # Blue steel
  #foregroundColor = "#deedf9"; # Light blue
  #warningColor = "#e23131"; # Reddish
  #lockCmd = "${pkgs.i3lock-fancy}/bin/i3lock-fancy -p -t ''";
in
{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "${username}";
  home.homeDirectory = "/home/${username}";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "23.05";

  xdg.enable = true;
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    #TODO: rework to group dependencies with their programs in modules...
    #= fonts =
    source-code-pro
    jetbrains-mono
    #= i3 =
    j4-dmenu-desktop
    picom
    #ranger #managed by arch as dependency of bmenu...
    dunst
    #i3-scrot #not in nixpgs
    #= emacs =
    aspell
    aspellDicts.en
    plantuml-c4
  ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    initExtra = ''
      . ./dotfiles/nmd/.profile.d/nmd-dir-nav.sh
    '';
  };
  programs.zsh = {
    enable = true;
    initExtra = ''
      . ./dotfiles/nmd/.profile.d/nmd-dir-nav.sh
    '';
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

  programs.ssh = {
    enable = true;
    #TODO: Vaguely remember these relating to emacs/tramp.. reinstate as needed
    # controlMaster = "auto";
    # controlPath = "~/.ssh/master-%r@%h:%p";
    # serverAliveInterval = 15;
    matchBlocks = {
      nmd-git = {
        hostname = "git.nmd.ie";
        user = "ec2-user";
        port = 1022;
      };
    };
  };

  programs.git = {
    enable = true;
    delta.enable = true;
    lfs.enable = true;
    userName = "Cormac Cannon";
    userEmail = "cormacc@gmail.com";
  };

  home.sessionVariables = {
    EDITOR = "vim";
    #Use xdg-config layout for spacemacs
    SPACEMACSDIR = "${config.xdg.configHome}/spacemacs";
    #Use fish as default shell, but NOT login shell as not posix compliant
    TERMINAL = "kitty -e /usr/bin/fish";
  };

  home.shellAliases = {

  };


  # Shell scripts
  home.file.".local/bin/kbmap".source="${dotfiles}/xorg/bin/kbmap";
  home.file.".local/bin/caps-lock-off".source="${dotfiles}/xorg/bin/caps-lock-off";
  home.file.".local/bin/md2org".source="${dotfiles}/emacs/bin/md2org";
  home.file.".local/bin/org2md".source="${dotfiles}/emacs/bin/org2md";
  home.file.".local/bin/syncup".source="${dotfiles}/git/bin/syncup";

  # Configuration data
  home.file.".editorconfig".source="${dotfiles}/base/.editorconfig";
  # ... MBT IOD bootloader configuration
  home.file.".mutebutton".source="${dotfiles}/nmd/.mutebutton";

  #TODO: These trigger an opengl issue -- install via OS package manager for now and revisit
  #programs.alacritty.enable = true;
  #programs.kitty.enable = true;

  home.file.".config/i3/config".source="${dotfiles}/i3/.config/i3/config";

  # Emacs and dependencies
  programs.emacs = {
    enable = true;
    package = pkgs.emacs29-gtk3;
  };

  home.file."${config.xdg.configHome}/emacs" = {
   recursive = true;
   #Use this variant to pin a specific commit
   # source = pkgs.fetchFromGitHub {
   #   owner = "syl20bnr";
   #   repo = "spacemacs";
   #   rev = "e4b20f797d9e7a03d9a5603942c4a51ea19047b2";
   #   #N.B. If updating rev above, new sha256 will be reported when trying to swap this flake in, and can be pasted here
   #   sha256 = "OdZuOmxDYvvsCnu9TcogCeB0agCq8o20/YPCmUSwYPw=";
   # };
   #... or this variant to track a branch
   source = builtins.fetchGit {
    url = "https://github.com/syl20bnr/spacemacs";
    ref = "develop";
   };
  };
  home.file."${config.xdg.configHome}/spacemacs".source = ~/dotfiles/emacs/.config/spacemacs;

  programs.pandoc.enable = true;

  #programs.vscode = {
    #enable = true;
    # I can't get the useUnfree options passed through to home manager yet
    # ... when using NixOS anyway
    # ... so use vscodium for now...
    #package = pkgs.vscodium;
    #extensions = with pkgs.vscode-extensions; [
      #dracula-theme.theme-dracula
      # vscodevim.vim
      # yzhang.markdown-all-in-one
    #];
  #};
}
