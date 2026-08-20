{ config, lib, pkgs, ... }:
let
  # ───────────────────────────── Source paths ─────────────────────────────
  dotRoot = "${config.home.homeDirectory}/dotfiles";

  # The dotagents repo is registered as a git submodule of this checkout
  # under `agents/`. Its working tree provides every reusable skill,
  # extension, prompt, the pi-side AGENTS.md, and the user-local
  # pi/settings.json (package list, default provider/model, secrets toggles).
  # Whole-directory symlinks below point ~/.agents/skills, ~/.claude/skills,
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
  claudeConfig = "${config.home.homeDirectory}/.claude";
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

    # ─────────────── pi/settings.json git clean filter ────────────────
    # The tracked `agents/pi/settings.json` is live-linked into ~/.pi/agent,
    # and pi writes runtime state (lastChangelogVersion, defaultProvider,
    # defaultModel) back into it on every /model swap or upgrade. dotagents
    # marks the file `filter=pi-settings` in .gitattributes and ships
    # install-git-filter.sh to register that filter, which strips the volatile
    # keys at stage time (smudge = cat, so the working tree is untouched).
    #
    # The filter *definition* lives in the submodule's .git/config, which is
    # not version-controlled, so every fresh clone needs it registered once --
    # easy to forget, and forgetting it means dirty-tree noise every session.
    # Register it here, short-circuiting when already configured. Non-fatal:
    # a failure warns rather than aborting activation.
    home.activation.installPiSettingsGitFilter =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -f "${agentsRoot}/install-git-filter.sh" ] && \
           [ -z "$(${pkgs.git}/bin/git -C "${agentsRoot}" config --get filter.pi-settings.clean || true)" ]; then
          echo "Registering pi-settings git clean filter in ${agentsRoot}"
          # cd into the submodule: the script resolves its target from
          # `git rev-parse --show-toplevel`, and activation's cwd is $HOME.
          if ! (cd "${agentsRoot}" && \
                PATH="${pkgs.git}/bin:${pkgs.jq}/bin:$PATH" \
                ${pkgs.bash}/bin/bash ./install-git-filter.sh); then
            echo "WARNING: could not register the pi-settings clean filter." >&2
            echo "         Run ${agentsRoot}/install-git-filter.sh manually." >&2
          fi
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
      # This is installed for linux only -- installed via homebrew on darwin
      # hermes-agent
      herdr
      prettier
      typescript-language-server
      # Required on PATH at stage time by the `pi-settings` git clean filter
      # registered above (the filter command is `jq 'del(...)'`), which is
      # declared `required = true` and so fails the stage without it.
      jq
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

      # Home-layer Herdr subagent overrides. Packaged personas and their default
      # config.edn still live below the linked skills tree at
      # herdr-orch/subagents/; this is the middle link of the resolution chain
      # (packaged < home < project), and is now managed rather than hand-authored
      # so the harness permission overrides in dotagents apply on every host.
      # Out-of-store, so edits in the submodule take effect without a switch.
      "${agentsConfig}/subagents".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/subagents";

      # Home layer of the trait-fragment store, the middle link of the same
      # project < home < packaged chain the subagents link above serves. The
      # packaged layer is a real directory beside the personas at
      # herdr-orch/traits/, so only the home layer needs projecting here.
      # Consumed by `oh` when composing a persona's inline %tokens, and by the
      # pi trait-expansion extension when that is built. Out-of-store, so edits
      # in the submodule take effect without a switch, matching skills and
      # subagents.
      "${agentsConfig}/traits".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/traits";

      # Claude Code discovery location for the same generic skills tree.
      # Claude Code hardcodes ~/.claude/skills (user scope) and
      # <project>/.claude/skills (project scope); there is no setting to point
      # it at ~/.agents/skills, so the tree needs its own link. Discovery is
      # depth-1 only (<root>/<name>/SKILL.md), which is what keeps
      # gitlab-cli-skills resident as a single entry while its 30+ glab-*
      # sub-skills stay on-demand -- the gradual-discovery behaviour the
      # sub-skill layout assumes. Out-of-store, matching ~/.agents/skills.
      "${claudeConfig}/skills".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills";

      # Claude Code's user-scope memory, giving claude the same portable rules
      # pi gets via ~/.pi/agent/AGENTS.md. It is a one-line `@` import rather
      # than a link straight to home/AGENTS.md so the file stays recognisably
      # CLAUDE.md at both ends. The import is written absolute (`~/dotfiles/...`)
      # deliberately: this file is reached through a symlink, and a relative
      # `@AGENTS.md` would resolve differently depending on whether Claude
      # resolves the link before taking the dirname. An absolute path is correct
      # either way, and assumes only the `dotRoot` this module already assumes.
      "${claudeConfig}/CLAUDE.md".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/home/CLAUDE.md";

      # Add the org-tasks cli tool shim to the path
      ".local/bin/ot".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills/org-tasks/scripts/ot";

      # Generic MCP config
      "${config.xdg.configHome}/mcp/mcp.json".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/mcp.json";

      # Pi-side discovery locations. AGENTS.md comes from the submodule's
      # `home/` layer -- the portable, project-agnostic rules. The submodule's
      # *root* AGENTS.md is the dotagents project file (maintenance specifics
      # for that repo) and is deliberately not projected here; it is picked up
      # by ordinary cwd discovery when working inside the submodule.
      "${piConfig}/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/home/AGENTS.md";
      "${piConfig}/prompts".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/prompts";
      "${piConfig}/extensions".source =
        config.lib.file.mkOutOfStoreSymlink "${piRoot}/extensions";
      # Pi-specific skills (separate from generic ~/.agents/skills) typically
      # rely on specific pi extensions.
      "${piConfig}/skills".source =
        config.lib.file.mkOutOfStoreSymlink "${piRoot}/skills";

      # User-local pi settings come from dotfiles, not from the dotagents
      # submodule.
      "${piConfig}/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink piSettings;

      # Same for the model catalogue. Its `providers.<id>.modelOverrides` is
      # pi's topmost model layer, so it corrects extension-registered providers
      # (e.g. the lemonade plugin's hardcoded 4096 `maxTokens`) without
      # patching the extension.
      "${piConfig}/models.json".source =
        config.lib.file.mkOutOfStoreSymlink piModels;
    };
  };
}
