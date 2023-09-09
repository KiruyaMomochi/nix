{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, glib
}:
stdenv.mkDerivation rec {
  pname = "naiveproxy";
  version = "116.0.5845.92-2";

  src = fetchurl {
    url = "https://github.com/klzgrad/naiveproxy/releases/download/v${version}/naiveproxy-v${version}-linux-x64.tar.xz";
    sha256 = "sha256-QarVB43fxALbY7tmR+B4em+N9Sf2iCvnHwTJyYOSHcE=";
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
