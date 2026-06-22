{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:

let
  inherit (stdenv.hostPlatform) system;

  platforms = {
    "x86_64-linux" = "linux-amd64";
    "aarch64-linux" = "linux-arm64";
    "aarch64-darwin" = "macos";
    "x86_64-darwin" = "macos";
  };

  shas = {
    "x86_64-linux" = "sha256-ePzZDpg+Pn2+Pw0ZIcwQJTweynuSwg3UvCo8G8oKmvU=";
    "aarch64-linux" = "sha256-uz+PCIePXZF6JNB25e84uKgcLW/PQuSpAl3HdKCB7kQ=";
    "aarch64-darwin" = "sha256-IX9WEFh0s4WKQlAdhMFdVaiFND2j9oUEYEbRtkWkH4Y=";
    "x86_64-darwin" = "sha256-IX9WEFh0s4WKQlAdhMFdVaiFND2j9oUEYEbRtkWkH4Y=";
  };

  platform = platforms.${system} or (throw "vendored quarto: unsupported platform ${system}");
  sha = shas.${system} or (throw "vendored quarto: no hash for ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "quarto";
  version = "1.9.37";

  src = fetchurl {
    url = "https://github.com/quarto-dev/quarto-cli/releases/download/v${finalAttrs.version}/quarto-${finalAttrs.version}-${platform}.tar.gz";
    hash = sha;
  };

  preUnpack = lib.optionalString stdenv.hostPlatform.isDarwin "mkdir ${finalAttrs.sourceRoot}";
  sourceRoot = lib.optionalString stdenv.hostPlatform.isDarwin "quarto-${finalAttrs.version}";
  unpackCmd = lib.optionalString stdenv.hostPlatform.isDarwin "tar xzf $curSrc --directory=$sourceRoot";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = stdenv.hostPlatform.isDarwin;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share
    mv bin/* $out/bin
    mv share/* $out/share
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$(mktemp -d)
    $out/bin/quarto --version | grep -q "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Vendored upstream Quarto CLI (bundled tools incl. pandoc 3.8.3 retained)";
    homepage = "https://quarto.org";
    license = lib.licenses.gpl2Plus;
    mainProgram = "quarto";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
