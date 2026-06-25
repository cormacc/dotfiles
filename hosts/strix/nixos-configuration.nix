{ config, pkgs, lib, ... }:

let
  lemonadePort = 13305;
  openWebUIPort = 8080;
  searxngPort = 8888;
  vanePort = 3001;
  vaneSearxngApiUrl = "http://host.docker.internal:${toString searxngPort}";
  openWebUIWebSearchBootstrap = pkgs.writeShellScript "open-webui-web-search-bootstrap" ''
    set -euo pipefail

    db=/var/lib/open-webui/data/webui.db
    if [ ! -e "$db" ]; then
      exit 0
    fi

    ${pkgs.python3}/bin/python3 - <<'PY'
import json
import sqlite3
from datetime import datetime
from pathlib import Path

DB = Path('/var/lib/open-webui/data/webui.db')
if not DB.exists():
    raise SystemExit(0)

with sqlite3.connect(DB) as conn:
    table = conn.execute(
        "select name from sqlite_master where type = 'table' and name = 'config'"
    ).fetchone()
    if table is None:
        raise SystemExit(0)

    row = conn.execute('select id, data from config order by id desc limit 1').fetchone()
    if row is None:
        raise SystemExit(0)

    config_id, raw_data = row
    data = json.loads(raw_data) if isinstance(raw_data, str) else (raw_data or {})
    search = data.setdefault('rag', {}).setdefault('web', {}).setdefault('search', {})
    search.update({
        'enable': True,
        'engine': 'searxng',
        'searxng_query_url': 'http://127.0.0.1:${toString searxngPort}/search?q=<query>',
    })

    conn.execute(
        'update config set data = ?, updated_at = ? where id = ?',
        (json.dumps(data), datetime.now().isoformat(sep=' '), config_id),
    )
    conn.commit()
PY
  '';
  vaneSearxngBootstrap = pkgs.writeShellScript "vane-searxng-bootstrap" ''
    set -euo pipefail

    config=/var/lib/vane/config.json
    if [ ! -e "$config" ]; then
      exit 0
    fi

    tmp=$(mktemp "$(dirname "$config")/.config.json.XXXXXX")
    trap 'rm -f "$tmp"' EXIT

    current=$(${pkgs.jq}/bin/jq -r '.search.searxngURL // ""' "$config")
    if [ "$current" = "$SEARXNG_API_URL" ]; then
      exit 0
    fi

    ${pkgs.jq}/bin/jq --arg url "$SEARXNG_API_URL" \
      '.search = (.search // {}) | .search.searxngURL = $url' \
      "$config" > "$tmp"
    cp "$tmp" "$config"
    echo "Updated Vane search.searxngURL to $SEARXNG_API_URL"
  '';
in
{
  # ---------------------------------------------------------------------------
  # Open WebUI: patch list-mode image-edit field name
  # ---------------------------------------------------------------------------
  # Open WebUI 0.9.5's chat-tool `edit_image` builds `EditImageForm(image=urls)`
  # with a *list*, which makes routers/images.py send the file part(s) under
  # the non-OpenAI field name `image[]`. Lemonade (and any strict OpenAI-compat
  # backend) ignores `image[]`, returns HTTP 400 with body
  # `{"error":{"message":"Missing 'image' field in request",...}}`, which Open
  # WebUI then re-raises to the chat UI as `400: [ERROR: Bad Request]`.
  #
  # OpenAI's spec is to send multiple images as repeated `image` parts, not
  # `image[]`. This overlay rewrites the single occurrence in routers/images.py
  # so the field name is `image` for both the single-string and list branches.
  # Drop this overlay once upstream Open WebUI ships an equivalent fix; track
  # the change via `grep -n 'image\[\]' .../routers/images.py` after each bump.
  nixpkgs.overlays = [
    (final: prev: {
      open-webui = prev.open-webui.overridePythonAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace backend/open_webui/routers/images.py \
            --replace-fail "'image[]'" "'image'"
        '';
      });
    })
  ];

  # ---------------------------------------------------------------------------
  # Bootloader
  # ---------------------------------------------------------------------------
  # Fresh NixOS install on a single 4TB SSD with no dual-boot, so systemd-boot
  # is the right pick (simpler than grub, no chainloading needed). If the box
  # ever dual-boots, switch to the grub block used in hosts/xps15.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";

  # ---------------------------------------------------------------------------
  # AMD AI / Lemonade (Strix Halo)
  # ---------------------------------------------------------------------------
  # Kernel >= 6.14 is satisfied by nixos-workstation.nix (linux_6_18).
  # `users.users.cormacc` already carries `video` and `render` groups via
  # nixos-base.nix, so the amd-npu module's group requirement is met.
  hardware.amd-npu = {
    enable = true;
    enableFastFlowLM = true;   # NPU (XDNA 2) inference runtime
    enableLemonade = true;     # OpenAI-compatible local AI server
    enableROCm = true;         # ROCm-backed llama.cpp / sd-cpp
    enableVulkan = true;       # Vulkan-backed llama.cpp / whisper.cpp
    enableImageGen = true;     # Decided 2026-05-19: accept ~1.5GB closure
                               # for sd-cpp image generation from day one.

    # iGPU-addressable memory (GTT) for large omni models. Strix Halo's iGPU
    # reaches unified RAM via GTT, not the tiny BIOS VRAM carveout (~512 MiB).
    # The TTM default caps GTT at ~half of RAM (~62.5 GiB on this 128 GB box),
    # too small to hold the LMX-Omni-52B-Halo planner (Qwen, 23.8 GB) AND the
    # image model (Flux-2-Klein-9B, 19 GB) at once with KV cache + sd-cpp
    # buffers, so image requests evicted the other components and failed.
    # 110 GiB leaves ~15 GiB for the CPU/system. The module emits this as the
    # `ttm pages_limit` modprobe option (ttm is a loadable module here).
    gpuMemory.ttmSizeGiB = 110;

    lemonade = {
      user = "cormacc";
      # Bind to all interfaces so coding harness clients on other LAN machines
      # can continue to use the raw OpenAI-compatible API directly. Open WebUI
      # is an additional chat frontend, not the only LAN-facing Lemonade path.
      host = "0.0.0.0";
      port = lemonadePort;
    };
  };

  # ---------------------------------------------------------------------------
  # sd-cpp (image generation) shared-library fix
  # ---------------------------------------------------------------------------
  # nix-amd-ai's `stable-diffusion-cpp-rocm` ships an `sd-server` binary with no
  # RUNPATH, and the amd-npu module's lemond `LD_LIBRARY_PATH` carries only
  # xrt + clr. So the ROCm image backend dies at launch with exit 127:
  #   sd-server: error while loading shared libraries: libatomic.so.1
  # (llama.cpp/whisper are unaffected: they resolve libs via their own RPATH.)
  # We re-assert the module's library path (xrt core + xdna driver plugin +
  # clr, mirroring its internal xrt-combined) and append gcc-libs
  # (libatomic.so.1, libstdc++, libgomp); lemond forwards this to the
  # sd-server child. Rebuilt from `pkgs` rather than the sibling env key to
  # avoid module-system infinite recursion. nix-ld does NOT help here: sd-server
  # is Nix-built and uses the Nix loader, not the /lib64 stub nix-ld intercepts.
  # Drop once nix-amd-ai rpaths sd-server or adds gcc-libs to its ldLibraryPath
  # (as of b304a013 its ldLibraryPath is still only xrt-combined + clr).
  systemd.services.lemond.environment.LD_LIBRARY_PATH = lib.mkForce (
    lib.concatStringsSep ":" [
      "${pkgs.xrt}/opt/xilinx/xrt/lib"
      "${pkgs.xrt-plugin-amdxdna}/opt/xilinx/xrt/lib"
      "${pkgs.rocmPackages.clr}/lib"
      "${pkgs.stdenv.cc.cc.lib}/lib"
    ]
  );

  # ---------------------------------------------------------------------------
  # WhisperServer runtime dir + kokoro nix-ld loader: now handled upstream.
  # ---------------------------------------------------------------------------
  # The lemond `RuntimeDirectory = "lemond"` (WhisperServer writable runtime
  # dir), `programs.nix-ld.enable`, and the lemond `NIX_LD`/`NIX_LD_LIBRARY_PATH`
  # env (so the kokoro TTS prebuilt ELF finds a real loader) were all merged
  # into nix-amd-ai by PR #38 ("lemond runtime dir + nix-ld loader for omni
  # backends") and are present from our pinned rev b304a013 onward, so the
  # local workarounds were removed here. The sd-server LD_LIBRARY_PATH gcc-libs
  # fix above is NOT yet upstream and is kept.

  # Keep the raw Lemonade API LAN-reachable for coding harness clients.
  # services.searx.openFirewall and services.open-webui.openFirewall add the
  # search API and chat UI ports separately.
  networking.firewall.allowedTCPPorts = [ lemonadePort vanePort ];

  # jq is used by the Vane systemd bootstrap to patch persisted JSON safely.
  environment.systemPackages = [ pkgs.jq ];

  # SearXNG refuses to start with its default "ultrasecretkey". Keep the actual
  # generated key out of git/the store while making first activation automatic.
  system.activationScripts.searx-secret-key = ''
    install -d -m 0750 -o searx -g searx /var/lib/searx
    if [ ! -s /var/lib/searx/searx.env ]; then
      umask 077
      printf 'SEARX_SECRET_KEY=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" > /var/lib/searx/searx.env
      chown searx:searx /var/lib/searx/searx.env
      chmod 0640 /var/lib/searx/searx.env
    fi
  '';

  # ---------------------------------------------------------------------------
  # Shared SearXNG search backend
  # ---------------------------------------------------------------------------
  # The current nixpkgs module is still named `services.searx`, even though the
  # package and settings are SearXNG. Keep the engine set intentionally small so
  # Open WebUI, Vane, and MCP clients get predictable JSON-capable results.
  services.searx = {
    enable = true;
    openFirewall = true;
    environmentFile = "/var/lib/searx/searx.env";

    settings = {
      use_default_settings.engines.keep_only = [
        "duckduckgo"
        "brave"
        "mojeek"
        "google"
        "wikipedia"
        "github"
        "wolframalpha"
      ];

      server = {
        bind_address = "0.0.0.0";
        port = searxngPort;
        secret_key = "$SEARX_SECRET_KEY";
      };

      search.formats = [ "html" "json" ];

      engines = [
        {
          name = "wolframalpha";
          engine = "wolframalpha_noapi";
          shortcut = "wa";
          disabled = false;
        }
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Open WebUI chat frontend for Lemonade
  # ---------------------------------------------------------------------------
  services.open-webui = {
    enable = true;
    host = "0.0.0.0"; # Phase 1: direct LAN access; later Caddy can proxy localhost.
    port = openWebUIPort;
    openFirewall = true;

    # Open WebUI persists these settings to its DB under /var/lib/open-webui
    # after first start. The systemd ExecStartPre below reapplies web-search
    # settings to the persisted config so rebuilds stay declarative without
    # requiring admin-UI clicks. Re-include the module's telemetry-off defaults
    # here because setting this attr replaces the module default value rather
    # than merging.
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";

      ENABLE_OPENAI_API = "True";
      OPENAI_API_BASE_URL = "http://127.0.0.1:${toString lemonadePort}/v1";
      OPENAI_API_KEY = "sk-local-lemonade";
      ENABLE_OLLAMA_API = "False";

      ENABLE_WEB_SEARCH = "True";
      WEB_SEARCH_ENGINE = "searxng";
      SEARXNG_QUERY_URL = "http://127.0.0.1:${toString searxngPort}/search?q=<query>";

      # Phase 2: use Lemonade's OpenAI-compatible image endpoint before
      # introducing a separate ComfyUI service. Lemonade's own image-generation
      # example uses SD-Turbo at 512x512 with 4 steps and low CFG; Open WebUI
      # reads the extra OpenAI-compatible image params from IMAGES_OPENAI_PARAMS.
      ENABLE_IMAGE_GENERATION = "True";
      IMAGE_GENERATION_ENGINE = "openai";
      IMAGE_GENERATION_MODEL = "SDXL-Turbo";
      IMAGE_SIZE = "512x512";
      IMAGES_OPENAI_API_BASE_URL = "http://127.0.0.1:${toString lemonadePort}/v1";
      IMAGES_OPENAI_API_KEY = "sk-local-lemonade";
      IMAGES_OPENAI_PARAMS = builtins.toJSON {
        steps = 4;
        cfg_scale = 1.0;
      };
    };
  };

  # Lemonade's systemd unit is named `lemond` by nix-amd-ai. Open WebUI can
  # still start if Lemonade is down, but ordering it after the backend avoids a
  # first-load race on normal boots.
  systemd.services.open-webui = {
    after = [ "lemond.service" ];
    wants = [ "lemond.service" ];
    serviceConfig.ExecStartPre = openWebUIWebSearchBootstrap;
  };

  # ---------------------------------------------------------------------------
  # Vane answer engine frontend
  # ---------------------------------------------------------------------------
  # Upstream ships Docker images only. Use the slim image so this instance shares
  # strix's declarative SearXNG service instead of running a bundled copy.
  virtualisation.oci-containers = {
    backend = "docker";

    containers.vane = {
      image = "itzcrazykns1337/vane:slim-v1.12.2";
      ports = [ "0.0.0.0:${toString vanePort}:3000" ];
      environment = {
        SEARXNG_API_URL = vaneSearxngApiUrl;
        LEMONADE_BASE_URL = "http://host.docker.internal:${toString lemonadePort}/v1";
        LEMONADE_API_KEY = "sk-local-lemonade";
      };
      volumes = [ "/var/lib/vane:/home/vane/data" ];
      extraOptions = [ "--add-host=host.docker.internal:host-gateway" ];
    };
  };

  systemd.services.docker-vane = {
    after = [ "lemond.service" "searx.service" ];
    wants = [ "lemond.service" "searx.service" ];
    environment.SEARXNG_API_URL = vaneSearxngApiUrl;
    preStart = ''
      ${vaneSearxngBootstrap}
    '';
  };

  # ---------------------------------------------------------------------------
  # nix-amd-ai Cachix at the NixOS level
  # ---------------------------------------------------------------------------
  # `nixConfig.extra-substituters` in flake.nix covers flake evaluation
  # (already-trusted users); these settings cover post-activation nix
  # invocations on the running system, including fresh installs that
  # haven't seen the flake's nixConfig yet.
  nix.settings = {
    extra-substituters = [ "https://nix-amd-ai.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    ];
  };
}
