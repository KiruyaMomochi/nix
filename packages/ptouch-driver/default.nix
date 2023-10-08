{ stdenv
, autoreconfHook
, fetchFromGitHub
, perl
, perlPackages
, cups
, libpng
, pkg-config
}:
stdenv.mkDerivation rec {
  pname = "ptouch-driver";
  version = "git";
  src = fetchFromGitHub {
    repo = "printer-driver-ptouch";
    owner = "KiruyaMomochi";
    rev = "p910bt";
    sha256 = "sha256-s50R0jr5CXeHhoIikZguFs09oO/BIBPhNQPrFn7pK4o=";
  };

  buildInputs = [
    pkg-config
    perl
    cups
    libpng
  ];
  nativeBuildInputs = [
    pkg-config
    autoreconfHook
    perl
    perlPackages.XMLLibXML
  ];

  prePatch = ''
    patchShebangs --build ./foomaticalize
  '';

  postInstall = ''
    install -vd "${placeholder "out"}/bin"
    ln -vst "${placeholder "out"}/bin/" "${placeholder "out"}/lib/cups/filter/rastertoptch" 
  '';

  postBuild = ''
    mkdir -p "${placeholder "out"}"/{etc/cups,nix-support}
    cat  >> "${placeholder "out"}/nix-support/setup-hook"  << eof
    export FOOMATICDB="${placeholder "out"}/share/foomatic"
    eof
  '';
}
