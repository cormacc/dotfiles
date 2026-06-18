{ config, lib, pkgs, ... }:
let
  # ───────────────────────────── Source paths ─────────────────────────────
  dotRoot = "${config.home.homeDirectory}/dotfiles";

  # The dotagents repo is registered as a git submodule of this checkout
  # under `agents/`. Its working tree provides every reusable skill,
  # extension, prompt, the pi-side AGENTS.md, and the user-local
  # pi/settings.json (package list, default provider/model, secrets toggles).
  # Whole-directory symlinks below point ~/.agents/skills,
  # ~/.pi/agent/extensions, ~/.pi/agent/skills, ~/.pi/agent/agents,
  # ~/.pi/agent/prompts, ~/.pi/agent/AGENTS.md, and ~/.pi/agent/settings.json
  # at the live submodule path so edits reload in place via `/reload` without
  # a Home Manager switch.
  agentsRoot = "${dotRoot}/agents";
  piRoot = "${agentsRoot}/pi";
  piSettings = "${piRoot}/settings.json";
  piModels = "${piRoot}/models.json";

  # ───────────────────────────── Dest paths ───────────────────────────────
  agentsConfig = "${config.home.homeDirectory}/.agents";
  piConfig = "${config.home.homeDirectory}/.pi/agent";
  # The xdg.configHome stuff causes pain / erratic detection...
  # piConfig = "${config.xdg.configHome}/pi";
  npmCache = "${config.xdg.cacheHome}/npm";

in
{
  config = {
    # ────────────────────── Submodule sanity check ────────────────────────
    # Fail-fast at activation time if the dotagents submodule is not
    # initialised. The submodule provides every skill, extension, prompt,
    # and the pi-side AGENTS.md; silently activating against an empty
    # tree yields dangling symlinks under ~/.agents/skills and
    # ~/.pi/agent/* that confuse pi at runtime.
    #
    # Implemented as a `home.activation` script (pre `writeBoundary`)
    # rather than the `assertions` option because per-user assertions
    # are silently dropped under `darwinConfigurations`/`nixosConfigurations`
    # `home-manager.users.<user>` integration. The activation script
    # runs on every `home-manager switch` and `darwin-rebuild switch`.
    home.activation.checkDotagentsSubmodule =
      lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        if [ ! -f "${agentsRoot}/package.json" ]; then
          echo >&2
          echo "ERROR: dotagents git submodule under ${agentsRoot} is not initialised." >&2
          echo >&2
          echo "Run:" >&2
          echo "    git -C ${dotRoot} submodule update --init --recursive" >&2
          echo >&2
          echo "Or, on a fresh clone:" >&2
          echo "    git clone --recurse-submodules <dotfiles-url>" >&2
          echo >&2
          exit 1
        fi
      '';

    # home.sessionVariables.PI_CODING_AGENT_DIR = "$piConfig";

    # Local-only pi extensions such as chromium and pi-clojure live in the
    # editable dotagents checkout but are intentionally excluded from the
    # published agent-org-memory package. Pi still auto-discovers them from
    # ~/.pi/agent/extensions, so their npm runtime dependencies must exist in
    # the live checkout. Install them into ignored node_modules directories and
    # rerun only when the extension package.json changes.
    home.activation.installLocalPiExtensionDeps =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        install_local_pi_extension_deps() {
          local label="$1"
          local dir="$2"
          local package_json="$dir/package.json"
          local node_modules="$dir/node_modules"
          local stamp="$node_modules/.pi-local-deps-package-json.sha256"

          if [ ! -f "$package_json" ]; then
            echo "WARNING: local pi extension $label has no package.json at $package_json" >&2
            return 0
          fi

          local hash
          hash="$(${pkgs.coreutils}/bin/sha256sum "$package_json" | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)"
          if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$hash" ]; then
            return 0
          fi

          echo "Installing local pi extension npm deps for $label"
          (cd "$dir" && ${pkgs.nodejs}/bin/npm install --omit=dev --package-lock=false --no-audit --no-fund)
          mkdir -p "$node_modules"
          printf '%s\n' "$hash" > "$stamp"
        }

        install_local_pi_extension_deps chromium "${piRoot}/extensions/chromium"
        install_local_pi_extension_deps pi-clojure "${piRoot}/extensions/pi-clojure"
        install_local_pi_extension_deps dataspex "${piRoot}/extensions/dataspex"
      '';

    # npm's default global prefix points into the (read-only) Nix store when
    # node comes from nixpkgs. Redirect it to a writable location so
    # `pi install` works. This is philosophically unsound w.r.t. Nix, but
    # a necessary hypocrisy...
    #
    # Written as a raw ~/.npmrc rather than via `programs.npm` so this
    # module works on home-manager release-25.11 (used by darwin per
    # flake.nix) where `programs.npm` doesn't yet exist, *and* on
    # home-manager master.
    # Expose local npm globals plus the in-tree `ot` CLI shim. Third-party
    # installs should prefer bbin (`bbin install io.github.cormacc/dotagents
    # --as ot --latest-sha`), but this fallback keeps the pi extension and
    # local shell workflows working immediately from the editable submodule.
    home.sessionPath = [
      "${npmCache}/bin"
      "${agentsRoot}/skills/org-tasks/scripts"
    ];

    home.packages = with pkgs; [
      # Pi coding-agent. Provided by `pi.overlays.default` from the
      # `lukasl-dev/pi.nix` flake input (replaces the older
      # numtide/llm-agents.nix path which exposed `llm-agents.pi`).
      # N.B. We're intentionally not using the agents home-manager based config module
      #      for compatibility with our symlinking / live editable strategy for agent config
      pi-coding-agent
      claude-code
      codex
      herdr
      prettier
      typescript-language-server
      fswatch
      # Support
      # lmstudio
    ];

    home.shellAliases = {
      # Portable: avoid GNU-only `realpath --relative-to` (BSD realpath on macOS lacks it).
      # ${PWD#$HOME/} strips the $HOME/ prefix; tmux session names can't contain `.` or `:`.
      pit = ''tmux new -s "$(echo "''${PWD#$HOME/}" | tr ':.' '__')" -n "''${PWD#$HOME/}" pi'';
    };

    home.file = {
      ".npmrc".text = ''
        prefix=${npmCache}
      '';

      # Generic harness-agnostic skills (Agent Skills spec location).
      "${agentsConfig}/skills".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills";

      # Add the org-tasks cli tool shim to the path
      ".local/bin/ot".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills/org-tasks/scripts/ot";

      # Generic MCP config
      "${config.xdg.configHome}/mcp/mcp.json".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/mcp.json";

      # Pi-side discovery locations.
      "${piConfig}/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/AGENTS.md";
      "${piConfig}/prompts".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/prompts";
      "${piConfig}/extensions".source =
        config.lib.file.mkOutOfStoreSymlink "${piRoot}/extensions";
      # Pi-specific skills (separate from generic ~/.agents/skills) typically
      # rely on specific pi extensions.
      "${piConfig}/skills".source =
        config.lib.file.mkOutOfStoreSymlink "${piRoot}/skills";

      # Subagent definitions (pi-interactive-subagents). Overrides the
      # extension's bundled defaults: pi reads ~/.pi/agent/agents/<name>.md
      # ahead of any project-local .pi/agents/. Keeping our copies in the
      # dotagents submodule lets us tweak model/tool/skill defaults per agent
      # without re-publishing the upstream package.
      "${piConfig}/agents".source =
        config.lib.file.mkOutOfStoreSymlink "${piRoot}/agents";

      # User-local pi settings come from dotfiles, not from the dotagents
      # submodule.
      "${piConfig}/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink piSettings;
    };
  };
}
