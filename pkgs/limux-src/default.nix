{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  wrapGAppsHook4,
  addDriverRunpath,
  libglvnd,
  limux-ghostty,
  fontconfig,
  gtk4,
  libadwaita,
  libepoxy,
  webkitgtk_6_0,
  glib,
  pango,
  pkg-config,
}:

rustPlatform.buildRustPackage rec {
  pname = "limux-src";
  version = "0.1.19";

  src = fetchFromGitHub {
    owner = "am-will";
    repo = "limux";
    tag = "v${version}";
    hash = "sha256-JIVwhVv49HllSYrUxmPkg/DNUn0lnDpuC/gw/pUBJwE=";
  };

  cargoHash = "sha256-CdGjtN3NYqVP3FBTSlpGOMaHOgzgpoSPusFh14n+HWc=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    fontconfig
    glib
    gtk4
    libadwaita
    libepoxy
    libglvnd
    pango
    webkitgtk_6_0
  ];

  postPatch = ''
    rm -f .cargo/config.toml

    cat > rust/limux-ghostty-sys/build.rs <<'EOF'
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let ghostty_root = manifest_dir.join("../../ghostty");
    let ghostty_lib = ghostty_root
        .join("zig-out/lib")
        .canonicalize()
        .expect("libghostty not found");

    let glad_src = ghostty_root.join("vendor/glad/src/gl.c");
    let glad_include = ghostty_root.join("vendor/glad/include");
    if glad_src.exists() {
        cc::Build::new()
            .file(&glad_src)
            .include(&glad_include)
            .compile("glad");
    }

    println!("cargo:rustc-link-search=native={}", ghostty_lib.display());
    println!("cargo:rustc-link-lib=dylib=ghostty");
    println!("cargo:rustc-link-lib=dylib=epoxy");
    println!("cargo:rustc-link-lib=static=glad");
    println!("cargo:rerun-if-changed={}", ghostty_lib.join("libghostty.so").display());
}
EOF

    mkdir -p ghostty/zig-out/lib ghostty/vendor
    ln -s ${limux-ghostty}/lib/libghostty.so ghostty/zig-out/lib/libghostty.so
    ln -s ${limux-ghostty}/src/vendor/glad ghostty/vendor/glad
  '';

  preBuild = ''
    export RUSTFLAGS="''${RUSTFLAGS:-} -C link-arg=$PWD/ghostty/vendor/glad/src/gl.c -C link-arg=-I$PWD/ghostty/vendor/glad/include"
  '';

  # Upstream tests expect GTK/WebKit/ghostty runtime resources and a graphical session.
  doCheck = false;

  installPhase = ''
    runHook preInstall

    install -Dm755 target/${stdenv.hostPlatform.rust.cargoShortTarget}/release/limux-cli "$out/bin/limux"
    install -Dm755 target/${stdenv.hostPlatform.rust.cargoShortTarget}/release/limux "$out/libexec/limux/limux-host"
    install -Dm755 ${limux-ghostty}/lib/libghostty.so "$out/lib/libghostty.so"

    mkdir -p "$out/share/limux/ghostty" "$out/share/limux/terminfo"
    cp -r ${limux-ghostty}/share/ghostty/. "$out/share/limux/ghostty/"
    if [ -d ${limux-ghostty}/share/terminfo/g ]; then
      mkdir -p "$out/share/limux/terminfo/g"
      cp ${limux-ghostty}/share/terminfo/g/ghostty "$out/share/limux/terminfo/g/ghostty"
    fi
    if [ -d ${limux-ghostty}/share/terminfo/x ]; then
      mkdir -p "$out/share/limux/terminfo/x"
      cp ${limux-ghostty}/share/terminfo/x/xterm-ghostty "$out/share/limux/terminfo/x/xterm-ghostty"
    fi

    install -Dm644 rust/limux-host-linux/dev.limux.linux.desktop "$out/share/applications/dev.limux.linux.desktop"
    install -Dm644 rust/limux-host-linux/dev.limux.linux.metainfo.xml "$out/share/metainfo/dev.limux.linux.metainfo.xml"
    for size in 16 32 128 256 512; do
      install -Dm644 "rust/limux-host-linux/icons/app/$size.png" "$out/share/icons/hicolor/''${size}x''${size}/apps/limux.png"
    done
    install -Dm644 rust/limux-host-linux/icons/limux-globe-symbolic.svg "$out/share/icons/hicolor/scalable/actions/limux-globe-symbolic.svg"
    install -Dm644 rust/limux-host-linux/icons/limux-split-horizontal-symbolic.svg "$out/share/icons/hicolor/scalable/actions/limux-split-horizontal-symbolic.svg"
    install -Dm644 rust/limux-host-linux/icons/limux-split-vertical-symbolic.svg "$out/share/icons/hicolor/scalable/actions/limux-split-vertical-symbolic.svg"

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      # Force XWayland/GLX. The from-source build hypothesis (one coherent
      # nixpkgs closure fixes native-Wayland EGL) did NOT hold on this host
      # (Sway + NVIDIA RTX 4070, driver 595): the embedded ghostty surface
      # renders but takes no keyboard input under native Wayland, and only
      # GDK_BACKEND=x11 restores it -- same workaround as the prebuilt limux. See the
      # ISC-9 fallback in the change-record. --set-default so non-NVIDIA /
      # Wayland-clean setups can override.
      --set-default GDK_BACKEND x11
      --prefix LD_LIBRARY_PATH : "$out/lib"
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd ]}"
      --prefix LD_LIBRARY_PATH : "${addDriverRunpath.driverLink}/lib"
      --prefix XDG_DATA_DIRS : "$out/share"
      --prefix TERMINFO_DIRS : "$out/share/limux/terminfo"
    )
  '';

  meta = {
    description = "GPU-accelerated terminal workspace manager for Linux";
    homepage = "https://github.com/am-will/limux";
    license = lib.licenses.mit;
    mainProgram = "limux";
    platforms = [ "x86_64-linux" ];
  };
}
