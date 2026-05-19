# BOOTSTRAP_PLACEHOLDER
#
# This file is intentionally a placeholder. It is overwritten by the
# repo-root `./bootstrap.sh strix` script during fresh-install bootstrap,
# which copies the real `/etc/nixos/hardware-configuration.nix` generated
# by `nixos-generate-config` on the target machine into this path.
#
# `bootstrap.sh` greps for the literal token `BOOTSTRAP_PLACEHOLDER`
# above and refuses to run `nixos-rebuild` while it is present. The
# `throw` below ensures any *other* evaluation of `nixosConfigurations.strix`
# (e.g. `nix flake check --impure` on the dev machine) fails loudly with an
# actionable message instead of silently producing a broken closure.
#
# Until bootstrap.sh replaces this file:
#   - `nix flake check --impure` will fail on strix (only); other hosts
#     and homeConfigurations / darwinConfigurations remain unaffected.
#   - `nixos-rebuild ... .#strix` will refuse before reaching the build.
{ lib, ... }:

throw ''
  hosts/strix/hardware-configuration.nix is still the BOOTSTRAP_PLACEHOLDER.

  Run on the target machine after a fresh NixOS live-CD install:

      ./bootstrap.sh strix

  which will:
    1. Replace this file with the real
       /etc/nixos/hardware-configuration.nix produced by
       `nixos-generate-config`.
    2. Apply `sudo nixos-rebuild switch --flake .#strix --impure`.
    3. Apply `home-manager switch --flake .#default --impure -b backup`.
''
