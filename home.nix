{ config, pkgs, specialArgs, ... }:

let
  # Input parameters
  inherit (specialArgs) cfgName;

  # Personal Info
  name = builtins.getEnv "NAME";
  email = builtins.getEnv "EMAIL";
  username = builtins.getEnv "USER";

  # Paths
  homedir = builtins.getEnv "HOME";
  dotRoot = "${homedir}/dotfiles";
  flakePath = "${dotRoot}#${cfgName}";
in
{

  imports = [
    ./shell/shell.nix
    # Include these at flake level instead?
    ./nmd/nmd.nix
    ./wayland/wayland.nix
    ./wayland/sway/sway.nix
    ./wayland/hypr/hypr.nix
    ./editors/editors.nix
    # Bypass for now -- nix-installed chromium can't use hardware acceleration - on non NixOS at least
    # ./desktop/web.nix
    ./desktop/audio.nix
    ./programming.nix
    ./desktop/office.nix
    ./sysadmin.nix
    # ./desktop/entertainment.nix
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
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Allow unfree packages
  # FIXME: I've tried setting the relevant options in flake.nix but not
  # working for me - hence the session variable workaround
  home.sessionVariables = {
    NIXPKGS_ALLOW_UNFREE = 1;
    #persist name and e-mail env variables from initial config...
    NAME = "${name}";
    EMAIL = "${email}";
  };

  home.shellAliases = {
    hmb = "home-manager build --flake '${flakePath}' --impure";
    hms = "home-manager switch --flake '${flakePath}' --impure";
    nob = "nixos-rebuild build --flake '${flakePath}' --impure";
    nos = "sudo nixos-rebuild switch --flake ${flakePath}#`cat /etc/hostname` --impure";
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
  #...    When using sway, applied via sway config instead...
  #...    But would be nice to have it applied globally for gnome etc.
  home.keyboard.options = [
    "caps:escape_shifted_capslock"
  ];

  fonts.fontconfig.enable = true;

  programs.ssh = {
    enable = true;
    # Use personal rather than work key for OSS
    extraConfig = "Host github.com
  Hostname github.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519_personal

  Host gitlab.com
  Hostname gitlab.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519_personal
";
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
  home.file.".local/bin/syncup".source=./git/bin/syncup;

}
