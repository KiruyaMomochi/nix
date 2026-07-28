{ lib
, stdenvNoCC
, buildGoModule
, fetchgit
, gn
, ninja
, python3
, symlinkJoin
, llvmPackages
,
}:

let
  version = "148.0.7778.96";

  src = fetchgit {
    url = "https://github.com/SagerNet/cronet-go.git";
    rev = "d62042e935130168f4cebcd4515319a88ee7abcf";
    hash = "sha256-QT9+2p8H7b9h83K6euPkrGBqeXnM71/66QOMw1Fs9fA=";
    fetchSubmodules = true;
  };

  clangBasePath = symlinkJoin {
    name = "cronet-go-llvm-toolchain";
    paths = [
      llvmPackages.llvm
      llvmPackages.stdenv.cc
    ];
  };

  build-naive = buildGoModule {
    pname = "cronet-go-build-naive";
    inherit version src;

    vendorHash = "sha256-pyeE+JPuRQEjNzrF+o9jslBcBM1vruuL+I/DCIa2BG0=";
    nativeBuildInputs = [ python3 ];
    subPackages = [ "cmd/build-naive" ];

    postPatch = ''
      substituteInPlace cmd/build-naive/cmd_build.go \
        --replace-fail 'runGetClang(t)' '// runGetClang(t)' \
        --replace-fail 'gnPath := filepath.Join(srcRoot, "gn", "out", "gn")' 'gnPath := "${lib.getExe gn}"'

      export CRONET_GO_CLANG_BASE_PATH=${lib.escapeShellArg (toString clangBasePath)}
      ${lib.getExe python3} - <<'PY'
      from pathlib import Path

      path = Path("cmd/build-naive/cmd_build.go")
      text = path.read_text()

      old = '\t\tfmt.Sprintf("target_cpu=\\"%s\\"", t.CPU),\n'
      new = old + '\t\t"clang_use_chrome_plugins=false",\n' + \
          '\t\tfmt.Sprintf("clang_base_path=\\"%s\\"", os.Getenv("CRONET_GO_CLANG_BASE_PATH")),\n'
      if old not in text:
          raise SystemExit("target_cpu GN argument anchor not found")
      text = text.replace(old, new, 1)

      old = ('\t\t// Sysroot is handled by get-clang.sh, use the naiveproxy path\n'
             '\t\tsysrootPath := getSysrootPath(t)\n'
             '\t\tsysrootDirectory := strings.TrimPrefix(sysrootPath, srcRoot+string(filepath.Separator))\n'
             '\t\targs = append(args, "use_sysroot=true", fmt.Sprintf("target_sysroot=\\"//%s\\"", sysrootDirectory))')
      new = '\t\targs = append(args, "use_sysroot=false")'
      if old not in text:
          raise SystemExit("Linux sysroot GN argument block not found")
      path.write_text(text.replace(old, new, 1))
      PY

      substituteInPlace cmd/build-naive/cmd_package.go \
        --replace-fail 'runCommand(targetDirectory, "go", "mod", "tidy")' '// runCommand(targetDirectory, "go", "mod", "tidy")'
    '';

    meta.mainProgram = "build-naive";
  };
in
stdenvNoCC.mkDerivation {
  pname = "libcronet-naive";
  inherit version src;

  outputs = [
    "out"
    "static"
  ];

  postPatch = ''
    substituteInPlace naiveproxy/src/build/config/compiler/BUILD.gn \
      --replace-fail 'cflags += [ "-fno-lifetime-dse" ]' '# cflags += [ "-fno-lifetime-dse" ]' \
      --replace-fail '"-fsanitize-ignore-for-ubsan-feature=array-bounds"' '# "-fsanitize-ignore-for-ubsan-feature=array-bounds"' \
      --replace-fail '"-fsanitize-ignore-for-ubsan-feature=return"' '# "-fsanitize-ignore-for-ubsan-feature=return"' \
      --replace-fail '"-Wno-unsafe-buffer-usage-in-static-sized-array"' '# "-Wno-unsafe-buffer-usage-in-static-sized-array"'
  '';

  nativeBuildInputs = [
    llvmPackages.bintools
    ninja
    python3
  ];

  env.CRONET_GO_CLANG_BASE_PATH = clangBasePath;

  buildPhase = ''
    runHook preBuild

    ${lib.getExe build-naive} build -t ${stdenvNoCC.hostPlatform.go.GOOS}/${stdenvNoCC.hostPlatform.go.GOARCH}
    ${lib.getExe build-naive} package --local -t ${stdenvNoCC.hostPlatform.go.GOOS}/${stdenvNoCC.hostPlatform.go.GOARCH}
    ${lib.getExe build-naive} package -t ${stdenvNoCC.hostPlatform.go.GOOS}/${stdenvNoCC.hostPlatform.go.GOARCH}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 lib/*/libcronet${stdenvNoCC.hostPlatform.extensions.sharedLibrary} \
      $out/lib/libcronet${stdenvNoCC.hostPlatform.extensions.sharedLibrary}
    install -Dm644 lib/*/libcronet.a $static/lib/libcronet.a

    install -Dm644 include/*.h -t $out/include
    mkdir -p $out/share/cronet-go/go
    install -Dm644 include_cgo.go lib/*/*.go lib/*/go.mod -t $out/share/cronet-go/go

    runHook postInstall
  '';

  passthru.build-naive = build-naive;

  meta = {
    description = "Cronet library with SagerNet naive proxy support";
    homepage = "https://github.com/SagerNet/cronet-go";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
