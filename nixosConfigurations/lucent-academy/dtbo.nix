{
  lib,
  runCommand,
  dtc,
  stdenv,
  src,
  # Fragment directories under overlay/fragments, applied in name order.
  # Add "experimental" to also get the EC node.
  fragmentDirs ? [ "" ],
}:

# Same steps as upstream overlay/build-overlay.sh.
let
  fragments = lib.concatMap (
    d:
    let
      dir = "${src}/overlay/fragments/${d}";
    in
    map (n: "${dir}/${n}") (
      lib.sort lib.lessThan (
        lib.filter (n: lib.hasSuffix ".dtsi" n) (lib.attrNames (builtins.readDir dir))
      )
    )
  ) fragmentDirs;
in
runCommand "vivobook-s15-dtbo"
  {
    nativeBuildInputs = [
      dtc
      stdenv.cc
    ];
  }
  ''
    {
      echo '/dts-v1/;'
      echo '/plugin/;'
      echo '#include <dt-bindings/sound/qcom,q6dsp-lpass-ports.h>'
      echo '#include <dt-bindings/sound/qcom,q6afe.h>'
      echo '/ { compatible = "asus,vivobook-s15"; };'
      ${lib.concatMapStrings (f: "cat ${f}\n") fragments}
    } > vb.dts
    cpp -nostdinc -I ${src}/overlay/include -undef -D__DTS__ -x assembler-with-cpp -P -o vb.pp.dts vb.dts
    mkdir -p $out
    dtc -q -@ -I dts -O dtb -o $out/vivobook-s15.dtbo vb.pp.dts
  ''
