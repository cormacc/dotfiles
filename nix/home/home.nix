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

  #TODO Does multiple shells confuse home manager
  programs.bash.enable = true;
  programs.zsh.enable = true;
  programs.fish.enable = true;

  home.file.".editorconfig".source="${dotfiles}/base/.editorconfig";

  #TODO: These trigger an opengl issue -- revisit
  #programs.wezterm.enable = true;
  #programs.alacritty.enable = true;

  home.file.".i3/config".source="${dotfiles}/i3/.i3/config";

  # Emacs and dependencies
  programs.emacs = {
    enable = true;
    package = pkgs.emacs29-gtk3;
  };

  #TODO: Rework to use xdg.whatever var
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
  #TODO: Move this to ~/.config/spacemacs once I figure out env
  home.file.".spacemacs.d".source = ~/dotfiles/emacs/.config/spacemacs;
  programs.pandoc.enable = true;

  #programs.vscode = {
    #enable = true;
    # I can't get the useUnfree options passed through to home manager yet
    # ... so use vscodium for now...
    #package = pkgs.vscodium;
    #extensions = with pkgs.vscode-extensions; [
      #dracula-theme.theme-dracula
      # vscodevim.vim
      # yzhang.markdown-all-in-one
    #];
  #};
}
