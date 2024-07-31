{config, pkgs, ... }:

let
  sway-dotfiles-root = "${config.home.homeDirectory}/dotfiles/sway";
  commonSessionVariables = {
    #Use fish as default shell, but NOT login shell as not posix compliant
    TERMINAL = "foot -e /usr/bin/env fish";
    #N.B. Check that this overrides the foot-extra specified in some OS defaults (e.g. manjaro)
    #     foot is included in ncurses / makes interop easier, and foot-extra additions included in ncurses version since 2021-11-13
    TERM = "foot";

    #Prevents java UIs showing up as a gray window on i3 and sway...
    _JAVA_AWT_WM_NONREPARENTING = 1;
    #Ensure sway-exec can source executables installed by home-manager
    PATH = "${config.home.homeDirectory}/.nix-profile/bin:$PATH";
  };
in {
  #User environment
  home.sessionVariables = commonSessionVariables;
  #... and environment.d for gdm, kdm etc. that don't source user profile
  systemd.user.sessionVariables = commonSessionVariables;

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
    python3
    networkmanagerapplet
    helvum # Patch bay for pipewire audio
    # Wayland...
    # ... notifications
    swaynotificationcenter
    libnotify
    inotify-tools
    # ... screenshots
    sway-contrib.grimshot
    grim # screenshot functionality
    slurp # screenshot functionality
    swappy
    # ... clipboard
    wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
    cliphist
    # ... screen related etc.
    wluma
    brightnessctl
    wf-recorder
    # ... misc
    showmethekey # useful for identifying keycodes etc. for config
    # More sway-targeted....
    foot #terminal
    swaylock
    # wob # services.wob.enable below doesn't seem to install wob fo rsome reason...
    waybar
    rofi #launcher / dmenu replacement
    fuzzel #alternative dmenu replacement
    jq # json parsing -- used by various sway/waybar scripts
    swaybg #backgrounds
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
  # DEPRECATED: Using SwayNotificationCenter instead
#   services.mako = {
#     enable = true;
#     extraConfig = ''
# [mode=do-not-disturb]
# invisible=1
# '';
#   };

  # programs.swayr = {
  #   enable=true;
  #   systemd.enable = true;
  # };

  programs.fuzzel = {
    enable=true;
  };

  home.file."${config.xdg.configHome}/sway".source = config.lib.file.mkOutOfStoreSymlink "${sway-dotfiles-root}/config";

  # waybar - status bar
  # TODO: Look at yambar?
  home.file."${config.xdg.configHome}/waybar".source = config.lib.file.mkOutOfStoreSymlink "${sway-dotfiles-root}/waybar";

  # rofi - a dmenu replacement
  home.file."${config.xdg.configHome}/rofi".source = config.lib.file.mkOutOfStoreSymlink "${sway-dotfiles-root}/rofi";

  # foot - terminal
  home.file."${config.xdg.configHome}/foot/foot.ini".source = config.lib.file.mkOutOfStoreSymlink "${sway-dotfiles-root}/foot.ini";

  home.file."${config.xdg.configHome}/fontconfig/conf.d/51-monospace.conf".source = ./fontconfig.conf;

  # Terminfo not usually installed for foot, which sets TERM=foot or TERM=foot-extra
  home.shellAliases = {
    ssh = "TERM=linux ssh";
  };

}
