# A signed launcher is a per-generation artifact: all routing is compiled in.
# Native LLVM emits AArch64 PE/COFF even on an x86_64 build host.
{ lib
, stdenvNoCC
, llvmPackages
, python3
, gnu-efi
, buildPackages
, bootPartuuid
, ukiPath
, qebspilPath ? "/EFI/el2/qebspilaa64.efi"
, slbouncePath ? "/EFI/el2/slbounceaa64.efi"
}:
let
  validPath = path:
    builtins.isString path
    && builtins.match "/[A-Za-z0-9_./-]+[.]efi" path != null
    && lib.all (part: part != "" && part != "." && part != "..")
      (builtins.tail (lib.splitString "/" path));
  routing = {
    inherit bootPartuuid ukiPath qebspilPath slbouncePath;
  };
in
assert lib.assertMsg (builtins.match "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" bootPartuuid != null)
  "EL2 launcher needs the XBOOTLDR GPT partition UUID (not filesystem UUID)";
assert lib.assertMsg (lib.all validPath [ ukiPath qebspilPath slbouncePath ])
  "EL2 launcher paths must be absolute ASCII .efi paths without empty/dot components";
stdenvNoCC.mkDerivation {
  pname = "lucent-el2-launcher";
  version = "1";
  dontUnpack = true;
  nativeBuildInputs = [ llvmPackages.clang-unwrapped llvmPackages.lld python3 ];
  routingJSON = builtins.toJSON routing;
  passAsFile = [ "routingJSON" ];

  buildPhase = ''
    runHook preBuild
    python3 - "$routingJSONPath" <<'PY'
    import json, sys, uuid
    config = json.load(open(sys.argv[1]))
    guid = uuid.UUID(config['bootPartuuid'])
    b = guid.bytes
    fields = [f'0x{guid.time_low:08x}', f'0x{guid.time_mid:04x}', f'0x{guid.time_hi_version:04x}',
              '{' + ','.join(f'0x{x:02x}' for x in b[8:]) + '}']
    with open('launcher-config.h', 'w') as f:
        f.write('#define BOOT_PARTUUID {' + ','.join(fields) + '}\n')
        for macro, key in [('UKI_PATH', 'ukiPath'), ('QEBSPIL_PATH', 'qebspilPath'), ('SLBOUNCE_PATH', 'slbouncePath')]:
            f.write('#define ' + macro + ' L' + json.dumps(config[key].replace('/', '\\')) + '\n')
    PY
    clang --target=aarch64-unknown-windows -std=c11 -O2 \
      -ffreestanding -fshort-wchar -fno-stack-protector -fno-builtin \
      -mno-outline-atomics -Wall -Wextra -Werror \
      -I${gnu-efi.src}/inc -I${gnu-efi.src}/inc/aarch64 -I. \
      -c ${./launcher.c} -o launcher.obj
    lld-link /subsystem:efi_application /entry:efi_main /machine:arm64 \
      /nodefaultlib /fixed:no /dynamicbase /nxcompat /timestamp:0 \
      /out:launcher.efi launcher.obj
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 ${./check-pe.py} launcher.efi
    cp ${./launcher.c} launcher.c
    cp ${./launcher-test.c} launcher-test.c
    ${buildPackages.stdenv.cc}/bin/cc -std=c11 -fshort-wchar -Wall -Wextra -Werror \
      -I${gnu-efi.src}/inc -I${gnu-efi.src}/inc/${buildPackages.stdenv.hostPlatform.parsed.cpu.name} -I. \
      launcher-test.c -o launcher-test
    LAUNCHER_TEST_VERBOSE=1 ./launcher-test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 launcher.efi "$out/lib/efi/lucent-el2-launcher.efi"
    install -Dm644 "$routingJSONPath" "$out/share/lucent-el2-launcher/routing.json"
    runHook postInstall
  '';

  passthru = { inherit routing; };
  meta = {
    description = "Entry-scoped AArch64 EFI launcher for qebspil, slbounce and a fixed UKI";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
