# Hardware configuration for the DGX Spark (NVIDIA GB10, aarch64-linux).
#
# Baseline from the graham33/nixos-dgx-spark template. On first install,
# regenerate a system-specific file and replace the placeholder UUIDs:
#   sudo nixos-generate-config --root /mnt --dir /tmp/nixos-config
#   blkid   # on the Spark, to read the real UUIDs
{ config, lib, pkgs, modulesPath, ... }:

let
  rootDevice = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
  bootDevice = "/dev/disk/by-uuid/XXXX-XXXX";
  isPlaceholder = dev: builtins.match ".*X{4,}.*" dev != null;
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Fail evaluation while the placeholder UUIDs are still in place. Without
  # this the host builds green and then cannot mount root on first boot.
  assertions = [
    {
      assertion = !(isPlaceholder rootDevice || isPlaceholder bootDevice);
      message = ''
        hosts/spark/hardware-configuration.nix still holds placeholder
        filesystem UUIDs. Read the real values on the Spark with `blkid`
        (or regenerate with `nixos-generate-config`) and replace rootDevice
        and bootDevice before you build this host.
      '';
    }
  ];

  boot.initrd.availableKernelModules = [
    "nvme" # NVMe storage
    "usb_storage" # USB storage support
    "usbhid" # USB input devices
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # REPLACE WITH YOUR ROOT FILESYSTEM UUID (see the assertion above)
  fileSystems."/" = {
    device = rootDevice;
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = bootDevice;
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # No on-disk swap: zramSwap (see nixos-configuration.nix) provides swap,
  # and a placeholder swap UUID here would fail first boot.

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
