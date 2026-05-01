# macOS system configuration for Cormac's MacBook Air
# Applied via: sudo darwin-rebuild switch --flake '/Users/cormacc/dotfiles#Cormacs-MacBook-Air' --impure
# See https://nixcademy.com/posts/nix-on-macos/
{ self, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.vim ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Grant cormacc trusted-user status so that substituters declared in the
  # flake's nixConfig (and any extra-substituters passed on the CLI) are
  # actually used.  Without this the binary caches are silently ignored for
  # non-root users.
  nix.settings.trusted-users = [ "root" "cormacc" ];

  # Declare substituters and their signing keys at the system level so they
  # are written into /etc/nix/nix.conf and honoured unconditionally, rather
  # than relying on flake nixConfig (which requires the user to already be
  # trusted at evaluation time).
  nix.settings.substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://hyprland.cachix.org"
    "https://cache.numtide.com"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];

  # Enable alternative shell support in nix-darwin.
  programs.zsh.enable = true;
  programs.fish.enable = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  # Note: `nixpkgs.config.allowUnfree` is *not* set here because flake.nix
  # passes a pre-built `nixpkgs.pkgs` for the darwin pin (see
  # nixpkgs-darwin in flake.nix); allowUnfree is baked into that instance.
  nixpkgs = {
    hostPlatform = "aarch64-darwin";
  };

  # Fingerprint sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  system.primaryUser = "cormacc";

  users.users.cormacc = {
    name = "cormacc";
    home = "/Users/cormacc";
  };

  homebrew = {
    enable = true;
    brews = [
      "libtool"
      "libvterm"
    ];
    casks = [
      "emacs-app"
      "ghostty"
      "google-chrome"
      "ungoogled-chromium"
      "audacity"
      "reaper"
      "claude"
      "dash"
      "gimp"
      "libreoffice"
    ];
  };
}
