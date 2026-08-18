# NVIDIA DGX Spark (GB10, aarch64-linux) -- local LLM inference workstation.
#
# This host is deliberately standalone: it imports the upstream
# graham33/nixos-dgx-spark module and nothing from nixos-base.nix /
# nixos-workstation.nix. Rationale: the upstream module sets
# `nixpkgs.config.cudaSupport = true` for the whole system, so every package
# the shared workstation profile adds (sway, hyprland, pipewire, docker,
# MooseFS, the embedded-dev toolchain) would be rebuilt from source on
# aarch64 with no cache. Staying close to the upstream template also removes
# the mkForce/platform-guard workarounds that a shared import needs.
#
# Shape follows upstream's tested install config
# (nixos-anywhere/configuration.nix) plus the local user and sshd.
{ config, lib, pkgs, inputs, ... }:

let
  vllmPort = 8000;
in
{
  # ---------------------------------------------------------------------------
  # DGX Spark hardware (NVIDIA GB10)
  # ---------------------------------------------------------------------------
  # The upstream module supplies: the NVIDIA 6.17 kernel with GB10 GPU and
  # Ethernet drivers, the nvidia-open driver, `nixpkgs.config.cudaSupport`,
  # the linux-6.17 overlay, podman + nvidia-container-toolkit, DGX Dashboard
  # on localhost:11000, fwupd, and the Flox CUDA cache as a substituter.
  #
  # `useNvidiaKernel` stays at its upstream default of true: the standard
  # 6.17 kernel has Ethernet problems on the Spark.
  hardware.dgx-spark.enable = true;

  # vLLM and the CUDA closure resolve from the dgx-spark nixpkgs pin (see
  # flake.nix), so this host also needs upstream's fixes overlay. It caps
  # vllm's CUTLASS targets at SM120 and MAX_JOBS at 8, without which the
  # build takes 16+ hours or OOM-kills itself on the Spark.
  nixpkgs.overlays = [ inputs.dgx-spark.overlays.fixes ];
  nixpkgs.config.allowUnfree = true;

  # ---------------------------------------------------------------------------
  # Boot
  # ---------------------------------------------------------------------------
  # Fresh single-boot NixOS install on the Spark's NVMe: systemd-boot (ARM64
  # EFI), matching the upstream template. If the box ever dual-boots with DGX
  # OS, switch to the grub block pattern used in hosts/xps15.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";

  # zram swap (upstream template choice): the GB10 has 128 GB of unified
  # LPDDR5x, so compressed RAM swap suits it better than a disk partition.
  zramSwap.enable = true;

  # ---------------------------------------------------------------------------
  # Identity, network, locale
  # ---------------------------------------------------------------------------
  networking.hostName = "spark"; # must match the flake attribute: `nos` builds .#$(cat /etc/hostname)
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
  console.keyMap = "ie";

  users.users.cormacc = {
    isNormalUser = true;
    description = "Cormac Cannon";
    extraGroups = [ "networkmanager" "wheel" "video" "render" "podman" "adm" "systemd-journal" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # Remote access. Key-only: this box is reached over the LAN, and its GPU is
  # the reason to reach it.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # ---------------------------------------------------------------------------
  # Nix
  # ---------------------------------------------------------------------------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" "cormacc" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  environment.systemPackages = with pkgs; [
    cachix
    curl
    git
    home-manager
    htop
    lshw
    pciutils
    usbutils
    vim
    wget
  ];
  environment.variables.EDITOR = "vim";

  # ---------------------------------------------------------------------------
  # vLLM inference server (OpenAI-compatible API)
  # ---------------------------------------------------------------------------
  # Serves the box's resident model on the port the homelab inventory checks
  # (openai-api on 8000). The upstream vLLM module creates one systemd unit
  # per instance, and instances declare mutual conflicts because they share
  # the single GB10 GPU. Add further models as new instances and start them
  # with `systemctl start vllm-<name>.service` rather than autoStart.
  services.vllm.instances.default = {
    # NVFP4 checkpoint: GB10 is Blackwell (SM121), which executes FP4
    # natively. vLLM reads the quantisation method from the checkpoint's
    # config.json, so no explicit --quantization argument is needed.
    model = "unsloth/Qwen3.8-27B-NVFP4";
    autoStart = true;
    port = vllmPort;
    # Unset upstream defaults, all correct for the Spark:
    #   host = "0.0.0.0"            LAN-reachable, like strix's Lemonade.
    #   gpuMemoryUtilization = 0.76 upstream's safe ceiling for unified RAM.
    #   maxModelLen = 65536
    #   enforceEager = true         required on GB10 (SM121) for some
    #                                quantization formats.
    # Set toolCallParser / reasoningParser once the model's chat template is
    # confirmed on the hardware.
  };

  # Keep the raw API LAN-reachable for coding harness clients (strix
  # pattern). DGX Dashboard (11000) stays localhost-only: no firewall port.
  networking.firewall.allowedTCPPorts = [ vllmPort ];

  # ---------------------------------------------------------------------------
  # State version
  # ---------------------------------------------------------------------------
  # Fresh install against nixpkgs 26.11. Upstream's template still says
  # 25.11; this value must be the release the system was first installed
  # from, so it tracks our pin rather than upstream's text.
  system.stateVersion = "26.11";
}
