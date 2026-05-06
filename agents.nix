{ config, lib, pkgs, ... }:
let
  # ───────────────────────────── Source paths ─────────────────────────────
  dotRoot = "${config.home.homeDirectory}/dotfiles";
  agentsRoot = "${dotRoot}/agents";
  piRoot = "${agentsRoot}/pi";

  # ───────────────────────────── Dest paths ───────────────────────────────
  agentsConfig = "${config.home.homeDirectory}/.agents";
  piConfig = "${config.home.homeDirectory}/.pi/agent";
  # The xdg.configHome stuff causes pain / erratic detection...
  # piConfig = "${config.xdg.configHome}/pi";
  npmCache = "${config.xdg.cacheHome}/npm";

  cfg = config.agents;

  # ──────────────────── Org-memory slice (single source of truth) ─────────
  # Read the package manifest so the Home Manager wiring and the pi
  # package always agree on which extensions and skills make up the
  # org-memory slice. Strip the manifest's leading "./" so paths are
  # usable as relative segments under the store output.
  manifest = lib.importJSON ./agents/package.json;
  stripDot = path: lib.removePrefix "./" path;
  basename = path: lib.last (lib.splitString "/" path);
  pkgExtensions = map stripDot manifest.pi.extensions;
  pkgSkills = map stripDot manifest.pi.skills;

  # Helper: given a list of slice paths under the store output, build a
  # set of `home.file` entries mapping each entry's basename under
  # `destRoot` to the corresponding store path.
  perEntrySymlinks = destRoot: paths:
    lib.listToAttrs (map (path: {
      name = "${destRoot}/${basename path}";
      value.source = "${cfg.package}/${path}";
    }) paths);
in
{
  options.agents = {
    mode = lib.mkOption {
      type = lib.types.enum [ "editable" "packaged" ];
      default = "editable";
      description = ''
        How org-memory and friends are installed into the user
        environment.

        - `editable`: whole-directory `mkOutOfStoreSymlink`s point
          `~/.agents/skills`, `~/.pi/agent/extensions`, and
          `~/.pi/agent/skills` at the live dotfiles checkout under
          `${dotRoot}/agents`. Installs the entire local agent suite
          (every skill and extension in the checkout), suitable for
          the dotfiles owner editing in place. Hot-reload (`/reload`)
          works without rebuilds.

        - `packaged`: per-entry symlinks from the `agents.package`
          Nix store output. Installs only the four packaged pi
          extensions (`tasks`, `jira`, `leader-menu`, `emacsclient`)
          and three packaged skills (`org-tasks`, `org-plan`,
          `org-jira`), leaving any other entries in the destination
          directories untouched. Suitable for collaborators who want
          a reproducible install of the org-memory slice without
          taking ownership of the destination directories.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./agents/agent-org-memory.nix { };
      defaultText = lib.literalExpression
        "pkgs.callPackage ./agents/agent-org-memory.nix { }";
      description = ''
        The `agent-org-memory` Nix package consumed by `packaged`
        mode. Override to install a specific version of the bundle
        (e.g. from another flake input).
      '';
    };
  };

  config = {
    # home.sessionVariables.PI_CODING_AGENT_DIR = "$piConfig";

    # npm's default global prefix points into the (read-only) Nix store when
    # node comes from nixpkgs. Redirect it to a writable location so
    # `pi install` works. This is philosophically unsound w.r.t. Nix, but
    # a necessary hypocrisy...
    #
    # Written as a raw ~/.npmrc rather than via `programs.npm` so this
    # module works on home-manager release-25.11 (used by darwin per
    # flake.nix) where `programs.npm` doesn't yet exist, *and* on
    # home-manager master.
    home.sessionPath = [ "${npmCache}/bin" ];

    home.packages = with pkgs; [
      #Pi + deps
      llm-agents.pi
      prettier
      typescript-language-server
      #Claude code + deps
      llm-agents.claude-code
      llm-agents.codex
      #Support
      # lmstudio
    ];

    home.file = lib.mkMerge [
      {
        ".npmrc".text = ''
          prefix=${npmCache}
        '';
      }
      # ─────────────────────── Editable mode (default) ─────────────────────
      # Whole-directory symlinks to the live checkout. Installs the full
      # local suite, not just the packaged slice. Used by the dotfiles
      # owner; pi auto-discovers everything under the convention
      # directories at runtime.
      (lib.mkIf (cfg.mode == "editable") {
        "${agentsConfig}/skills".source =
          config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills";
        "${piConfig}/AGENTS.md".source =
          config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/AGENTS.md";
        "${piConfig}/prompts".source =
          config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/prompts";
        "${piConfig}/settings.json".source =
          config.lib.file.mkOutOfStoreSymlink "${piRoot}/settings.json";
        "${piConfig}/extensions".source =
          config.lib.file.mkOutOfStoreSymlink "${piRoot}/extensions";
        # Pi-specific skills (separate from generic skills under
        # ~/.agents/skills) typically rely on specific pi extensions.
        "${piConfig}/skills".source =
          config.lib.file.mkOutOfStoreSymlink "${piRoot}/skills";
      })

      # ──────────────────────── Packaged mode ──────────────────────────────
      # Per-entry symlinks from the agent-org-memory store output. Only
      # the four packaged extensions land under ~/.pi/agent/extensions/
      # and only the three packaged skills land under
      # ~/.agents/skills/. The destination directories are NOT owned by
      # this module, so any other entries the user manages locally are
      # preserved.
      #
      # Helper modules under pi/extensions/lib/ are also symlinked as a
      # sibling: pi's extension loader resolves `../lib/…` against the
      # symlink path (not the realpath), so without a `lib` entry next
      # to each extension the relative imports fail at load time. The
      # `lib` directory contains no `index.ts` and no `package.json`,
      # so pi's loader skips it as a candidate extension.
      (lib.mkIf (cfg.mode == "packaged") (lib.mkMerge [
        (perEntrySymlinks "${agentsConfig}/skills" pkgSkills)
        (perEntrySymlinks "${piConfig}/extensions" pkgExtensions)
        {
          "${piConfig}/extensions/lib".source =
            "${cfg.package}/pi/extensions/lib";
        }
      ]))
    ];
  };
}
