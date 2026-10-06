{ config, lib, pkgs, ... }:

{
  # ... MBT IOD bootloader configuration
  home.file.".mutebutton".source=./.mutebutton;

  # OneDrive etc.
  # See https://github.com/abraunegg/onedrive
  home.packages = with pkgs; [
    #File sharing etc
    onedrive
    # Dropbox alternative -- use one or the other
    maestral
    maestral-gui
  ];
  home.file."${config.xdg.configHome}/onedrive/config".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/nmd/onedrive-config";
  #Manually link to systemd service, as home-manager not doing it for us here
  home.file."${config.xdg.configHome}/systemd/user/onedrive.service".source = "${pkgs.onedrive}/lib/systemd/user/onedrive.service";

  # Microsoft 365 MCP server (Softeria) for coding agents, in HTTP (OAuth) mode.
  # The ms365 skill launcher owns the server version, flags, and scope list;
  # this unit only supplies PATH and the Entra app identifiers (not secrets).
  # Clients connect to http://127.0.0.1:3365/mcp -- see agents/pi/mcp.json and
  # agents/skills/ms365/README.org. Non-Nix hosts use the skill's
  # assets/ms365-mcp.service instead.
  systemd.user.services.ms365-mcp = {
    Unit = {
      Description = "Microsoft 365 MCP server (read-only, loopback HTTP)";
      After = [ "network-online.target" ];
    };
    Service = {
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.nodejs pkgs.bash pkgs.coreutils ]}"
        "MS365_MCP_CLIENT_ID=1fa11897-1d66-4d5d-8dfa-6c623f386d04"
        "MS365_MCP_TENANT_ID=9797dc60-6d0f-4471-a18c-4e7b097913fc"
      ];
      # Live submodule path, like the `ot` shim in agents.nix.
      ExecStart = "${config.home.homeDirectory}/dotfiles/agents/skills/ms365/scripts/ms365-mcp";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Zephyr development config
  home.sessionVariables = {
    ZEPHYR_BASE="${config.home.homeDirectory}/dev/ncs/zephyr";
  };
}
