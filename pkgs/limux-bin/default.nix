# Credit to whazor (https://github.com/whazor) for original implementation
# from https://github.com/am-will/limux/issues/75
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook4,
  addDriverRunpath,
  libglvnd,
  gtk4,
  libadwaita,
  webkitgtk_6_0,
  glib,
  pango,
  fontconfig,
  gcc,
}:

stdenv.mkDerivation rec {
  pname = "limux-bin";
  version = "0.1.19";

  src = fetchurl {
    url = "https://github.com/am-will/limux/releases/download/v${version}/limux-${version}-linux-x86_64.tar.gz";
    hash = "sha256-94/s5Iugdf3vbiwwVviGhVe5tSBnDi4Cbsib3yzeNNg=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook4
  ];

  buildInputs = [
    fontconfig
    gcc.cc.lib
    glib
    gtk4
    libadwaita
    libglvnd
    pango
    webkitgtk_6_0
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 limux "$out/bin/limux"
    install -Dm755 libexec/limux/limux-host "$out/libexec/limux/limux-host"
    install -Dm755 lib/libghostty.so "$out/lib/libghostty.so"
    cp -r share "$out/share"

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      # Force XWayland/GLX. limux is a prebuilt binary spliced into the Nix
      # closure (nixpkgs GTK4/libwayland/Mesa) on top of the system NVIDIA
      # driver; the native-Wayland EGL path mismatches and renders the
      # embedded ghostty surfaces blank. GLX via XWayland sidesteps libwayland.
      # --set-default so users on non-NVIDIA / Wayland-clean setups can override.
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
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
