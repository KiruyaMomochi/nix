{ lib
, stdenv
, fetchFromGitHub
, cmake
, python3
, vulkan-loader
, vulkan-headers
, python3Packages
, openxr-loader
}:

stdenv.mkDerivation rec {
  pname = "openxr-hpp";
  version = "1.0.26";

  src = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "OpenXR-HPP";
    rev = "release-${version}";
    hash = "sha256-JEqE5QLpgec+/RMWrmGCi6w7/n53t9ThjxwbgqT4lNk=";
  };

  nativeBuildInputs = [ cmake python3 python3Packages.jinja2 vulkan-loader vulkan-headers openxr-loader ];

  cmakeFlags = [ "-DBUILD_TESTS=OFF" "-DSKIP_EZVCPKG=ON" "-DOPENXR_SDK_SRC_DIR=${openxr-loader.src}" ];

  buildPhase = ''
    make generate_headers
  '';

  meta = with lib; {
    description = "C++ bindings for OpenXR";
    homepage = "https://github.com/KhronosGroup/OpenXR-HPP";
    license = licenses.asl20;
    maintainers = [ ];
  };
}
