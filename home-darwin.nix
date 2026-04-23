{ config, pkgs, lib, specialArgs, ... }:

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
    ./home-core.nix
    # Include these at flake level instead?
    #./nmd/nmd.nix
    ./editors/editors.nix
    ./dev/dev.nix
    ./agents.nix
    #./desktop/office.nix
  ];

  # Google Chrome with remote debugging — required for the claude-usage pi extension.
  # Chrome is installed via homebrew cask in darwin-configuration.nix; we can't use
  # programs.chromium (which expects a nix-built package). Instead:
  #   - 'chrome' shell wrapper: launch from terminal with the debug port
  #   - ~/Applications/Chrome (Debug).app: pin to Dock for GUI launches
  home.packages = [
    (pkgs.writeShellScriptBin "chrome" ''
      exec '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
        --remote-debugging-port=9222 \
        --user-data-dir="$HOME/Library/Application Support/Google/Chrome" \
        "$@"
    '')
  ];

  home.activation.chromeDebugApp =
    let
      plist = pkgs.writeText "Chrome-Debug-Info.plist" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleExecutable</key><string>ChromeDebug</string>
          <key>CFBundleIdentifier</key><string>com.user.chrome-debug</string>
          <key>CFBundleName</key><string>Chrome (Debug)</string>
          <key>CFBundleDisplayName</key><string>Chrome (Debug)</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleVersion</key><string>1</string>
        </dict>
        </plist>
      '';
      script = pkgs.writeShellScript "ChromeDebug" ''
        exec '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
          --remote-debugging-port=9222 \
          --user-data-dir="$HOME/Library/Application Support/Google/Chrome" \
          "$@"
      '';
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      app="${config.home.homeDirectory}/Applications/Chrome (Debug).app"
      mkdir -p "$app/Contents/MacOS"
      cp ${plist} "$app/Contents/Info.plist"
      cp ${script} "$app/Contents/MacOS/ChromeDebug"
      chmod +x "$app/Contents/MacOS/ChromeDebug"
    '';

  services.syncthing = {
   enable = true;
  };
}
