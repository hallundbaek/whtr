{ lib
, stdenvNoCC
, makeWrapper
, bash
, cacert
, coreutils
, curl
, gawk
, gnused
, imagemagick
, jq
, kitty
, ncurses
, tzdata
}:

stdenvNoCC.mkDerivation {
  pname = "whtr";
  version = "0.1.0";

  src = ./whtr.sh;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/whtr"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/whtr" \
      --prefix PATH : ${lib.makeBinPath [
        bash
        coreutils
        curl
        gawk
        gnused
        imagemagick
        jq
        kitty
        ncurses
      ]} \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --set TZDIR "${tzdata}/share/zoneinfo"
  '';

  meta = {
    description = "Terminal weather radar and forecast viewer for Denmark";
    homepage = "https://github.com/hallundbaek/whtr";
    mainProgram = "whtr";
    platforms = lib.platforms.linux;
  };
}
