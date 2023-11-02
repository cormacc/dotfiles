{ config, pkgs, ... }:

let
  # Personal Info
  name = "Cormac Cannon";
  email = "cormacc@gmail.com";
  username = "cormacc";
  # Paths
  dotfiles = "/home/cormacc/dotfiles";
  flakePath = "path:${dotfiles}/nix/home#${username}";
  # Preferences
  #font = "Hack";
  #backgroundColor = "#243442"; # Blue steel
  #foregroundColor = "#deedf9"; # Light blue
  #warningColor = "#e23131"; # Reddish
  #lockCmd = "${pkgs.i3lock-fancy}/bin/i3lock-fancy -p -t ''";
in
{
  imports = [
    ./modules/i3.nix
    ./modules/shells.nix
    ./modules/emacs.nix
    ./modules/nmd.nix
  ];

  #FIXME: Should be able to define this once
  my.i3.dotRoot = dotfiles;
  my.emacs.dotRoot = dotfiles;
  my.nmd.dotRoot = dotfiles;

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

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.shellAliases = {
    hmb = "home-manager build --flake '${flakePath}' --impure";
    hms = "home-manager switch --flake '${flakePath}' --impure";
  };

  # To setup direnv in a given folder...
  # 1. create a flake.nix in the folder
  # 2. create a .envrc with the content "use flake"
  # 3. run 'direnv allow' in the folder
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    # direnv implicitly enabled for fish -- trying to do so here results in error
    # enableFishIntegration = true;
    enableZshIntegration = true;
    #cache the shell environment
    nix-direnv.enable = true;
  };

  xdg.enable = true;

  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    source-code-pro
    jetbrains-mono
  ];

  programs.ssh = {
    enable = true;
    #TODO: Vaguely remember these relating to emacs/tramp.. reinstate as needed
    # controlMaster = "auto";
    # controlPath = "~/.ssh/master-%r@%h:%p";
    # serverAliveInterval = 15;
  };

  programs.git = {
    enable = true;
    delta.enable = true;
    lfs.enable = true;
    userName = "Cormac Cannon";
    userEmail = "cormacc@gmail.com";
  };
  home.file.".local/bin/syncup".source="${dotfiles}/git/bin/syncup";

  # Shell scripts
  home.file.".local/bin/kbmap".source="${dotfiles}/xorg/bin/kbmap";
  home.file.".local/bin/caps-lock-off".source="${dotfiles}/xorg/bin/caps-lock-off";

  home.file.".editorconfig".source="${dotfiles}/base/.editorconfig";


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
