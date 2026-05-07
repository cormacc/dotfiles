{ config, lib, pkgs, ... }:
let
  # ───────────────────────────── Source paths ─────────────────────────────
  dotRoot = "${config.home.homeDirectory}/dotfiles";

  # The dotagents repo is registered as a git submodule of this checkout
  # under `agents-src/`. Its working tree provides every reusable skill,
  # extension, prompt, and the pi-side AGENTS.md. Whole-directory symlinks
  # below point ~/.agents/skills, ~/.pi/agent/extensions, ~/.pi/agent/skills,
  # and ~/.pi/agent/prompts at the live submodule path so edits reload in
  # place via `/reload` without a Home Manager switch.
  agentsRoot = "${dotRoot}/agents-src";
  piRoot = "${agentsRoot}/pi";

  # User-local pi configuration (package list, default provider/model,
  # secrets toggles) stays in dotfiles, *outside* the dotagents submodule.
  piSettings = "${dotRoot}/agents-config/pi/settings.json";

  # ───────────────────────────── Dest paths ───────────────────────────────
  agentsConfig = "${config.home.homeDirectory}/.agents";
  piConfig = "${config.home.homeDirectory}/.pi/agent";
  # The xdg.configHome stuff causes pain / erratic detection...
  # piConfig = "${config.xdg.configHome}/pi";
  npmCache = "${config.xdg.cacheHome}/npm";

  # ─────────────────────── Submodule sanity check ─────────────────────────
  # Fail-fast if the dotagents submodule is not initialised. The submodule
  # provides every skill, extension, prompt, and the pi-side AGENTS.md;
  # silently installing against an empty tree yields dangling symlinks
  # under ~/.agents/skills and ~/.pi/agent/* that confuse pi at runtime.
  #
  # Uses the absolute working-tree path (not a relative Nix path) because
  # nix flakes don't include git submodules in their evaluated source by
  # default. With `--impure` (already required by the rest of this flake)
  # `builtins.pathExists` peeks at the live filesystem.
  submoduleInitialised = builtins.pathExists "${agentsRoot}/package.json";
in
{
  config = {
    assertions = [
      {
        assertion = submoduleInitialised;
        message = ''
          The dotagents git submodule under `~/dotfiles/agents-src` is not
          initialised. Run:

              git -C ~/dotfiles submodule update --init --recursive

          Or, on a fresh clone:

              git clone --recurse-submodules <dotfiles-url>
        '';
      }
    ];

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
      # Pi + deps
      llm-agents.pi
      prettier
      typescript-language-server
      # Claude Code + Codex
      llm-agents.claude-code
      llm-agents.codex
      # Support
      # lmstudio
    ];

    home.file = {
      ".npmrc".text = ''
        prefix=${npmCache}
      '';

      # Generic harness-agnostic skills (Agent Skills spec location).
      "${agentsConfig}/skills".source =
        config.lib.file.mkOutOfStoreSymlink "${agentsRoot}/skills";

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

      # User-local pi settings come from dotfiles, not from the dotagents
      # submodule.
      "${piConfig}/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink piSettings;
    };
  };
}
