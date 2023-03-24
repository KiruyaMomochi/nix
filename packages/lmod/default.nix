{ stdenv
, fetchurl
, bc
, perl
, tcl
, lua
, luaPackages
, rsync
, procps
}:

# https://github.com/ComputeCanada/nixpkgs/blob/f6daa33900a71529aa7835cb5dbed5ddf854ec32/pkgs/tools/misc/lmod/default.nix#L4
with luaPackages; stdenv.mkDerivation rec {
  name = "Lmod-${version}";

  version = "8.7.20";
  src = fetchurl {
    url = "http://github.com/TACC/Lmod/archive/${version}.tar.gz";
    sha256 = "sha256-wE3v99LKNUYQo2JFmnqpocZCoJXkWksLskcbsyVOhfQ=";
  };

  buildInputs = [ lua tcl perl rsync procps bc ];
  propagatedBuildInputs = [ luaposix luafilesystem ];
  # set custom LD_LIBRARY_PATH so capture("groups") works properly
  # preConfigure = ''
  #   makeFlags="PREFIX=$out"
  # '';
  configureFlags = [ "--with-duplicatePaths=yes --with-caseIndependentSorting=yes --with-redirect=yes" ];

  preBuild = ''
    patchShebangs proj_mgmt/
  '';

  # replace nix-store paths in the environment with nix-profile paths to allow easy upgrade
  postInstall = ''
    # find $out/lmod/lmod/init/ -type f -print0 | xargs -0 sed -i -e "s;/cvmfs/soft.computecanada.ca/nix/store/[^/]*;/cvmfs/soft.computecanada.ca/nix/var/nix/profiles/16.09;g" ;
    # sed -i -e 's;/cvmfs/soft.computecanada.ca/nix/store/[^/"]*;/cvmfs/soft.computecanada.ca/nix/var/nix/profiles/16.09;g' \
    sed -i -e 's:/usr/share/lua/5.2/?.lua;/usr/share/lua/5.2/?/init.lua;/usr/lib/lua/5.2/?.lua;/usr/lib/lua/5.2/?/init.lua;./?.lua;::g' \
    	   -e 's:/usr/lib/lua/5.2/?.so;/usr/lib/lua/5.2/loadall.so;./?.so;::g' $(grep -rl "nix/store" $out | grep '\.lua')
    # sed -i -e 's;/cvmfs/soft.computecanada.ca/nix/store/[^/"]*;/cvmfs/soft.computecanada.ca/nix/var/nix/profiles/16.09;g' \
    sed -i -e 's:/usr/share/lua/5.2/?.lua;/usr/share/lua/5.2/?/init.lua;/usr/lib/lua/5.2/?.lua;/usr/lib/lua/5.2/?/init.lua;./?.lua;::g' \
    	   -e 's:/usr/lib/lua/5.2/?.so;/usr/lib/lua/5.2/loadall.so;./?.so;::g' $out/lmod/lmod/libexec/{computeHashSum,lmod,addto,spider,ml_cmd,spiderCacheSupport,sh_to_modulefile,update_lmod_system_cache_files} $out/lmod/lmod/settarg/{settarg_cmd,targ}
  '';

  LUA_PATH = "${luaposix}/share/lua/5.2/?.lua;${luaposix}/share/lua/5.2/?/init.lua;;";
  LUA_CPATH = "${luafilesystem}/lib/lua/5.2/?.so;${luaposix}/lib/lua/5.2/?.so;;";
  meta = {
    description = "Tool for configuring environments";
  };
}
