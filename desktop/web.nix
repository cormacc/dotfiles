{config, pkgs, ... }:

{
  programs.chromium = {
    enable = true;
    # Chromium disables its own Vulkan backend on Linux by default; WebGPU
    # uses Vulkan through Dawn regardless of these flags.
    commandLineArgs = [
      "--remote-debugging-port=9222"
      "--enable-features=Vulkan,VulkanFromANGLE,DefaultANGLEVulkan"
      "--use-angle=vulkan"
    ];
    dictionaries = [ pkgs.hunspellDictsChromium.en-gb ];
    extensions = [
      # Bitwarden
      { id = "nngceckbapebfimnlniiiahkandclblb"; }
      # floccus bookmarks sync
      { id = "fnaicdffflnofjppbagibeoednhnbjhg"; }
      # Dataspex
      { id = "blgomkhaagnapapellmdfelmohbalneo"; }
      # Shadow-cljs UI
      { id = "hpcbebiekdogcnamniekdaknicncdban"; }
      # OPFS explorer
      { id = "acndjpgkpaclldomagafnognkcgjignd"; }
      # EPupp (webpage tampering with clojurescript)
      { id = "bfcbpnmgefiblppimmoncoflmcejdbei"; }
    ];
  };

  # Firefox have finally started to support webserial as of April 2026 / v151.0 nightlies
  # ... although nixpkgs hasn't caught up yet
  programs.firefox = {
    enable = true;
    # Keep explicit: HM wraps Firefox with this profile directory only when
    # configPath differs from its default (.config/mozilla/firefox).
    configPath = "${config.xdg.configHome}/mozilla/firefox";
  };

  home.packages = with pkgs; [
    google-chrome
  ];
}
