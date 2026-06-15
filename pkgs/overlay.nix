# Local package overlay.
#
# Auto-exposes every package under ./pkgs/<name>/default.nix as
# `pkgs.<name>`, callPackage-wired against the final (overlaid) pkgs set.
# Drop a new `pkgs/<name>/default.nix` in and it appears automatically --
# no edits needed here or in flake.nix.
final: _prev:
let
  dir = ./.;
  entries = builtins.readDir dir;
  # A package is any subdirectory containing a default.nix.
  isPackage = name: type:
    type == "directory"
    && builtins.pathExists (dir + "/${name}/default.nix");
  names = builtins.filter (name: isPackage name entries.${name})
    (builtins.attrNames entries);
in
builtins.listToAttrs (map
  (name: {
    inherit name;
    value = final.callPackage (dir + "/${name}") { };
  })
  names)
