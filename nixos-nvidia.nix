{ config, lib, pkgs, ... }:
let
  cfg = config.dotfiles.nvidia;
in {
  # See https://nixos.wiki/wiki/Nvidia#CUDA
  #
  # Single Nvidia preset for both modern (Turing+) and legacy (pre-Turing)
  # GPUs. Set `dotfiles.nvidia.legacy = true;` on a host to switch to the
  # closed-source kernel module + `nvidiaPackages.latest` (last driver
  # series that still supports older cards).

  options.dotfiles.nvidia = {
    legacy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, configure the host for a pre-Turing GPU: closed-source
        kernel module (`hardware.nvidia.open = false`) and
        `nvidiaPackages.latest` (the last series that still ships
        legacy-card support). When false, use the open kernel module and
        the current beta driver, suitable for Turing and newer GPUs.
      '';
    };
  };

  config = {
    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {

      # Modesetting is required.
      modesetting.enable = true;

      # Nvidia power management. Experimental, and can cause sleep/suspend
      # to fail. Enable this if you have graphical corruption issues or
      # application crashes after waking up from sleep. This fixes it by
      # saving the entire VRAM memory to /tmp/ instead of just the bare
      # essentials.
      powerManagement.enable = false;

      # Fine-grained power management. Turns off GPU when not in use.
      # Experimental and only works on modern Nvidia GPUs (Turing or
      # newer).
      powerManagement.finegrained = false;

      # Use the NVidia open source kernel module (not to be confused with
      # the independent third-party "nouveau" open source driver). Support
      # is limited to the Turing and later architectures; legacy hosts
      # must keep the closed module. Full GPU compatibility list:
      # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
      open = !cfg.legacy;

      # Enable the Nvidia settings menu, accessible via `nvidia-settings`.
      nvidiaSettings = true;

      # Driver package selection:
      # - Modern: beta (Dec 25) pending fix for
      #   https://github.com/NixOS/nixpkgs/issues/467814
      # - Legacy: latest, which is the last driver series with support
      #   for pre-Turing cards.
      # Search nixpkgs for `linuxKernel.packages.linux_6_X.nvidia_x11` if
      # you need to pin a specific kernel/driver pairing.
      package =
        if cfg.legacy
        then config.boot.kernelPackages.nvidiaPackages.latest
        else config.boot.kernelPackages.nvidiaPackages.beta;
    };

    environment.systemPackages = with pkgs; [
      # Required during laptop hybrid graphics setup
      lshw
    ];

    # llm-related additions - per
    # https://gist.github.com/reklis/fb300e1b6c3549b1b2a82b891a8cc1b7
    # N.B. Unverified
    nixpkgs.config.cudaSupport = true;
    hardware.nvidia-container-toolkit.enable = true;
    virtualisation.docker.extraOptions =
      "--add-runtime nvidia=/run/current-system/sw/bin/nvidia-container-runtime";
  };
}
