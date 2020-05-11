{ pkgs, lib, symlinkJoin, makeWrapper
, hpack, git, nix, nix-prefetch-git
, fetchExternal, cleanSourceHaskell, mkCabalProjectPkgSet
, ... }@args:

let
  src = cleanSourceHaskell {
    src = fetchExternal {
      name     = "nix-tools-src";
      specJSON = ./nix-tools-src.json;
      override = "nix-tools-src";
    };
  };

  pkgSet = mkCabalProjectPkgSet {
    plan-pkgs = if args ? ghc
                then import (./pkgs + "-${args.ghc.version}.nix")
                else import ./pkgs.nix;
    pkg-def-extras = [
      # We need this, as we are going to *re-isntall* happy, and happy > 1.19.9 needs
      # a patched lib:Cabal to be properly installed.
      (hackage: { packages = { happy = hackage.happy."1.19.9".revisions.default; }; })
    ];
    modules = [
      {
        packages.transformers-compat.components.library.doExactConfig = true;
        packages.time-compat.components.library.doExactConfig = true;
        packages.time-locale-compat.components.library.doExactConfig = true;
      }

      {
        packages.nix-tools.src = src;
      }

      {
        # Make Cabal reinstallable
        nonReinstallablePkgs =
          [ "rts" "ghc-heap" "ghc-prim" "integer-gmp" "integer-simple" "base"
            "deepseq" "array" "ghc-boot-th" "pretty" "template-haskell"
            "ghc-boot"
            "ghc" "Win32" "array" "binary" "bytestring" "containers"
            "directory" "filepath" "ghc-boot" "ghc-compact" "ghc-prim"
            "hpc"
            "mtl" "parsec" "process" "text" "time" "transformers"
            "unix" "xhtml"
          ];
      }
    ] ++ pkgs.lib.optional (args ? ghc) { ghc.package = args.ghc; };
  };

  hsPkgs = pkgSet.config.hsPkgs;

  tools = [ hpack git nix nix-prefetch-git ];
in
  symlinkJoin {
    name = "nix-tools";
    paths = builtins.attrValues hsPkgs.nix-tools.components.exes;
    buildInputs = [ makeWrapper ];
    meta.platforms = lib.platforms.all;
    # We wrap the -to-nix executables with the executables from `tools` (e.g. nix-prefetch-git)
    # so that consumers of `nix-tools` won't have to provide those tools.
    postBuild = ''
      for prog in stack-to-nix cabal-to-nix plan-to-nix; do
        wrapProgram "$out/bin/$prog" --prefix PATH : "${lib.makeBinPath tools}"
      done
    '';
  }
