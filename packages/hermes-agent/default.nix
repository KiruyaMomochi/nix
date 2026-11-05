{ lib
, stdenv
, patch
, sqlite
, makeWrapper
, python314
, inputs
, hermesAgent ? inputs.hermes-agent.packages.${stdenv.hostPlatform.system}.default
, hermesAgentSrc ? inputs.hermes-agent
, extraDependencyGroups ? [ ]
, includeLocales ? true
, patches ? [ ]
,
}:

let
  # The flake source has no .git, so upstream stamps the placeholder "0.0.0" and
  # plugins with requires_hermes refuse to load. "unknown" is unparseable, which
  # the version gate treats as permissive. Upstream issue #130070.
  base = hermesAgent.override (
    { version = "unknown"; }
    // lib.optionalAttrs (extraDependencyGroups != [ ]) { inherit extraDependencyGroups; }
  );

  sitePackages = python314.sitePackages;
  localesSrc = lib.cleanSource (hermesAgentSrc + "/locales");

  origVenv = base.passthru.hermesVenv;

  # cjk_unicode61 FTS5 tokenizer (native/fts5_cjk): bigram index for 1-2 char
  # CJK search terms, which otherwise fall back to a LIKE scan.
  fts5Cjk = stdenv.mkDerivation {
    pname = "hermes-fts5-cjk";
    version = "0";
    src = hermesAgentSrc + "/native/fts5_cjk";
    buildInputs = [ sqlite ];
    buildPhase = ''
      $CC -shared -fPIC -O2 -Wall fts5_cjk.c -o libfts5_cjk.so
    '';
    installPhase = ''
      install -Dm0644 libfts5_cjk.so $out/lib/libfts5_cjk.so
    '';
  };

  # pyprojectMakeVenv hardlinks package contents from the wheel derivation into
  # the venv. Patch the wheel itself, then substitute it into NIX_PYPROJECT_DEPS;
  # copying into the venv would not work because Path(__file__).resolve() follows
  # hardlinks back to the original wheel derivation.
  origWheel = builtins.head (
    builtins.filter
      (drv: lib.hasPrefix "/nix/store" drv && lib.hasInfix "-hermes-agent-" drv)
      (lib.splitString ":" origVenv.NIX_PYPROJECT_DEPS)
  );

  patchedWheel = stdenv.mkDerivation {
    name = "hermes-agent-local-patches";
    src = origWheel;
    dontUnpack = true;
    nativeBuildInputs = [ patch ];

    installPhase = ''
      cp -a $src $out
      chmod -R u+w $out

      ${lib.optionalString includeLocales ''
        cp -r ${localesSrc} $out/${sitePackages}/locales
      ''}

      # pm treats site-packages as the repo root and seeds plugin venvs from its
      # uv.lock; the wheel ships neither file, so enabling a plugin fails.
      cp ${hermesAgentSrc + "/pyproject.toml"} ${hermesAgentSrc + "/uv.lock"} $out/${sitePackages}/

      ${lib.concatMapStringsSep "\n" (p: ''
        patch -p1 -d $out/${sitePackages} < ${p}
      '') patches}
    '';
  };

  patchedVenv = origVenv.overrideAttrs (old: {
    NIX_PYPROJECT_DEPS = builtins.replaceStrings
      [ origWheel ]
      [ "${patchedWheel}" ]
      old.NIX_PYPROJECT_DEPS;
  });
in
base.overrideAttrs (old: {
  pname = "hermes-agent";

  installPhase = builtins.replaceStrings
    [ (builtins.unsafeDiscardStringContext "${origVenv}") ]
    [ "${patchedVenv}" ]
    old.installPhase;

  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ makeWrapper ];

  postInstall = (old.postInstall or "") + ''
    for wrapper in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
      if [ -e "$wrapper" ] && grep -q ${origVenv} "$wrapper"; then
        substituteInPlace "$wrapper" --replace-fail ${origVenv} ${patchedVenv}
      fi
      if [ -e "$wrapper" ]; then
        wrapProgram "$wrapper" --set-default HERMES_FTS5_CJK_SO ${fts5Cjk}/lib/libfts5_cjk.so
      fi
    done
  '';

  passthru = old.passthru // {
    hermesVenv = patchedVenv;
    inherit fts5Cjk;
    unpatched = base;
    appliedPatches = patches;
  };
})
