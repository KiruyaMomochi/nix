{ OVMFFull
, callPackage
}:
let
  edk2 = callPackage ./edk2.nix { };
in
(OVMFFull.override
{
  inherit edk2;
})
