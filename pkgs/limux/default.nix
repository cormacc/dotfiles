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
  pname = "limux";
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

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
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
