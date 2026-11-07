{ config, lib, pkgs, ... }:
let
  # ───────────────────────────── Source paths ─────────────────────────────
  dotRoot = "${config.home.homeDirectory}/dotfiles";

  # The dotagents repo is registered as a git submodule of this checkout
  # under `agents/`. Its working tree provides every reusable skill,
  # extension, prompt, the pi-side AGENTS.md, and the user-local
  # pi/settings.json (package list, default provider/model, secrets toggles)
  # and pi/mcp.json (native MCP servers).
  # Whole-directory symlinks below point ~/.agents/skills, ~/.claude/skills,
  # ~/.pi/agent/extensions, ~/.pi/agent/skills, ~/.pi/agent/agents,
  # ~/.pi/agent/prompts, ~/.pi/agent/AGENTS.md, and ~/.pi/agent/settings.json
  # at the live submodule path so edits reload in place via `/reload` without
  # a Home Manager switch.
  agentsRoot = "${dotRoot}/agents";
  piRoot = "${agentsRoot}/pi";
  piSettings = "${piRoot}/settings.json";
  piMcp = "${piRoot}/mcp.json";
  piModels = "${piRoot}/models.json";

  # ───────────────────────────── Dest paths ───────────────────────────────
  agentsConfig = "${config.home.homeDirectory}/.agents";
  claudeConfig = "${config.home.homeDirectory}/.claude";
  piConfig = "${config.home.homeDirectory}/.pi/agent";
  # The xdg.configHome stuff causes pain / erratic detection...
  # piConfig = "${config.xdg.configHome}/pi";
  npmCache = "${config.xdg.cacheHome}/npm";

  # Live-editable link into the dotfiles checkout.
  link = path: { source = config.lib.file.mkOutOfStoreSymlink path; };

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

    # Home Manager may accept identical foreign files or back them up. These
    # personal app paths must instead reject every foreign occupant.
    home.activation.checkHerdrAppLeaves =
      lib.hm.dag.entryBefore [ "writeBoundary" ] (''
        check_herdr_app_leaf() {
          local target="$1" source="$2" link_target resolved resolved_source
          if [ -e "$target" ] || [ -L "$target" ]; then
            link_target="$(${pkgs.coreutils}/bin/readlink "$target" || true)"
            case "$link_target" in
              ${builtins.storeDir}/*-home-manager-files/*)
                if [ -e "$source" ] &&
                   resolved="$(${pkgs.coreutils}/bin/readlink -f "$target")" && [ -n "$resolved" ] &&
                   resolved_source="$(${pkgs.coreutils}/bin/readlink -f "$source")" && [ -n "$resolved_source" ] &&
                   [ "$resolved" = "$resolved_source" ]; then return; fi ;;
            esac
            echo "ERROR: foreign Herdr app path: $target" >&2
            exit 1
          fi
        }
        check_herdr_app_leaf "${config.home.homeDirectory}/.config/herdr-app/mods/herdr-orch" "${agentsRoot}/herdr-app/mods/herdr-orch"
        check_herdr_app_leaf "${config.home.homeDirectory}/.config/herdr-app/mods/system" "${agentsRoot}/herdr-app/mods/system"
        check_herdr_app_leaf "${config.home.homeDirectory}/.config/herdr-app/mods/org-tasks" "${agentsRoot}/herdr-app/mods/org-tasks"
        check_herdr_app_leaf "${config.home.homeDirectory}/.config/herdr-app/layouts/herdr-orch.json" "${agentsRoot}/herdr-app/layouts/herdr-orch.json"
      '' + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
        # herdr-app writes a default keys.json whenever the file is missing,
        # so a plain file here is app-written: keep it aside with a timestamp.
        # A foreign symlink is still rejected.
        keys="${config.home.homeDirectory}/.config/herdr-app/keys.json"
        if [ -f "$keys" ] && [ ! -L "$keys" ]; then
          run mv "$keys" "$keys.pre-hm-$(date +%Y%m%d%H%M%S)"
          echo "Moved app-written $keys aside" >&2
        fi
        check_herdr_app_leaf "$keys" "${agentsRoot}/herdr-app/keys.darwin.json"
      '');

    # programs.herdr exposes settings, not editable plugin source leaves.
    home.activation.checkHerdrOrgTasksLeaf =
      lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        target="${config.home.homeDirectory}/.local/share/herdr-plugins/org-tasks"
        source="${agentsRoot}/herdr-plugin/org-tasks"
        if [ -e "$target" ] || [ -L "$target" ]; then
          link_target="$(${pkgs.coreutils}/bin/readlink "$target" || true)"
          owned=false
          case "$link_target" in
            ${builtins.storeDir}/*-home-manager-files/*)
              if [ -e "$source" ] &&
                 resolved="$(${pkgs.coreutils}/bin/readlink -f "$target")" && [ -n "$resolved" ] &&
                 resolved_source="$(${pkgs.coreutils}/bin/readlink -f "$source")" && [ -n "$resolved_source" ] &&
                 [ "$resolved" = "$resolved_source" ]; then owned=true; fi ;;
          esac
          if [ "$owned" != true ]; then
            echo "ERROR: foreign Herdr org-tasks path: $target" >&2
            exit 1
          fi
        fi
      '';

    # Herdr keeps plugin registration in its own registry, which no Home
    # Manager option manages; registering the leaf is a `herdr plugin link`
    # call. Register only when the id is absent, so a deliberate manual link
    # or unlink of another checkout is not replaced. Linking needs no running
    # server. Non-fatal: a failure warns rather than aborting activation.
    home.activation.registerHerdrOrgTasksPlugin =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        leaf="${config.home.homeDirectory}/.local/share/herdr-plugins/org-tasks"
        if [ -e "$leaf" ]; then
          if ! plugins="$(${pkgs.herdr}/bin/herdr plugin list 2>&1)"; then
            echo "WARNING: could not list Herdr plugins: $plugins" >&2
          elif ! printf '%s\n' "$plugins" | ${pkgs.gnugrep}/bin/grep -qF 'cormacc.org-tasks'; then
            if ! run ${pkgs.herdr}/bin/herdr plugin link "$leaf"; then
              echo "WARNING: could not register the Herdr org-tasks plugin." >&2
              echo "         Run: herdr plugin link $leaf" >&2
            fi
          fi
        fi
      '';

    # ─────────────── pi/settings.json git clean filter ────────────────
    # The tracked `agents/pi/settings.json` is live-linked into ~/.pi/agent,
    # and pi writes runtime state (lastChangelogVersion on upgrade, a
    # per-installation deviceId) back into it. dotagents marks the file
    # `filter=pi-settings` in .gitattributes and ships install-git-filter.sh
    # to register that filter, which strips those keys at stage time
    # (smudge = cat, so the working tree is untouched). defaultProvider and
    # defaultModel are tracked: pi saves them only on Ctrl+S in /model.
    #
    # The filter *definition* lives in the submodule's .git/config, which is
    # not version-controlled, so every fresh clone needs it registered once --
    # easy to forget, and forgetting it means dirty-tree noise every session.
    # Run the installer on every activation: it exits early when the filter is
    # current, so a changed field list reaches clones that already had the
    # filter. Non-fatal: a failure warns rather than aborting activation.
    home.activation.installPiSettingsGitFilter =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -f "${agentsRoot}/install-git-filter.sh" ]; then
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
    #
    # `--ignore-scripts` everywhere: no dependency needs an install-time script,
    # and it stops any package in the tree from running code at install time.
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
          (cd "$dir" && ${pkgs.nodejs}/bin/npm install --omit=dev --package-lock=false --ignore-scripts --no-audit --no-fund)
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
    # a necessary hypocrisy... nodejs itself comes from dev/dev.nix.
    programs.npm = {
      enable = true;
      package = null;
      settings.prefix = npmCache;
    };

    # Expose local npm globals plus the in-tree `ot` CLI shim. Third-party
    # installs should prefer bbin (`bbin install io.github.cormacc/dotagents
    # --as ot --latest-sha`), but this fallback keeps the pi extension and
    # local shell workflows working immediately from the editable submodule.
    home.sessionPath = [
      "${npmCache}/bin"
      "${agentsRoot}/skills/org-tasks/scripts"
    ];

    home.packages = with pkgs; [
      # Pi coding-agent (binary `pi`). nixpkgs builds each release tag with
      # its own derivation, so an upstream flake build failure does not hold
      # it back.
      pi-coding-agent
      claude-code
      codex
      herdr
      herdr-core
      herdr-desktop
      prettier
      # FIXME: Disabled - failing in nixpkgs 13/10/2026
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
      # Generic harness-agnostic skills (Agent Skills spec location).
      "${agentsConfig}/skills" = link "${agentsRoot}/skills";

      # Home-layer Herdr subagent overrides. Packaged personas and their default
      # config.edn still live below the linked skills tree at
      # herdr-orch/subagents/; this is the middle link of the resolution chain
      # (packaged < home < project), and is now managed rather than hand-authored
      # so the harness permission overrides in dotagents apply on every host.
      # Out-of-store, so edits in the submodule take effect without a switch.
      "${agentsConfig}/subagents" = link "${agentsRoot}/subagents";

      # Home layer of the trait-fragment store, the middle link of the same
      # project < home < packaged chain the subagents link above serves. The
      # packaged layer is a real directory beside the personas at
      # herdr-orch/traits/, so only the home layer needs projecting here.
      # Consumed by `oh` when composing a persona's inline %tokens, and by the
      # pi trait-expansion extension when that is built. Out-of-store, so edits
      # in the submodule take effect without a switch, matching skills and
      # subagents.
      "${agentsConfig}/traits" = link "${agentsRoot}/traits";

      # Claude Code discovery location for the same generic skills tree.
      # Claude Code hardcodes ~/.claude/skills (user scope) and
      # <project>/.claude/skills (project scope); there is no setting to point
      # it at ~/.agents/skills, so the tree needs its own link. Discovery is
      # depth-1 only (<root>/<name>/SKILL.md), which is what keeps
      # gitlab-cli-skills resident as a single entry while its 30+ glab-*
      # sub-skills stay on-demand -- the gradual-discovery behaviour the
      # sub-skill layout assumes. Out-of-store, matching ~/.agents/skills.
      # Claude Code writes its account skills to ~/.claude/skills/synced/, so
      # they land in the submodule; agents/skills/.gitignore keeps them out of
      # git and out of pi's discovery.
      "${claudeConfig}/skills" = link "${agentsRoot}/skills";

      # Claude Code's user-scope memory, giving claude the same portable rules
      # pi gets via ~/.pi/agent/AGENTS.md. It is a one-line `@` import rather
      # than a link straight to home/AGENTS.md so the file stays recognisably
      # CLAUDE.md at both ends. The import is written absolute (`~/dotfiles/...`)
      # deliberately: this file is reached through a symlink, and a relative
      # `@AGENTS.md` would resolve differently depending on whether Claude
      # resolves the link before taking the dirname. An absolute path is correct
      # either way, and assumes only the `dotRoot` this module already assumes.
      "${claudeConfig}/CLAUDE.md" = link "${agentsRoot}/home/CLAUDE.md";

      # Add the org-tasks cli tool shim to the path
      ".local/bin/ot" = link "${agentsRoot}/skills/org-tasks/scripts/ot";

      # Pi-side discovery locations. AGENTS.md comes from the submodule's
      # `home/` layer -- the portable, project-agnostic rules. The submodule's
      # *root* AGENTS.md is the dotagents project file (maintenance specifics
      # for that repo) and is deliberately not projected here; it is picked up
      # by ordinary cwd discovery when working inside the submodule.
      "${piConfig}/AGENTS.md" = link "${agentsRoot}/home/AGENTS.md";
      "${piConfig}/prompts" = link "${agentsRoot}/prompts";
      "${piConfig}/extensions" = link "${piRoot}/extensions";
      # Pi-specific skills (separate from generic ~/.agents/skills) typically
      # rely on specific pi extensions.
      "${piConfig}/skills" = link "${piRoot}/skills";

      "${piConfig}/settings.json" = link piSettings;

      # Native pi MCP server configuration (pi-only keys such as `oauth.callbackUrl`
      # and `description`), so it lives beside settings.json.
      "${piConfig}/mcp.json" = link piMcp;

      # Same for the model catalogue. Its `providers.<id>.modelOverrides` is
      # pi's topmost model layer, so it corrects extension-registered providers
      # (e.g. the lemonade plugin's hardcoded 4096 `maxTokens`) without
      # patching the extension.
      "${piConfig}/models.json" = link piModels;

      # Herdr config, including the herdr-orch quota status in `[ui] tab_bar_right`.
      # Only the file is linked: ~/.config/herdr/ also holds sockets, logs and
      # session state. Out-of-store, so Herdr can write the file (for example
      # `onboarding = false`) and edits apply after `herdr server reload-config`.
      # Not `programs.herdr.settings`: it writes a store copy (or, with
      # `mutableSettings`, merges into an untracked file), so the tracked file
      # would not be live-editable.
      "${config.home.homeDirectory}/.config/herdr/config.toml" = link "${agentsRoot}/herdr/config.toml";

      # registerHerdrOrgTasksPlugin links this leaf; it never replaces the registry.
      ".local/share/herdr-plugins/org-tasks" = link "${agentsRoot}/herdr-plugin/org-tasks";

      # Herdr desktop app (herdr-desktop) settings. `option_as_alt = "on"`
      # because its `auto` default sends Option as Alt only on US/ABC layouts;
      # on the Irish layout Option+T types a character, so Pi's `alt+t`
      # org-tasks shortcut never fires. Only the file is linked: the directory
      # also holds the app socket, state and caches. Out-of-store, so the app
      # can write its own settings and edits apply without a switch. No Home
      # Manager module exists for herdr-desktop.
      "${config.home.homeDirectory}/.config/herdr-app/settings.json" = link "${agentsRoot}/herdr-app/settings.json";

      # Link only personal leaves; bundled mods and layouts remain app-owned.
      "${config.home.homeDirectory}/.config/herdr-app/mods/herdr-orch" = link "${agentsRoot}/herdr-app/mods/herdr-orch";
      "${config.home.homeDirectory}/.config/herdr-app/mods/system" = link "${agentsRoot}/herdr-app/mods/system";
      "${config.home.homeDirectory}/.config/herdr-app/mods/org-tasks" = link "${agentsRoot}/herdr-app/mods/org-tasks";
      "${config.home.homeDirectory}/.config/herdr-app/layouts/herdr-orch.json" = link "${agentsRoot}/herdr-app/layouts/herdr-orch.json";
    } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      # Herdr desktop app key bindings. macOS only: the file uses `cmd-`
      # chords, and a Linux variant waits on a check of that platform's key
      # names. Out-of-store, so app writes land here for review.
      "${config.home.homeDirectory}/.config/herdr-app/keys.json" = link "${agentsRoot}/herdr-app/keys.darwin.json";
    };
  };
}
