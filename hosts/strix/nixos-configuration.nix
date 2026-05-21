{ config, pkgs, lib, ... }:

let
  lemonadePort = 13305;
  openWebUIPort = 8080;
in
{
  # ---------------------------------------------------------------------------
  # Bootloader
  # ---------------------------------------------------------------------------
  # Fresh NixOS install on a single 4TB SSD with no dual-boot, so systemd-boot
  # is the right pick (simpler than grub, no chainloading needed). If the box
  # ever dual-boots, switch to the grub block used in hosts/xps15.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";

  # ---------------------------------------------------------------------------
  # AMD AI / Lemonade (Strix Halo)
  # ---------------------------------------------------------------------------
  # Kernel >= 6.14 is satisfied by nixos-workstation.nix (linux_6_18).
  # `users.users.cormacc` already carries `video` and `render` groups via
  # nixos-base.nix, so the amd-npu module's group requirement is met.
  hardware.amd-npu = {
    enable = true;
    enableFastFlowLM = true;   # NPU (XDNA 2) inference runtime
    enableLemonade = true;     # OpenAI-compatible local AI server
    enableROCm = true;         # ROCm-backed llama.cpp / sd-cpp
    enableVulkan = true;       # Vulkan-backed llama.cpp / whisper.cpp
    enableImageGen = true;     # Decided 2026-05-19: accept ~1.5GB closure
                               # for sd-cpp image generation from day one.

    lemonade = {
      user = "cormacc";
      # Bind to all interfaces so coding harness clients on other LAN machines
      # can continue to use the raw OpenAI-compatible API directly. Open WebUI
      # is an additional chat frontend, not the only LAN-facing Lemonade path.
      host = "0.0.0.0";
      port = lemonadePort;
    };
  };

  # Keep the raw Lemonade API LAN-reachable for coding harness clients.
  # services.open-webui.openFirewall below adds the chat UI port separately.
  networking.firewall.allowedTCPPorts = [ lemonadePort ];

  # ---------------------------------------------------------------------------
  # Open WebUI chat frontend for Lemonade
  # ---------------------------------------------------------------------------
  services.open-webui = {
    enable = true;
    host = "0.0.0.0"; # Phase 1: direct LAN access; later Caddy can proxy localhost.
    port = openWebUIPort;
    openFirewall = true;

    # Open WebUI persists these settings to its DB under /var/lib/open-webui
    # after first start; later declarative changes may need admin-UI updates or
    # a state reset. Re-include the module's telemetry-off defaults here because
    # setting this attr replaces the module default value rather than merging.
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";

      ENABLE_OPENAI_API = "True";
      OPENAI_API_BASE_URL = "http://127.0.0.1:${toString lemonadePort}/v1";
      OPENAI_API_KEY = "sk-local-lemonade";
      ENABLE_OLLAMA_API = "False";
    };
  };

  # Lemonade's systemd unit is named `lemond` by nix-amd-ai. Open WebUI can
  # still start if Lemonade is down, but ordering it after the backend avoids a
  # first-load race on normal boots.
  systemd.services.open-webui = {
    after = [ "lemond.service" ];
    wants = [ "lemond.service" ];
  };

  # ---------------------------------------------------------------------------
  # nix-amd-ai Cachix at the NixOS level
  # ---------------------------------------------------------------------------
  # `nixConfig.extra-substituters` in flake.nix covers flake evaluation
  # (already-trusted users); these settings cover post-activation nix
  # invocations on the running system, including fresh installs that
  # haven't seen the flake's nixConfig yet.
  nix.settings = {
    extra-substituters = [ "https://nix-amd-ai.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    ];
  };
}
