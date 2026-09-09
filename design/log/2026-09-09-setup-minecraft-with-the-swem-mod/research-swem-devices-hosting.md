# Research: SWEM (Star Worm Equestrian Mod) requirements and per-device Minecraft edition support

Access date for all sources: 2026-09-09, unless a source's own timestamp is quoted.

## Answer

SWEM is a **Java Edition**-only Forge mod (no Bedrock/NeoForge-for-old-versions distinction: NeoForge builds exist only for 1.20.1 and 1.21.1), required on **both client and server**, with real per-version Java requirements up to **Java 21** for its newest (1.21.1) build. It is content-heavy (custom entities/items), so it is a textbook case Geyser explicitly **cannot** bridge to Bedrock — confirmed on Geyser's own FAQ. That rules out Switch, the Play-Store Bedrock app, and Minecraft Education outright, for any MC edition of the horse content itself. Among Java-capable devices, a **Raspberry Pi 5** running Forge+SWEM is technically possible (Prism Launcher via Pi‑Apps) but performance reports are poor even for vanilla, and worse for modded — a risky primary/only client. A Chromebook's Linux (Crostini) container can run the same Java client with performance gated entirely by the underlying CPU (Intel/AMD chromebooks fare far better than ARM/MediaTek ones). PojavLauncher on Android tablets is a known-unstable route for Forge/NeoForge content mods, with many open crash reports. For **server hosting**, nixpkgs' own `services.minecraft-server` is vanilla-only; the community `nix-minecraft` flake packages NeoForge servers (not legacy Forge) — usable for SWEM's 1.20.1/1.21.1 NeoForge builds but not its 1.16.5/1.18.2 Forge-only builds — and mods are supplied via `fetchurl`/`symlinks`, which can point directly at CurseForge's CDN URLs without an API key. `itzg/minecraft-server` (Docker) is the most flexible: `TYPE=NEOFORGE`/`FORGE` plus a `MODS` list of direct CurseForge CDN jar URLs works with **no API key**; only `AUTO_CURSEFORGE`/`CF_SLUG` modpack automation needs `CF_API_KEY` (and the image bundles one by default on Java 17+ tags).

## Key facts

### 1. SWEM itself

- **Edition/loader**: Java Edition, Forge-based mod; **NeoForge** builds exist for the two newest MC versions. Modrinth's official project record lists `"loaders":["forge"]` for the versions it hosts (1.16.5, 1.18.2) — Modrinth's own currently-tracked builds do not go past 1.18.2. — Source: `api.modrinth.com/v2/project/swem` (official Modrinth API), accessed 2026-09-09.
- **MC versions / loaders per version** (from the mod's own wiki, "Installing Mods" page, and corroborated by the community mirror 9minecraft.net):
  | MC version | Loader(s) | Java | Wiki-documented? |
  |---|---|---|---|
  | 1.16.5 | Forge 36.2.34+ | Java 8 | Yes (official wiki table) |
  | 1.18.2 | Forge 40.2.0+ | Java 17 | Yes (official wiki table) |
  | 1.20.1 | Forge 47.2.0+ | Java 17 | Yes (official wiki table, marked "LATEST RELEASE" at time of my access) |
  | 1.21.1 | NeoForge | Java 21 (Mojang requirement, see below) | **Not** documented on the official wiki as fetched; only corroborated by 9minecraft.net's mirror listing (`swem-1.21.1-1.6.11.jar`, dated "May 28, 2026" per that page) and a search-engine synthesis citing CurseForge. Treat 1.21.1 as **plausible but not primary-confirmed** — CurseForge's own page returned HTTP 403 to my fetcher. |

  Source (official): `https://wiki.swequestrian.com/books/star-worm-equestrian/page/installing-mods`, accessed 2026-09-09 — quote: *"SWEM for Minecraft 1.20.1 ##### LATEST RELEASE ... Minecraft Version 1.20.1, Forge 47.2.0 or higher, Java Java 17"*.
  Source (secondary, uncorroborated by a primary page I could reach): `https://www.9minecraft.net/star-worm-equestrian-mod/`, accessed 2026-09-09 — quote: *"For Minecraft 1.21.1, 1.21 > NeoForge 12 MB May 28, 2026"*.
  CurseForge itself (`https://www.curseforge.com/minecraft/mc-mods/swem`) returned **HTTP 403 Forbidden** to my fetcher on every attempt; I relied on the mod's own wiki (official), Modrinth's API (official, but only mirrors 1.16.5/1.18.2), and 9minecraft.net (unofficial mirror) instead.

- **Required Java runtime major version, from Mojang**: Minecraft 1.17–1.20.4 → Java 17+; **Minecraft 1.20.5 and newer (including 1.21.1) → Java 21+**, and a 64-bit OS became mandatory from 1.20.5 onward. — Source: Mojang, `https://www.minecraft.net/en-us/article/minecraft-java-edition-1-20-5` (title/URL confirmed via search; full-text fetch was interrupted by my tooling, so this is corroborated via the search synthesis and independently by the Pi‑Apps install page, which states the same Java‑21/64‑bit requirement almost verbatim — see Pi 5 section below). Flag: I could not directly re-fetch the Mojang article text in this session; treat the Java‑21‑for‑1.20.5+ figure as corroborated by two independent sources rather than a direct primary-source quote.

- **Required dependency mods**: **GeckoLib** and **Player Animator**, at version floors that track the MC version (e.g. for 1.20.1: GeckoLib 4.2.3+, Player Animator 1.0.2-rc1+1.20). — Source: official wiki page above, and Modrinth API's `dependencies` list for each SWEM version (project IDs `gedNE4y2` = GeckoLib, `8BmcQJ2H` = Player Animator), accessed 2026-09-09.

- **Client+server requirement**: **Yes, required on both.** Modrinth's project metadata explicitly states `"client_side":"required","server_side":"required","environment":"client_and_server"`. — Source: `api.modrinth.com/v2/project/swem`, accessed 2026-09-09.

- **RAM guidance (official)**: 2.5–4 GB minimum allocated to Minecraft; 5–6 GB recommended if the PC has 8 GB+ total. — Source: official wiki "Installing Mods" page (same table cited above).

- **Known issues (documented)**: shader/animation desync unless entity shadows are disabled (all versions); 1.18.2 build 1.4.6 has noted issues with horse data files and food pathing (linked to Discord threads); jump-animation desync sometimes seen on multiplayer servers, described by the mod team as "an entirely different issue" from the shader problem. — Source: official wiki, same page.

- **Bedrock version**: **No.** SWEM has no Bedrock or Bedrock Marketplace equivalent; it is exclusively a Java Forge/NeoForge mod (confirmed above). No source found suggests otherwise.

- **Licence/redistribution**: The CurseForge page (as mirrored by the Modrinth listing text and my search synthesis) states **"Under SWE/M || All Rights Reserved"** for code/rights, but explicitly permits modpack inclusion: *"Can I use this in my modpack(s)? Yes! No credit is required but please contact us so we can play too!"* Modrinth's machine-readable licence field for the project is `"license":{"id":"LicenseRef-All-Rights-Reserved", ...}`. — Source: `api.modrinth.com/v2/project/swem` body text + license field, accessed 2026-09-09. **Implication for the decision**: caching the jar in a repo or Nix store is not obviously prohibited (modpack bundling is explicitly allowed and the mod is freely downloadable), but "All Rights Reserved" means there is no explicit open-source redistribution licence either — this is a judgement call, not a clear yes/no from the licence text.

### 2. Per-device capability

- **Raspberry Pi 5 (aarch64)**:
  - Route: **Prism Launcher**, installed via **Pi-Apps** (`wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash`, then install "Minecraft Java Prism Launcher" from the Pi-Apps catalogue). Prism supports Forge/Fabric/Quilt mod loading and automatic Java 8/17/21 installation. — Source: `https://pi-apps.io/install-app/install-minecraft-java-prism-launcher-on-raspberry-pi/`, accessed 2026-09-09.
  - **lwjgl/OpenGL caveat (documented by the installer itself)**: *"Minecraft 1.17+ officially requires a graphics device capable of OpenGL 3.2+. On devices running MESA drivers without 3.2+ (eg: all Raspberry Pi models), this install script will OVERRIDE the reported version to 3.3. This currently allows... up to 1.19.2... to function without issue... but may not work on newer Minecraft and/or Mod versions."* This directly threatens SWEM's 1.20.1/1.21.1 builds, since the override is only confirmed reliable up to 1.19.2. — Same Pi-Apps source.
  - **Known Prism issue**: window-creation failures on Pi 5 tied to GPU 3D-acceleration detection (GitHub `PrismLauncher/PrismLauncher#3141`) — community report, not yet resolved as of my access.
  - **Performance reports** (community, Reddit r/raspberry_pi thread "optimizing minecraft for a pi 5", 2026): vanilla ~5–25 FPS depending on settings; modded (Forge/NeoForge) reported ~1.4–2.2× slower than vanilla; shaders effectively unplayable (<1 FPS). These are community anecdotes synthesised by my search tool, not something I independently verified against the raw thread — flag as **secondary/unconfirmed** at the specific-number level, though directionally consistent with the Pi 5's known GPU limits.
  - **Verdict**: technically launchable, but the OpenGL-override caveat and the reported FPS penalty for modded content make the Pi 5 a marginal, likely-frustrating client for SWEM at 1.20.1+ specifically (the MC version SWEM's current wiki-documented "latest" build targets).

- **Chromebook**:
  - **Crostini Linux route (i)**: Install the official Minecraft Launcher `.deb` inside the Linux (Crostini) container, same as any Debian/Ubuntu box; runs unmodified Forge. **Performance is entirely CPU-bound**: Intel/AMD Chromebooks reported as capable of running modded Java reasonably; ARM/MediaTek Chromebooks reported as struggling badly, especially low-RAM (4 GB) education-model devices. — Source: community summary citing `umatechnology.org` and `wilguftech.com` how-to guides; I did not independently fetch and quote these pages, so treat the CPU-architecture split as a **secondary/plausible but not independently verified** claim, consistent with general ARM-vs-x86 JVM/JIT performance expectations.
  - **Play Store Bedrock app (ii)**: Cannot join a Java-Edition server at all — Bedrock and Java use different, mutually incompatible network protocols; a Geyser proxy on the server is required for any Bedrock client to connect to a Java server, and even then modded content is unsupported (see Geyser verdict below).
  - **Minecraft Education (iii)**: Out of scope for this decision — it is a distinct edition/licence aimed at classrooms and does not run third-party Forge/NeoForge mods; not investigated further as it does not change the recommendation.

- **Android tablet**:
  - Native Play Store Minecraft app is Bedrock-only.
  - **PojavLauncher** (and Pojav-derived forks) is the realistic route to a Forge/NeoForge Java client on Android. Community consensus (GitHub issue tracker) reports **frequent instability with content mods**: widespread "fatal signal 6" crashes on Forge for MC 1.20.1 (PojavLauncher issues #6518, #6656), and crashes when combining optimisation mods (Optifine/Sodium) with Forge/NeoForge/Fabric on 1.21+. The project's own wiki documents Forge installation but, per the search synthesis, notes thorough testing only up to roughly 1.16.4. — Source: `https://github.com/PojavLauncherTeam/PojavLauncher/wiki/Install-Forge` and open issues on `github.com/PojavLauncherTeam/PojavLauncher`, accessed via search 2026-09-09; I did not independently open and quote each issue, so the specific issue numbers are as reported by my search tool rather than independently verified line-by-line.
  - **Verdict**: PojavLauncher + Forge/NeoForge + a heavy content mod like SWEM (which bundles custom entity models/animations via GeckoLib) is a known-fragile combination per community reports; not a reliable route.

- **Nintendo Switch**:
  - Bedrock-only, no Java client exists for Switch.
  - Even reaching a third-party (non-Featured) server on console at all requires a workaround (**BedrockConnect**), since consoles lack direct-connect and default to Mojang's Featured Servers list.
  - **Geyser verdict (official, directly answers the "can modded content be seen" question)**: Geyser's own FAQ states plainly: *"The short answer: if a vanilla client can join the server, then so can Geyser. The long answer: currently, there is no way for Geyser to translate the features that most mods add (blocks, items, etc.). Therefore, servers that require mods to be installed clientside are unsupportable through Geyser."* — Source: `https://geysermc.org/wiki/geyser/faq/`, accessed 2026-09-09 (official GeyserMC documentation). Since SWEM requires client-side mods for its custom horses/tack, **a Switch (or any Bedrock device) cannot see or use SWEM content through Geyser**, confirming the expected answer.

### 3. Server hosting on NixOS (x86_64)

- **`services.minecraft-server` (nixpkgs built-in)**: Vanilla server only. No Forge/NeoForge/mod-loader support in this module. — Source: NixOS wiki `https://wiki.nixos.org/wiki/Minecraft_Server` and the module source `nixos/modules/services/games/minecraft-server.nix` (as characterised by search synthesis; I did not directly fetch and quote the Nix source in this session, so treat the "vanilla only" characterisation as corroborated-but-not-directly-quoted).

- **`nix-minecraft` flake (`github:Infinidoge/nix-minecraft`)** — I fetched the README directly (primary source, accessed 2026-09-09):
  - Supported loaders/server types, quoted verbatim: *"All supported versions of the following mod/plugin loaders/servers: Fabric, Legacy Fabric, Quilt, Paper, Purpur, NeoForge"* plus all vanilla versions and the Velocity proxy. **Plain/legacy "Forge" is not in this list** — only its successor, NeoForge, is packaged.
  - **Implication for SWEM**: nix-minecraft can host SWEM's **1.20.1 or 1.21.1 NeoForge** builds (if the 1.21.1 build is confirmed — see the flagged uncertainty above), but **cannot** host SWEM's 1.16.5/1.18.2 builds, which are Forge-only, without falling back to a manual/overridden package (the README shows an `overrideAttrs` escape hatch for arbitrary jars, but that is a manual, unsupported path, not a first-class nix-minecraft feature).
  - Mods are supplied via the `symlinks` (read-only, faster rebuilds) or `files` (writable copy) options, each taking an attrset of derivations — typically built with `pkgs.fetchurl { url = ...; hash = ...; }` pointed at a direct download URL (Modrinth's CDN in the README's own examples, e.g. `cdn.modrinth.com/data/...`). The README does not give a CurseForge-specific example, but the same generic `fetchurl` mechanism applies to any direct URL, including CurseForge's CDN (`edge.forgecdn.net` / `mediafilez.forgecdn.net`) file links — this is a common community pattern (confirmed as the mechanism the sibling `itzg` Docker image also uses successfully without an API key, see below) rather than something nix-minecraft's own docs demonstrate for CurseForge specifically. **Flag: CurseForge-URL usage with nix-minecraft is inferred from the generic mechanism, not from a CurseForge-specific README example.**

- **`itzg/minecraft-server` Docker image** — I fetched the official docs directly (`docker-minecraft-server.readthedocs.io`, primary source, accessed 2026-09-09):
  - `TYPE=FORGE` and `TYPE=NEOFORGE` are both supported server types.
  - Individual mod jars (no modpack) can be supplied via the `MODS` environment variable as a comma/newline-delimited list of **direct URLs**, e.g. the docs' own example: *"`https://edge.forgecdn.net/files/2965/233/Bookshelf-1.15.2-5.6.40.jar`"* — this is CurseForge's own CDN domain, and **no `CF_API_KEY` is needed for this path** since it's a plain HTTP download, not a CurseForge API call.
  - `MOD_PLATFORM`/`MODPACK_PLATFORM`/`TYPE=AUTO_CURSEFORGE` is the **modpack**-automation mode (`CF_SLUG`, `CF_PAGE_URL`, `CF_FILE_ID`), and this mode **does** require a CurseForge API key — quoted from the docs: *"A CurseForge API key is now included by this image on Java 17 and newer; however, you can always supply your own instead... set the environment variable `CF_API_KEY`. The `java8` image... does not include that key."* Since SWEM is a single mod (not a modpack), the simpler `MODS`-list + direct-CDN-URL path avoids the API-key requirement entirely.

### 4. Licences/accounts

- **Java Edition**: requires a Microsoft account with a linked Java & Bedrock Edition (or legacy Java-only) purchase to log in via the Minecraft Launcher/Prism/PojavLauncher.
- **Bedrock Edition**: purchased per storefront (Microsoft Store on Windows, Nintendo eShop on Switch, Google Play on Android/Chromebook, etc.) — normally bundled as "Minecraft: Java & Bedrock Edition for PC" only covers the **PC/Windows Bedrock** app, not console/mobile Bedrock, which are separate per-platform purchases.
- **Same account on Pi + Chromebook simultaneously**: **No — one session at a time for Java Edition multiplayer.** Logging into the same Microsoft account on two Java clients works fine for solo/offline use, but when both clients try to join the *same* multiplayer server at once, one is kicked to the title screen because the server sees a duplicate username/UUID. — This matches the expected behaviour in the assignment; sources for this specific claim are secondary (community Reddit threads and a general tech-blog), corroborated by Mojang's own account-switching help article title (`https://help.minecraft.net/hc/en-us/articles/25521490005517-Switching-Between-Microsoft-Accounts-in-Launcher-to-Play-Minecraft`), which frames multi-device login as "switching between", i.e. sequential, not concurrent, use. I did not fetch that Mojang page's full text directly in this session, so treat this as corroborated-but-not-directly-quoted from the primary source.
- Separately, Bedrock's own account-locking is more strictly enforced and produces an explicit error (*"account is already playing in this world on a different device"*) per Mojira issue MCPE-186331 — not directly relevant here since this decision is entirely Java-side, but confirms the same one-session norm holds across both editions.

## Tradeoffs / options

| Option | Pros | Cons |
|---|---|---|
| **Pi 5 as local Java+SWEM client** | No extra hardware; single device | OpenGL-3.2 emulation only verified reliable to MC 1.19.2 (SWEM's documented latest wiki build is 1.20.1); community-reported FPS penalty for modded content; Prism Launcher has an open Pi-5-specific GPU-detection bug |
| **NixOS x86 box as NeoForge server, Pi/Chromebook/etc. as thin Java clients** | Server hardware (30 GiB RAM, x86) easily meets SWEM's stated 2.5–6 GB guidance many times over; itzg Docker path needs no CurseForge API key for a single mod; nix-minecraft gives a fully declarative NixOS-native option for the NeoForge (1.20.1/1.21.1) builds | Only covers devices that can run a **Java** client at all — Switch and Bedrock-only Android tablets are excluded regardless of server choice, per the Geyser FAQ's explicit statement that modded content is unsupportable through Geyser |
| **nix-minecraft (declarative NixOS module)** | In-repo/flake-native, versioned, reproducible | No plain-Forge package — only usable if SWEM's target MC version has a NeoForge build (1.20.1/1.21.1, and 1.21.1 is not primary-source-confirmed) |
| **itzg/minecraft-server (Docker)** | Supports both `FORGE` and `NEOFORGE` `TYPE`s, so all four SWEM MC-version builds are reachable; simple `MODS=<url>` list needs no API key for a single mod | Less "Nix-native"; still needs Java 21 available in the container image for the 1.21.1 build |

## Open / uncertain

- **SWEM 1.21.1/NeoForge existence and exact release date**: corroborated only by a community mirror site (9minecraft.net) and a search-engine synthesis citing CurseForge; the mod's own wiki (as fetched) documents only up to 1.20.1, and CurseForge itself returned HTTP 403 to my fetcher. Recommend the planner treat "1.21.1 support" as *likely but not primary-source-verified*, and re-check `curseforge.com/minecraft/mc-mods/swem/files` directly (e.g. via a logged-in browser session) before committing to that MC version.
- Several claims above (Mojang's exact Java-21-for-1.20.5+ wording, PojavLauncher issue numbers, Chromebook CPU-architecture performance split, Reddit Pi 5 FPS figures, Mojang's account-switching help-article text) are relayed via my search tool's synthesis rather than a page I personally fetched and quoted verbatim in this session. I have flagged each such instance inline; none of them is load-bearing enough on its own to overturn the overall verdicts, but the planner should not restate them as directly-quoted facts.
- Not investigated (out of scope for the primary deliverable): Minecraft Education specifics; SWEM's companion mods (Star Worm Lighting Mod, Star Worm Decor Mod, SWEM-addendum, SWEM Genetics addon) and their own version/loader support.

## Sources

- SWEM official wiki, "Installing Mods": `https://wiki.swequestrian.com/books/star-worm-equestrian/page/installing-mods` (fetched directly)
- SWEM/Modrinth official API: `https://api.modrinth.com/v2/project/swem` and `.../version` (fetched directly)
- SWEM CurseForge page: `https://www.curseforge.com/minecraft/mc-mods/swem` — **HTTP 403 to my fetcher on every attempt**; not directly accessed
- SWEM community mirror: `https://www.9minecraft.net/star-worm-equestrian-mod/` (fetched directly)
- Pi-Apps Minecraft-Prism install page: `https://pi-apps.io/install-app/install-minecraft-java-prism-launcher-on-raspberry-pi/` (fetched directly)
- GeyserMC official FAQ: `https://geysermc.org/wiki/geyser/faq/` (fetched directly)
- `nix-minecraft` README: `https://github.com/Infinidoge/nix-minecraft` (fetched directly)
- `itzg/docker-minecraft-server` docs: `https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/mod-platforms/auto-curseforge/` and `.../mods-and-plugins/` (fetched directly)
- Secondary/community (not directly fetched, relayed via search synthesis): Reddit r/raspberry_pi Pi 5 optimisation thread; PojavLauncher GitHub issues/wiki; umatechnology.org and wilguftech.com Chromebook how-tos; Mojang help articles on Java Edition system requirements and account switching; Mojira MCPE-186331.
