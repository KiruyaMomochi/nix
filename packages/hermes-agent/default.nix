{ lib
, stdenv
, patch
, python312
, inputs
, hermesAgent ? inputs.hermes-agent.packages.${stdenv.hostPlatform.system}.default
, hermesAgentSrc ? inputs.hermes-agent
, extraDependencyGroups ? [ ]
, includeLocales ? true
, patches ? [
    ./vision-anthropic.patch
    ./fallback-custom-api-mode.patch
    ./gemini-cli-aux.patch
    ./context-control.patch              # context_control.yaml injection
    ./prompt-overrides.patch             # prompt_overrides.yaml support
    ./memory-context-header-override.patch
    ./context-window-override.patch
    ./compaction-preamble-override.patch  # custom compaction preamble
    ./compaction-role-labels.patch        # [USER]/[ASSISTANT] → custom labels
    ./post-compaction-message-loss.patch  # flush offset reset after split (#43066)
    ./session-db-flush-cursor.patch      # stale cursor clamp (#43066)
    ./gateway-db-persistence-fallback.patch # gateway-side DB write fallback (#43066)
    ./telegram-hide-reasoning.patch      # suppress reasoning blocks in TG
    ./telegram-split-replies.patch       # opt-in paragraph splitting for TG replies
    ./telegram-stream-split-replies.patch # split TG streaming replies on ---
    ./telegram-split-reply-first-only.patch # only first bubble replies to user msg
    ./stop-retry-message-loss.patch      # message loss on stop+retry
    ./background-review-file-tools.patch
    ./nixos-path-fill.patch              # PATH handling for NixOS
  ]
,
}:

let
  base =
    if extraDependencyGroups == [ ]
    then hermesAgent
    else hermesAgent.override { inherit extraDependencyGroups; };

  sitePackages = python312.sitePackages;
  localesSrc = lib.cleanSource (hermesAgentSrc + "/locales");

  origVenv = base.passthru.hermesVenv;

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

  postInstall = (old.postInstall or "") + ''
    for wrapper in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
      if [ -e "$wrapper" ] && grep -q ${origVenv} "$wrapper"; then
        substituteInPlace "$wrapper" --replace-fail ${origVenv} ${patchedVenv}
      fi
    done
  '';

  passthru = old.passthru // {
    hermesVenv = patchedVenv;
    unpatched = base;
    appliedPatches = patches;
  };
})
