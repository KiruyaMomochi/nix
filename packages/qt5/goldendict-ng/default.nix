{ goldendict
, lib
, fetchFromGitHub
, libzim
, qtwebengine
, qtwebchannel
, qtmultimedia
, qtspeech
}:
(goldendict.override { qtwebkit = null; }).overrideAttrs
  (oldAttrs: rec {
    pname = "goldendict-ng";
    version = "24.01.22-LoongYear.3dddb3be";
    src = fetchFromGitHub {
      owner = "xiaoyifang";
      repo = pname;
      rev = "v${version}";
      sha256 = "sha256-+OiZEkhNV06fZXPXv9zDzgJS5M3isHlcOXee3p/ejpw=";
    };
    patches = [ ];
    postPatch = "";
    buildInputs = oldAttrs.buildInputs ++ (
      [
        libzim
        qtwebengine
        qtwebchannel
        qtmultimedia
        qtspeech
      ]);

    meta = with lib; {
      homepage = "https://github.com/xiaoyifang/goldendict-ng";
      description = "The Next Generation GoldenDict";
      longDescription = ''
        The Next Generation GoldenDict.
        A feature-rich open-source dictionary lookup program,
        supporting [multiple dictionary formats](https://xiaoyifang.github.io/goldendict-ng/dictformats/)
        and online dictionaries.
      '';
      platforms = with platforms; linux ++ darwin;
      license = licenses.gpl3Plus;
    };
  })
