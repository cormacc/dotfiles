# Shared list of nix substituters and trusted public keys.
#
# Single source of truth consumed by:
#   - flake.nix              (nixConfig.extra-substituters / extra-trusted-gpg-public-keys)
#   - nixos-base.nix         (nix.settings.substituters / trusted-public-keys)
#   - darwin-configuration.nix (nix.settings.substituters / trusted-public-keys)
#
# Host-specific caches (e.g. nix-amd-ai for strix) live in the host module
# and append via `extra-substituters` / `extra-trusted-public-keys` so they
# merge on top of this list rather than replacing it.
#
# IMPORTANT: nix.settings.{substituters,trusted-public-keys} REPLACE the
# defaults; nix.settings.{extra-substituters,extra-trusted-public-keys}
# MERGE. Use the replacing form here so the same list applies regardless
# of upstream default churn, and reserve the extra-* form for genuine
# host-local additions.
{
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://hyprland.cachix.org"
    "https://cache.numtide.com"
  ];

  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];
}
