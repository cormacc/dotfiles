{ lib, dirge }:

# Bleeding-edge dirge: identical build to `pkgs.dirge`, but sourced from the
# latest commit on `main` instead of a pinned release tag. Tracking a moving
# branch is inherently impure, so `builtins.fetchGit` (no `rev`) fetches main's
# current HEAD at eval time -- always build with `--impure` (the repo norm).
#
#   nix build .#dirge-dev --impure
#
# Not installed anywhere by default; build/run on demand. (Its binary is still
# `dirge`, so it would collide with `pkgs.dirge` if both were in one profile.)

let
  src = builtins.fetchGit {
    url = "https://github.com/dirge-code/dirge.git";
    ref = "main";
  };
in
(dirge.override {
  srcOverride = src;
  versionOverride = "0-unstable-${builtins.substring 0 8 src.rev}";
}).overrideAttrs
  (old: {
    meta = old.meta // {
      description = old.meta.description + " (latest main)";
    };
  })
