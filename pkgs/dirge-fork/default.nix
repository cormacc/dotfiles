{ lib, dirge }:

# dirge built from your fork, for PR development against upstream. Same build as
# pkgs.dirge, different source.
#
# Default source = the LOCAL worktree at ~/dev/agents/dirge. builtins.fetchGit
# on a local repo builds whatever commit is currently checked out on that branch
# (committed state only -- it ignores the working-tree dirt and, conveniently,
# the multi-GB target/ and .git). Switch branches in the worktree, commit, then
# rebuild to pick the new HEAD up.
#
# Always build with --impure (the repo norm; required here for the absolute path
# and the moving ref):
#
#   nix build .#dirge-fork --impure
#
# To build the PUSHED GitHub fork instead, comment out the local `src` and use
# the fetchGit block below (set `ref` to your PR branch).
#
# Not installed anywhere; its binary is still `dirge`, so it collides with
# pkgs.dirge in a shared profile.

let
  worktree = "${builtins.getEnv "HOME"}/dev/agents/dirge";

  # Local worktree, current branch HEAD:
  src = builtins.fetchGit { url = worktree; };

  # GitHub fork alternative:
  # src = builtins.fetchGit {
  #   url = "https://github.com/cormacc/dirge.git";
  #   ref = "oauth-anthropic";
  # };
in
(dirge.override {
  srcOverride = src;
  versionOverride = "0-fork-${builtins.substring 0 8 (src.rev or "dirty")}";
}).overrideAttrs
  (old: {
    meta = old.meta // {
      description = old.meta.description + " (cormacc fork / PR build)";
    };
  })
