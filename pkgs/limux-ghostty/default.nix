{
  lib,
  stdenv,
  blueprint-compiler,
  bzip2,
  callPackage,
  fetchFromGitHub,
  fontconfig,
  freetype,
  glib,
  glslang,
  gst_all_1,
  gtk4-layer-shell,
  harfbuzz,
  libadwaita,
  libGL,
  libx11,
  libxml2,
  ncurses,
  oniguruma,
  pandoc,
  pkg-config,
  wrapGAppsHook4,
  zig_0_15,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "limux-ghostty";
  version = "0.1.19-ghostty-81ab8ffa90185221782baf785e85387321e16f8d";

  src = fetchFromGitHub {
    owner = "am-will";
    repo = "ghostty";
    rev = "81ab8ffa90185221782baf785e85387321e16f8d";
    hash = "sha256-JLUXIlOXQOTkDW449m0jGROMn2NmFXdMwt90LsgM64A=";
  };

  deps = callPackage ./deps.nix {
    name = "${finalAttrs.pname}-cache-${finalAttrs.version}";
  };

  strictDeps = true;

  nativeBuildInputs = [
    blueprint-compiler
    ncurses
    pandoc
    pkg-config
    zig_0_15
    glib
    wrapGAppsHook4
    libxml2
  ];

  buildInputs = [
    oniguruma
    libadwaita
    libx11
    gtk4-layer-shell
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-base
    glslang
    libGL
    bzip2
    fontconfig
    freetype
    harfbuzz
  ];

  dontConfigure = true;
  dontSetZigDefaultFlags = true;

  zigBaseFlags = lib.escapeShellArgs [
    "--system"
    "${finalAttrs.deps}"
    "-Dcpu=baseline"
    "-Doptimize=ReleaseFast"
  ];

  buildPhase = ''
    runHook preBuild

    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"

    zig build -Dapp-runtime=none ${finalAttrs.zigBaseFlags}
    DESTDIR="$TMPDIR/ghostty-install" zig build --prefix /usr ${finalAttrs.zigBaseFlags} -Demit-docs=false

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 zig-out/lib/libghostty.so "$out/lib/libghostty.so"
    cp -r "$TMPDIR/ghostty-install/usr/share" "$out/share"

    mkdir -p "$out/src"
    cp -r vendor "$out/src/vendor"

    runHook postInstall
  '';

  passthru = {
    inherit (finalAttrs) src deps;
  };

  meta = {
    description = "am-will Ghostty fork built for limux libghostty integration";
    homepage = "https://github.com/am-will/ghostty";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
