{config, pkgs, ... }:

let
  wayland-dotfiles-root = "${config.home.homeDirectory}/dotfiles/wayland";
  commonSessionVariables = {
    #Use fish as default shell, but NOT login shell as not posix compliant
    # FIXME: Bypassing for now, as nix profile not getting sourced under fish...
    #TERMINAL = "foot -e /usr/bin/env fish";
    #N.B. Check that this overrides the foot-extra specified in some OS defaults (e.g. manjaro)
    #     foot is included in ncurses / makes interop easier, and foot-extra additions included in ncurses version since 2021-11-13
    TERM = "foot";

    #Prevents java UIs showing up as a gray window on i3 and sway...
    _JAVA_AWT_WM_NONREPARENTING = 1;
    #Ensure sway-exec etc. can source executables installed by home-manager
    PATH = "${config.home.homeDirectory}/.nix-profile/bin:$PATH";
  };
in {
  #User environment
  home.sessionVariables = commonSessionVariables;
  #... and environment.d for gdm, kdm etc. that don't source user profile
  systemd.user.sessionVariables = commonSessionVariables;

  # N.B. Install the following packages at OS level
  # - sway
  # - waybar (as nix-installed variant has privilege issues with hyprland)
  # - python3 (as nix-installed variant breaks some aur packages on Arch linux)

  # The following packages have home-manager modules, but convenient to
  # install directly and link their config files using mkOutOfStoreSymlink
  # - waybar
  # - foot
  home.packages = with pkgs; [
    # Generic desktop enablement...
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk
    adwaita-icon-theme
    font-awesome

    networkmanagerapplet
    helvum # Patch bay for pipewire audio
    # Wayland...
    # ... notifications
    swaynotificationcenter # Usable on hyprland too
    libnotify
    inotify-tools
    # ... screenshots
    grim # screenshot functionality
    slurp # screenshot functionality
    swappy
    # ... clipboard
    wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
    # TODO: Hold off on flake updates until this commit gets deployed as latest nixpkgs:
    #       https://github.com/NixOS/nixpkgs/pull/348887
    # TODO: Review/rework sway config for 0.6.x -- existing config largely lifted from manjaro / overly complicated
    cliphist
    # ... screen related etc.
    wluma
    brightnessctl
    # Disabling 4/11/2024 -- build error
    # wf-recorder
    # ... misc
    showmethekey # useful for identifying keycodes etc. for config
    # More sway-targeted....
    foot #terminal
    # wob # services.wob.enable below doesn't seem to install wob fo rsome reason...
    #
    # waybar
    rofi #launcher / dmenu replacement
    fuzzel #alternative dmenu replacement
    jq # json parsing -- used by various sway/waybar scripts
    bc # gnu calculator -- used in some scripts

  ];

  # Eliminates some annoying errors with waybar
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 16;
  };

  # N.B. this requires blueman to be installed system-wide and service enabled by OS
  #      For NixOS, set 'services.blueman.enable = true;'
  #      For Arch, install blueman, then enable blueman-mechanism service
  services.blueman-applet.enable = true;

  # wob - wayland overlay bars - for volume ctrl, brightness display
  services.wob = {
    enable = true;
    systemd = true;
    settings = {
      "" = {
        anchor = "top center";
        margin = 20;
        border_color = "3498db";
        bar_color = "3498db";
        background_color = "14161b";
      };
    };
  };

  # wlsunset - dims screen at sunset
  services.wlsunset = {
    enable = true;
    latitude = 53;
    longitude = -9;
  };

  # mako  - a notification daemon for Wayland
  # DEPRECATED: Using SwayNotificationCenter instead for sway. And builtin for hyprland?
#   services.mako = {
#     enable = true;
#     extraConfig = ''
# [mode=do-not-disturb]
# invisible=1
# '';
#   };

  programs.fuzzel = {
    enable=true;
  };

  # rofi - a dmenu replacement
  home.file."${config.xdg.configHome}/rofi".source = config.lib.file.mkOutOfStoreSymlink "${wayland-dotfiles-root}/rofi";

  # foot - terminal
  home.file."${config.xdg.configHome}/foot/foot.ini".source = config.lib.file.mkOutOfStoreSymlink "${wayland-dotfiles-root}/foot.ini";

  home.file."${config.xdg.configHome}/fontconfig/conf.d/51-monospace.conf".source = ./fontconfig.conf;

  # Terminfo not usually installed for foot, which sets TERM=foot or TERM=foot-extra
  home.shellAliases = {
    ssh = "TERM=linux ssh";
  };

}
