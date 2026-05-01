{ config, lib, pkgs, ... }:

{
  programs.kitty = {
    enable = true;
    shellIntegration = {
      enableFishIntegration = true;
      enableZshIntegration = true;
    };
    settings = {
      confirm_os_window_close = 0;
      allow_remote_control = "socket-only";
      listen_on = "unix:/tmp/kitty-{kitty_pid}";
      enabled_layouts = "splits";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      # Make Option behave as Alt so chords like Alt+Esc reach TUIs (e.g. pi).
      macos_option_as_alt = "yes";
    };
  };

  home.packages = with pkgs; [
    nerd-fonts.roboto-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.inconsolata
    nerd-fonts.hack
    nerd-fonts.fira-code
    nerd-fonts.caskaydia-cove

    # Tools to help with nixpkg development...
    bundix

    # Serial terminal
    minicom

    # Compilers etc. for evaluating 3rd party repos without a flake...
    # ... js
    nodejs
    bun
    # ... rust
    #rust-bin.stable.latest.default
    cargo
    rustc

    # Misc tools
    libxml2
  ];

  imports = [
    ./clojure/clojure.nix
  ];
}
