{ config, pkgs, lib, ... }:

let
  lemonadePort = 13305;
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
      # Bind to all interfaces so other devices on the LAN can hit the
      # OpenAI-compatible API. Decided 2026-05-19: LAN-reachable. Pair
      # this with the explicit firewall hole below.
      host = "0.0.0.0";
      port = lemonadePort;
    };
  };

  # Open the Lemonade port explicitly rather than disabling the firewall.
  networking.firewall.allowedTCPPorts = [ lemonadePort ];

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
