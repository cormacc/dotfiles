{config, pkgs, ... }:

let
  sway-dotfiles-root = "${config.home.homeDirectory}/dotfiles/sway";
in {


  # The following packages have home-manager modules, but convenient to
  # install directly and link their config files using mkOutOfStoreSymlink
  # - waybar
  # - foot
  home.packages = with pkgs; [
    inotify-tools
    foot #terminal
    swaylock
    # wob # services.wob.enable below doesn't seem to install wob fo rsome reason...
    waybar
    rofi #launcher / dmenu replacement
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk
    gnome.adwaita-icon-theme
    font-awesome
    python3
    jq # json parsing -- used by various sway/waybar scripts
    swaybg #backgrounds
    grim # screenshot functionality
    slurp # screenshot functionality
    wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
    cliphist
    wluma
    brightnessctl
    wf-recorder
    networkmanagerapplet
    helvum # Patch bay for pipewire audio
  ];

  # Eliminates some annoying errors with waybar
  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 16;
  };

  #TODO: Investigate enabling via wayland.windowManager.sway.enable, rather than at NixOS level?
  #      This will work if set package = null, although then I'll need to import all the contents of config here...

  # wob - wayland overlay bars - for volume ctrl, brightness display
  # TODO: This socket is non-functional for some reason -- creating a pipe manually from sway applications config
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
  # TODO: Look at SwayNotificationCenter?
  services.mako = {
    enable = true;
    extraConfig = ''
[mode=do-not-disturb]
invisible=1
'';
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

  home.sessionVariables = {
    #Use fish as default shell, but NOT login shell as not posix compliant
    TERMINAL = "foot -e /usr/bin/env fish";
    #N.B. Check that this overrides the foot-extra specified in some OS defaults (e.g. manjaro)
    #     foot is included in ncurses / makes interop easier, and foot-extra additions included in ncurses version since 2021-11-13
    TERM = "foot";

    #Prevents java UIs showing up as a gray window on i3 and sway...
    _JAVA_AWT_WM_NONREPARENTING = 1;
  };
  # Terminfo not usually installed for foot, which sets TERM=foot or TERM=foot-extra
  home.shellAliases = {
    ssh = "TERM=linux ssh";
  };

}
