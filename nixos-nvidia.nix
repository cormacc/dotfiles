{ config, lib, pkgs, ... }:
{

  # Enable OpenGL
  # ... on unstable
  hardware.graphics = {
    enable = true;
  };
  # ... on 24.05
  # hardware.opengl = {
  #   enable = true;
  #   # driSupport = true;
  #   # driSupport32Bit = true;
  # };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu,
	  # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    # Search nixpkgs for something like: linuxKernel.packages.linux_6_9.nvidia_x11
    # package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Stable package build failing against kernel 6.12 20/11/2024 - using beta as a dodge
    package = config.boot.kernelPackages.nvidiaPackages.beta;
    # package = linuxKernel.packages.linux_6_12.nvidia_x11

  };

  environment.systemPackages = with pkgs; [
    # Required during laptop hybrid graphics setup
    lshw
  ];

  # llm-related additions - per https://gist.github.com/reklis/fb300e1b6c3549b1b2a82b891a8cc1b7
  # N.B. Unverified
  nixpkgs.config.cudaSupport = true;
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.extraOptions = "--add-runtime nvidia=/run/current-system/sw/bin/nvidia-container-runtime";
}
