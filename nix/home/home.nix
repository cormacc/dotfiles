{ config, pkgs, ... }:

let
  # Personal Info
  name = "Cormac Cannon";
  email = "cormacc@gmail.com";
  username = "cormacc";
  # Paths
  dotfiles = "/home/cormacc/sync/dotfiles";
  #scripts = "/home/jon/Dotfiles/scripts";
  #maildir = "/home/jon/Mail";
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
    #FIXME: I'd like to group dependencies with their programs below...
    #fonts
    source-code-pro
    jetbrains-mono
    # emacs
    aspell
    aspellDicts.en
    plantuml-c4
  ];

  # Let Home Manager install and manage itself.
  # N.B. this causes an error
  # programs.home-manager.enable = true;

  home.file.".editorconfig".source="${dotfiles}/base/.editorconfig";

  # Emacs and dependencies
  #... installing at system level instead...
  #... as haven't figured out overlays in home-manager...
  #... yet ...
  # programs.emacs.enable = true;
  home.file.".config/emacs" = {
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
  #TODO: Move this to ~/.config/spacemacs once I figure out env
  home.file.".spacemacs.d".source = ~/sync/dotfiles/emacs/.config/spacemacs;
  programs.pandoc.enable = true;

  programs.vscode = {
    enable = true;
    # I can't get the useUnfree options passed through to home manager yet
    # ... so use vscodium for now...
    package = pkgs.vscodium;
    extensions = with pkgs.vscode-extensions; [
      dracula-theme.theme-dracula
      # vscodevim.vim
      # yzhang.markdown-all-in-one
    ];
  };
}
