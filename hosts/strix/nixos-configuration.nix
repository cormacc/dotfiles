{ config, pkgs, lib, ... }:

let
  lemonadePort = 13305;
  openWebUIPort = 8080;
  searxngPort = 8888;
  vanePort = 3001;
  vaneSearxngApiUrl = "http://host.docker.internal:${toString searxngPort}";
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
  # AMD AI / Lemonade (Strix Halo)
  # ---------------------------------------------------------------------------
  # Kernel >= 6.14 is satisfied by nixos-workstation.nix (linuxPackages_latest).
  # `users.users.cormacc` already carries `video` and `render` groups via
  # nixos-base.nix, so the amd-npu module's group requirement is met.
  # FastFlowLM (NPU), Lemonade and sd-cpp image generation are on by default
  # upstream; only the non-default options are set here.
  hardware.amd-npu = {
    enable = true;
    gpuTarget = "gfx1151";   # Strix Halo (default is gfx1150 / Strix Point)
    enableROCm = true;         # ROCm-backed llama.cpp / sd-cpp
    enableVulkan = true;       # Vulkan-backed llama.cpp / whisper.cpp

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

      # No origin allowlist. lemond accepts requests with no Origin header
      # (CLI/SDK clients, and Open WebUI and Vane, which call it from their
      # backends), loopback origins, and same-origin requests from its own web
      # UI. An empty string clears the "*" that lemond migrated into
      # ~/.config/lemonade/config.json from the old LEMONADE_ALLOWED_ORIGINS
      # env var; the module's reconcile merges keys but never deletes them.
      # This makes the module emit a "allowedOrigins is empty" eval warning,
      # which is expected.
      settings.allowed_origins = "";
    };
  };

  # Keep the raw Lemonade API LAN-reachable for coding harness clients.
  # services.searx.openFirewall and services.open-webui.openFirewall add the
  # search API and chat UI ports separately.
  networking.firewall.allowedTCPPorts = [ lemonadePort vanePort ];

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
      # Engine set chosen by test from this network's public IP (2026-10-15).
      # brave ("too many requests"), google, qwant and privacywall ("access
      # denied"), startpage (CAPTCHA) and wolframalpha (timeout) returned no
      # results. duckduckgo works intermittently (CAPTCHA after a few rapid
      # queries). Retest after an IP change or a SearXNG bump.
      use_default_settings.engines.keep_only = [
        "bing"
        "duckduckgo"
        "mojeek"
        "yahoo"
        "yep"
        "wikipedia"
        "github"
      ];

      server = {
        bind_address = "0.0.0.0";
        port = searxngPort;
        secret_key = "$SEARX_SECRET_KEY";
      };

      search.formats = [ "html" "json" ];

      # Upstream defaults: bing, yahoo and yep are disabled; mojeek is
      # inactive (not loaded) because of its proof-of-work CAPTCHA, which
      # this IP does not get.
      engines = map (name: { inherit name; disabled = false; }) [ "bing" "yahoo" "yep" ]
        ++ [ { name = "mojeek"; inactive = false; } ];
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

    # ENABLE_PERSISTENT_CONFIG = False makes these environment values
    # authoritative on every start, instead of only seeding the DB under
    # /var/lib/open-webui on first start. Admin-UI changes to the same
    # settings do not survive a restart. Re-include the module's telemetry-off
    # defaults here because setting this attr replaces the module default
    # value rather than merging.
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";

      ENABLE_PERSISTENT_CONFIG = "False";

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
  # Keep this Linux-only cache out of the platform-neutral flake nixConfig.
  # These settings cover post-activation nix invocations on the running
  # system. Before the first activation, pass the cache and key explicitly
  # if they are not already configured in the build machine's nix.conf.
  nix.settings = {
    extra-substituters = [ "https://nix-amd-ai.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
    ];
  };
}
