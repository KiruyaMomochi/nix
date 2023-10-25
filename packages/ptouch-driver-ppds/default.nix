{ stdenv
, perl
, cups-filters
, ghostscript
, netpbm
, psutils
, foomatic-db-engine
, patchPpdFilesHook
, callPackage # TODO: ptouch-driver
}:
let 
  ptouch-driver = callPackage ../ptouch-driver {};
in
# TODO: some dependencies are not required.
stdenv.mkDerivation rec {
  pname = "ptouch-ppds";
  version = "git";

  buildInputs = [
    cups-filters
    ghostscript
    netpbm
    perl
    psutils
    ptouch-driver
    foomatic-db-engine
  ];

  nativeBuildInputs = [
    foomatic-db-engine
    patchPpdFilesHook
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "${placeholder "out"}/share/cups/model"
    foomatic-compiledb -j "$NIX_BUILD_CORES" -d "${placeholder "out"}/share/cups/model/${pname}"
    runHook postInstall
  '';

  ppdFileCommands = [
    "cat"
    "echo" # coreutils
    "foomatic-rip" # cups-filters or foomatic-filters
    "gs" # ghostscript
    "pnmflip"
    "pnmgamma"
    "pnmnoraw" # netpbm
    "perl" # perl
    "psresize" # psutils
    "rastertoptch" # ptouch-driver
  ];

  # compress ppd files
  postFixup = ''
    echo 'compressing ppd files'
    find -H "${placeholder "out"}/share/cups/model/${pname}" -type f -iname '*.ppd' -print0  \
      | xargs -0r -n 64 -P "$NIX_BUILD_CORES" gzip -9n
  '';
}
