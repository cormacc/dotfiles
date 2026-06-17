{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.7.5";
  sel = {
    "x86_64-linux" = {
      triple = "x86_64-unknown-linux-gnu";
      hash = "sha256-F97sX8+L0VvxJJI6NvMm2KfSQTapW+cGAcQ5h/czqzA=";
    };
    "aarch64-darwin" = {
      triple = "aarch64-apple-darwin";
      hash = "sha256-8bYD6nIEb8ezp5Xi7FznIksMF5DEmxM/HWmMtFUBw90=";
    };
  }.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "dirge-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/dirge-code/dirge/releases/download/v${version}/dirge-${sel.triple}.tar.gz";
    inherit (sel) hash;
  };

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib ];

  dontBuild = true;
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 dirge "$out/bin/dirge"

    runHook postInstall
  '';

  meta = {
    description = "Minimal, fast pure-Rust coding agent with persistent memory";
    homepage = "https://github.com/dirge-code/dirge";
    license = lib.licenses.gpl3Only;
    mainProgram = "dirge";
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
  };
}
