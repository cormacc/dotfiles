# agent-org-memory

Org-mode task-memory protocol for agentic coding tools (pi, Claude Code,
OpenAI Codex, etc.) plus the pi-specific extensions that implement it.

The bundle lets agents maintain durable, file-backed task state across
sessions: `TASKS.org` indexes work, change-record files capture context
and plans, and the pi extensions automate ID/timestamp/status mechanics
so the format stays consistent.

## What's in the bundle

### Generic skills (`skills/`)

Harness-agnostic skills written to the [Agent Skills][skills] standard.
Land in `~/.agents/skills/` — the cross-tool location honoured by pi,
Claude Code, OpenAI Codex, and any other agent that follows the
spec. The bundle keeps these skills harness-agnostic deliberately so
the protocol layer can be reused by any agent, not just by users of
the pi extensions below.

| Skill        | Purpose                                                                 |
|--------------|-------------------------------------------------------------------------|
| `org-tasks`  | Core task-memory protocol: file format, statuses, IDs, archive layout.  |
| `org-plan`   | Change-record structure (`* Context` / `* Plan` / `* Implementation`).  |
| `org-jira`   | Jira-specific authoring conventions layered on top of `org-tasks`.      |

### Pi extensions (`pi/extensions/`)

Loadable extensions for [pi-coding-agent][pi]. Land in
`~/.pi/agent/extensions/` — pi's own discovery location, distinct
from the generic `~/.agents/skills/` so that pi-only behaviour is
clearly scoped to pi and other agents don't accidentally try to load
TypeScript modules they can't execute.

| Extension     | Purpose                                                              |
|---------------|----------------------------------------------------------------------|
| `tasks`       | Implements the task-memory protocol: edit/insert/lifecycle helpers, status overlay, doctor checks. |
| `jira`        | Atlassian MCP integration: clone/claim/comment/transition flows for Jira-linked tasks. |
| `leader-menu` | Leader-key dispatcher (`/`-prefixed commands) used by the other extensions. |
| `emacsclient` | Emacs server bridge used by `tasks` for in-place file edits.         |

### Helper modules (`pi/extensions/lib/`)

`pi-utils.ts`, `editor.ts`, `wm.ts`. Imported by the four extensions
above via `../lib/…` relative paths. The directory is *not* loaded
as an extension because it contains no `index.ts`, `index.js`, or
`package.json` with a `pi` field — pi's loader skips it.

When the bundle is installed via Home Manager packaged mode, `lib/`
is symlinked next to the four extensions under
`~/.pi/agent/extensions/lib` so that the relative imports resolve
from the symlink path. The pi-package install routes (`npm:`,
`git:`, local-path via `pi install`) ship `lib/` inside the package
tree itself, so no extra wiring is required there.

## Install

> The bundle declares its resources in `package.json` under the `pi`
> key. Pi loads exactly the four extensions and three skills listed
> above; nothing else in the directory is exposed.

### As a pi package

```bash
# From npm (when published)
pi install npm:@cormacc/agent-org-memory

# From git
pi install git:github.com/cormacc/dotfiles
# or, after extraction to a dedicated repo:
pi install git:github.com/cormacc/agent-org-memory

# From a local checkout / Nix store path
pi install /path/to/agent-org-memory
```

`pi install` writes the entry to `~/.pi/agent/settings.json` (or
`.pi/settings.json` with `-l`) so missing packages reinstall on
startup.

### Via Nix / Home Manager

The flake at `github:cormacc/dotfiles` exposes the bundle as a Nix
package (`packages.<system>.agent-org-memory`) and a Home Manager
module (`agents.nix`). Two modes are available:

- **Editable mode** — for the bundle author. Whole-directory
  `mkOutOfStoreSymlink`s point `~/.agents/skills`,
  `~/.pi/agent/extensions`, and `~/.pi/agent/skills` at the source
  checkout. The full local suite is installed, not just the
  org-memory slice. Hot reload (`/reload`) works without rebuilds.
- **Packaged mode** — for collaborators. Per-entry symlinks from the
  Nix store install only the eight org-memory resources (three
  skills + four extensions + the `lib` helper directory used for
  sibling-import resolution), leaving every other entry in the
  destination directories untouched.

See the dotfiles flake's `agents.nix` for the option schema.

#### Consuming from another Nix flake

Reference the package as a flake input and select packaged mode in
your Home Manager config:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agent-org-memory = {
      url = "github:cormacc/dotfiles";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, agent-org-memory, ... }: {
    homeConfigurations.you =
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { system = "x86_64-linux"; };
        modules = [
          ./home.nix
          # Use the packaged store output instead of the editable checkout.
          {
            agents.mode = "packaged";
            agents.package =
              agent-org-memory.packages.x86_64-linux.agent-org-memory;
          }
        ];
      };
  };
}
```

The module options `agents.mode` and `agents.package` are the only
knobs collaborators need to flip. `agents.mode = "editable"` (the
default) is reserved for consumers who *do* check the dotfiles repo
out under `~/dotfiles` and want full live-edit access — typically
only the bundle author.

## Filtering

Pi's package-filter syntax lets consumers narrow the slice further if
needed:

```json
{
  "packages": [
    {
      "source": "npm:@cormacc/agent-org-memory",
      "extensions": ["./pi/extensions/tasks", "./pi/extensions/leader-menu"],
      "skills": ["./skills/org-tasks"]
    }
  ]
}
```

Refer to the [pi packages docs][packages] for the full filter grammar.

## Why the directory split

The bundle deliberately keeps two install destinations rather than
dumping everything under one root:

- **`~/.agents/skills/`** is the cross-agent location defined by the
  [Agent Skills specification][skills]. Skills here are pure
  Markdown + assets and are loaded by pi, Claude Code, OpenAI Codex,
  and any other agent that follows the spec. The three packaged
  skills (`org-tasks`, `org-plan`, `org-jira`) intentionally describe
  the protocol in agent-neutral terms.
- **`~/.pi/agent/extensions/`** is pi's own discovery location for
  loadable TypeScript extensions. Code that calls into pi's
  `ExtensionAPI`, registers tools, or hooks events lives here
  because it has no meaning to other agents.

Keeping these separate means another agent can adopt the protocol
(via the skills) without inheriting pi-specific behaviour, and pi
users can swap out or extend the implementation without touching the
portable protocol layer.

## Extraction roadmap

This package currently lives inside the upstream
[`cormacc/dotfiles`][repo] repo under `agents/`. The boundary is
designed so a future move to a dedicated repo is mostly a
repository-level rename rather than a redesign:

- The `pi` manifest, peer-deps, and `files` whitelist already
  describe the slice independently of the surrounding dotfiles.
- The Nix package definition (`agent-org-memory.nix`) consumes only
  the slice via `lib.fileset`; it has no other dependencies on the
  dotfiles tree.
- The Home Manager module reads the slice membership from
  `package.json`, so adding/removing entries during or after
  extraction does not touch the consumer-facing module.

When the slice is extracted:

1. Move `agents/{package.json,README.md,pi/extensions/{tasks,jira,leader-menu,emacsclient,lib},skills/{org-tasks,org-plan,org-jira}}`
   into the root of the new repo.
2. Flatten `pi/extensions/…` to `extensions/…` and update the manifest
   paths (or keep the deeper layout if you prefer; the manifest is
   the only thing that has to agree).
3. Update the `repository.url` and `repository.directory` fields in
   `package.json`.
4. Replace `pi install git:github.com/cormacc/dotfiles` install
   examples with the dedicated-repo URL (already shown as the second
   form below).
5. Tag a release and re-point any consuming flakes' inputs.

No source code changes are needed in the extensions or skills
themselves.

## What the bundle does *not* ship

- **User settings.** `settings.json`, per-extension override files
  (`tasks-ext.json`, `jira-ext.json`, `leader-menu.json`), prompt
  templates, themes — compose those yourself in your own pi
  configuration.
- **Other skills/extensions** present in the upstream dotfiles
  (`chromium`, `webdriver`, `clj-nrepl`, `review`, etc.). They are
  intentionally out of scope for this package.
- **Tests.** Co-located `*.test.ts` and `test.sh` files exist in the
  upstream source tree but are excluded from the package output.

## Layout

```
agent-org-memory/
├── package.json
├── README.md
├── pi/
│   └── extensions/
│       ├── tasks/         # index.ts + sibling modules + README.md
│       ├── jira/          # index.ts + utils.ts + README.md
│       ├── leader-menu/   # index.ts + defaults.json + AGENTS.md + README.md
│       ├── emacsclient/   # index.ts + emacsclient.ts + elisp.ts + README.md
│       └── lib/
│           ├── pi-utils.ts
│           ├── editor.ts
│           └── wm.ts
└── skills/
    ├── org-tasks/SKILL.md
    ├── org-plan/SKILL.md
    └── org-jira/SKILL.md
```

## Runtime requirements

- **pi-coding-agent** (host runtime). Declared as a peer dependency;
  pi bundles the core packages itself.
- **Emacs** with a running server (`M-x server-start`) for the
  `emacsclient` extension's Elisp bridge. Used by `tasks` for
  in-place edits to org files.
- **Node 20+** (provided by pi's environment).

[pi]: https://github.com/mariozechner/pi-coding-agent
[skills]: https://agentskills.io/specification
[packages]: https://github.com/mariozechner/pi-coding-agent/blob/main/docs/packages.md
[repo]: https://github.com/cormacc/dotfiles
