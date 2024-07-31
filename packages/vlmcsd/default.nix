{ lib
, stdenv
, fetchFromGitHub
}:

stdenv.mkDerivation rec {
  pname = "vlmcsd";
  version = "20230728";

  src = fetchFromGitHub {
    owner = "Wind4";
    repo = "vlmcsd";
    rev = "70e03572b254688b8c3557f898e7ebd765d29ae1";
    sha256 = "sha256-BEi47U0rdkO+AlQRpntsaTgm5A4CSwS6LuffAl2kIaw=";
  };

  installPhase = ''
    mkdir -p $out

    pushd bin
    for b in vlmcs{,d}; do
      install -D -m755 $b "$out/bin/$b"
    done
    popd

    pushd man
    for m in *.[0-9]; do
      s=''${m##*.}
      install -D -m644 $m "$out/share/man/man$s/$m"
    done
    popd

    install -D -m644 etc/vlmcsd.ini $out/share/vlmcsd/examples/vlmcsd.ini
    install -D -m644 etc/vlmcsd.kmd $out/share/vlmcsd/vlmcsd.kmd
  '';

  meta = with lib; {
    description = "KMS Emulator in C";
    homepage = "https://github.com/Wind4/vlmcsd";
    license = with licenses; [ free ];
    maintainers = with maintainers; [ pborzenkov ];
  };
}
