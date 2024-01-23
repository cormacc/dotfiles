{ config, pkgs, specialArgs, ... }:

let
  # Input parameters
  inherit (specialArgs) host;

  # Personal Info
  name = "Cormac Cannon";
  email = "cormacc@gmail.com";
  username = "cormacc";

  # Paths
  homedir = "/home/${username}";
  dotRoot = "${homedir}/dotfiles";
  flakePath = "${dotRoot}#${host}";
  hostRoot = "${dotRoot}/hosts/${host}";
in
{

  imports = [
    ./shell/shell.nix
    ./emacs/emacs.nix
    ./nmd/nmd.nix
  ];

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

  # Allow unfree packages
  # FIXME: I've tried setting the relevant options in flake.nix but not
  # working for me - hence the session variable workaround
  home.sessionVariables = {
    NIXPKGS_ALLOW_UNFREE = 1;
  };

  home.shellAliases = {
    hmb = "home-manager build --flake '${flakePath}' --impure";
    hms = "home-manager switch --flake '${flakePath}' --impure";
  };

  services.syncthing = {
    enable = true;
    tray = {
      enable = true;
    };
  };
  # TODO: Add some configuration here?

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
    #cache the direnv environment -- faster rebuild
    nix-direnv.enable = true;
    #Additional content for .config/direnv/direnvrc
    #N.B. home-manager appends "source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc" to the provided content
    stdlib = (builtins.readFile ./shell/direnvrc);
  };

  xdg.enable = true;

  home.language.base = "en_IE.UTF-8";
  #FIXME: This isn't applied for some reason...
  #....   When using sway, applied via sway config instead...
  home.keyboard.options = [
    "caps:escape_shifted_capslock"
  ];

  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    source-code-pro
    jetbrains-mono
    moosefs
    # programming
    # zeal # requires opengl
    # audio
    audacity
    reaper
    # desktop
    libreoffice
  ];

  programs.ssh = {
    enable = true;
    extraConfig = "Host github.com
  Hostname github.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519_personal";
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
  home.file.".local/bin/syncup".source="${dotRoot}/git/bin/syncup";

  # Shell scripts
  home.file.".local/bin/kbmap".source="${dotRoot}/xorg/bin/kbmap";
  home.file.".local/bin/caps-lock-off".source="${dotRoot}/xorg/bin/caps-lock-off";
  # ... per-host shell-scripts
  # home.file.".local/bin/dock".source="${hostRoot}/bin/dock";

  home.file.".editorconfig".source="${dotRoot}/emacs/.editorconfig";

  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      dracula-theme.theme-dracula
      vscodevim.vim
      yzhang.markdown-all-in-one
    ];
  };

}
