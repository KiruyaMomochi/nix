{ fetchFromGitHub, stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "ddcci-plasmoid";
  version = "0.1.10";

  # Plasma 6 applet; the plain v0.1.10 tag still ships Plasma 5 metadata.
  src = fetchFromGitHub {
    owner = "davidhi7";
    repo = "ddcci-plasmoid";
    rev = "b8e5a2a9a7f4ac6c879d751d637a71a08b03ab8d"; # v0.1.10-kf6
    hash = "sha256-/UTIflcUyPHMQ2CQG0d2R0MaKuXYmlvnYnLNQ+nMWvw=";
  };

  installPhase = ''
    mkdir -p $out
    cp -r $src/plasmoid/* $out/
  '';
}
