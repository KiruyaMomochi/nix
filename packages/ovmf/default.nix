{ OVMFFull
, callPackage
}:
let
  edk2 = callPackage ./edk2.nix { };
in
(OVMFFull.override
{
  inherit edk2;
  # Disable systemManagementModeRequired as legacy gvt-d require i440fx
  # However, i440fx does not support SMM
  # This may affect S3 suspend, but it's not a big issue for our virtual environment
  systemManagementModeRequired = false;
})
