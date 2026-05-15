{ stdenv
, lib
, fetchurl
, autoPatchelfHook
}:
stdenv.mkDerivation rec {
  pname = "greptimedb";
  version = "1.0.1";

  src = fetchurl {
    url = "https://github.com/GreptimeTeam/greptimedb/releases/download/v${version}/greptime-linux-amd64-v${version}.tar.gz";
    hash = "sha256-fPXM9aAkLquGOurIPOd4BPDbOtpEdwNzKVKAUqj5CRE=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  # libgcc_s.so.1 lives in stdenv.cc.cc.lib; glibc comes from stdenv automatically.
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -m755 -D greptime $out/bin/greptime
    runHook postInstall
  '';

  meta = with lib; {
    description = "Open-source unified time-series database for metrics, logs, and traces (prebuilt amd64 tarball)";
    homepage = "https://github.com/GreptimeTeam/greptimedb";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "greptime";
  };
}
