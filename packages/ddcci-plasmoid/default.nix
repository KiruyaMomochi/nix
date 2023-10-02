{ fetchFromGitHub, stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "ddcci-plasmoid";
  version = "0.1.8";

  src = fetchFromGitHub {
    owner = "davidhi7";
    repo = "ddcci-plasmoid";
    rev = "1dc2f5594f2cf44496855b169fd1e1a4f1f41546";
    hash = "sha256-Q0Bbugh1rVl8Ze0yrVMEiQUYbMThj8bYFqzAZ400Yd4=";
  };

  installPhase = ''
    mkdir -p $out
    cp -r $src/plasmoid/* $out/
  '';
}
