{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, glib
}:
stdenv.mkDerivation rec {
  pname = "naiveproxy";
  version = "121.0.6167.71-1";

  src = fetchurl {
    url = "https://github.com/klzgrad/naiveproxy/releases/download/v${version}/naiveproxy-v${version}-linux-x64.tar.xz";
    sha256 = "sha256-qRoc5XFD1tquaFG47+18FAoku+dpmqVP1jtJSqtRQTo=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    glib
  ];

  installPhase = ''
    install -m755 -D naive $out/bin/naive
  '';

  meta = with lib; {
    homepage = "https://github.com/klzgrad/naiveproxy";
    description = "naiveproxy";
    platforms = platforms.linux;
  };
}
