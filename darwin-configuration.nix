# macOS system configuration for Cormac's MacBook Air
# Applied via: sudo darwin-rebuild switch --flake '/Users/cormacc/dotfiles#Cormacs-MacBook-Air' --impure
# See https://nixcademy.com/posts/nix-on-macos/
{ self, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.vim ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Enable alternative shell support in nix-darwin.
  programs.zsh.enable = true;
  programs.fish.enable = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
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
      "kitty"
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
