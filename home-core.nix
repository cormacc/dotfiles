{ config, pkgs, specialArgs, ... }:

let
  # Input parameters
  inherit (specialArgs) cfgName;

  # Personal Info
  name = builtins.getEnv "NAME";
  email = builtins.getEnv "EMAIL";
  # Personal / OSS git identity. Defaults to $EMAIL when unset so a
  # single-identity setup needs no extra env var. Scoped to ~/dev/ via
  # a git includeIf below.
  emailOss =
    let v = builtins.getEnv "EMAIL_OSS";
    in if v == "" then email else v;
  username = builtins.getEnv "USER";

  # Paths
  homedir = builtins.getEnv "HOME";
  dotRoot = "${homedir}/dotfiles";
  flakePath = "${dotRoot}#${cfgName}";

  # Secrets
  gitlabHost = builtins.getEnv "GITLAB";
  # openaiKey = builtins.getEnv "OPENAI_API_KEY";
  # anthropicKey = builtins.getEnv "ANTHROPIC_API_KEY";
in
{

  imports = [
    ./shell/shell.nix
  ];


  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  # Capped at 25.11 because the darwin configuration is pinned to home-manager
  # release-25.11 (see flake.nix nixpkgs-darwin pin / nixpkgs#507531). Lowering
  # the stateVersion is safe: it just keeps older Home Manager defaults active.
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.sessionVariables = {
    # Allow unfree packages
    # FIXME: I've tried setting the relevant options in flake.nix but not
    # working for me - hence the session variable workaround
    NIXPKGS_ALLOW_UNFREE = 1;
    # Doing this globally is undoubtedly a bad idea... but I'm lazy
    NIXPKGS_ALLOW_INSECURE = 1;
    # Persist env variables from initial config...
    NAME = "${name}";
    EMAIL = "${email}";
    GITLAB = "${gitlabHost}";
    # Using subscription access for now
    # OPENAI_API_KEY = "${openaiKey}";
    # ANTHROPIC_API_KEY = "${anthropicKey}";
  };

  home.shellAliases = {
    hmb = "home-manager build --flake '${flakePath}' --impure";
    hms = "home-manager switch --flake '${flakePath}' --impure";
    nob = "nixos-rebuild build --flake '${flakePath}' --impure";
    nos = "sudo nixos-rebuild switch --flake \"${dotRoot}#`cat /etc/hostname`\" --impure";
    # Constructing path manually here -- sudo -E doesn't inherit USER or HOME
    drs = "sudo -E darwin-rebuild switch --flake '/Users/cormacc/dotfiles#Cormacs-MacBook-Air' --impure";
  };


  # To setup direnv in a given folder...
  # 1. create a flake.nix in the folder
  # 2. create a .envrc with the content "use flake"
  # 3. run 'direnv allow' in the folder
  programs.direnv = {
    enable = true;
    # direnv implicitly enabled for fish -- trying to do so here results in error
    #cache the direnv environment -- faster rebuild
    nix-direnv.enable = true;
    #Additional content for .config/direnv/direnvrc
    #N.B. home-manager appends "source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc" to the provided content
    stdlib = (builtins.readFile ./shell/direnvrc);
  };

  #TODO: Is this valid without x / a wm?
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
    #TODO: Vaguely remember these relating to emacs/tramp.. reinstate as needed
    # controlMaster = "auto";
    # controlPath = "~/.ssh/master-%r@%h:%p";
    # serverAliveInterval = 15;
    enableDefaultConfig = false;
    # `matchBlocks` is the name HM release-25.11 (darwin pin) accepts;
    # HM unstable (linux) has renamed it to `settings` and emits a
    # deprecation warning here. Keep `matchBlocks` until the darwin pin
    # advances past the rename, then switch in one go.
    matchBlocks = {
      # Use personal rather than work key for OSS forges.
      "github.com" = {
        hostname = "github.com";
        addKeysToAgent = "yes";
        identityFile = "~/.ssh/id_ed25519_personal";
      };
      "gitlab.com" = {
        hostname = "gitlab.com";
        addKeysToAgent = "yes";
        identityFile = "~/.ssh/id_ed25519_personal";
      };
      # Personal Lightsail box hosting a self-hosted GitLab instance.
      gitlab = {
        hostname = "${gitlabHost}";
        port = 1022;
        user = "ec2-user";
        identityFile = "~/.ssh/LightsailDefaultKey-eu-west-1.pem";
      };
      # Old SSH default config.... TODO: RTFM and see what I should keep
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
      };
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user = {
        name = "${name}";
        # Default identity is the work/global $EMAIL. Repos under ~/dev/
        # (see includes below) swap in $EMAIL_OSS instead.
        email = "${email}";
      };
      core = {
        autocrlf = "input";
      };
    };
    # Scope a personal / OSS git identity to ~/dev/ repos. When
    # $EMAIL_OSS is unset it falls back to $EMAIL (see let-binding
    # above), making this a no-op rather than producing duplicate
    # config.
    includes = [
      {
        condition = "gitdir:~/dev/";
        contents.user.email = "${emailOss}";
      }
    ];
  };

  # We can only enable one of delta, diff-so-fancy and difftastic
  # programs.delta.enable = true;
  # Colorised diff output
  # programs.diff-so-fancy.enable = true;
  # Structural diff
  programs.difftastic.enable = true;
  # Automated changelog generation...
  programs.git-cliff.enable = true;

  home.file.".local/bin/syncup".source=./git/bin/syncup;

  # Set vim as default editor for shell use
  home.file.".editorconfig".source=./editors/doteditorconfig;

  programs.vim = {
    enable = true;
    defaultEditor = true;
  };
}
