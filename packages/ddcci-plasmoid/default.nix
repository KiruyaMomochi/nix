{ fetchFromGitHub, stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "ddcci-plasmoid";
  version = "0.1.8";

  src = fetchFromGitHub {
    owner = "davidhi7";
    repo = "ddcci-plasmoid";
    rev = "db3ca1ac83b9b40c30723555674ca57ae5a0dd61";
    hash = "sha256-/YzIfkAlbxxS41VGwQ7Br+rGM8T3ez5nVxP536o7Lnk=";
  };

  installPhase = ''
    mkdir -p $out
    cp -r $src/plasmoid/* $out/
  '';
}
