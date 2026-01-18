{ lib
, sing-box
, kyaru
, runCommand
}:

sing-box.override {
  buildGoModule = args: sing-box.buildGoModule (args // {
    pname = "sing-box-naive";
    
    tags = (args.tags or []) ++ [ "with_naive" ];
    
    buildInputs = (args.buildInputs or []) ++ [ kyaru.libcronet ];
    
    # We need to tell CGO where to find the header and the library
    # CGO_CFLAGS = "-I${kyaru.libcronet}/include";
    # CGO_LDFLAGS = "-L${kyaru.libcronet}/lib -lcronet";
    
    # Using preBuild to inject env vars might be safer or pass them via overrideAttrs env?
    # buildGoModule supports overriding 'env' in recent nixpkgs versions or directly as attrs.
    
    CGO_CFLAGS = "-I${kyaru.libcronet}/include";
    CGO_LDFLAGS = "-L${kyaru.libcronet}/lib -lcronet";
    
    # Ensure RPATH is set so it finds libcronet.so at runtime
    # We can use allowMissingDependencies if strictly needed, but let's try standard way.
    
    ldflags = (args.ldflags or []) ++ [
      "-rpath ${kyaru.libcronet}/lib"
    ];
    
    # If the above rpath doesn't work (Go linker sometimes is tricky), we use postFixup
    postFixup = (args.postFixup or "") + ''
      # Add libcronet to RPATH
      patchelf --add-rpath "${kyaru.libcronet}/lib" $out/bin/sing-box
    '';
  });
}
