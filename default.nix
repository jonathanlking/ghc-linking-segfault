let
  baseNixpkgs = builtins.fetchTarball {
    name = "nixos-unstable-2023-01-03";
    url = https://github.com/NixOS/nixpkgs/archive/de8e0bfaa7e8032ea6698c5d5cc34216604fcaa3.tar.gz;
    sha256 = "1bh1bbg6mgbvf6sd8b2gw5nqkqmrc44ga6szs0869vkal186nm6b";
  };

  # `static-haskell-nix` is a repository maintained by @nh2 that documents and
  # implements the litany of tricks necessary to construct a Nix-Haskell
  # toolchain capable of building fully-statically-linked binaries.

  staticHaskellNixpkgs = builtins.fetchTarball {
    url = https://github.com/nh2/static-haskell-nix/archive/bd66b86b72cff4479e1c76d5916a853c38d09837.tar.gz;
    sha256 = "0rnsxaw7v27znsg9lgqk1i4007ydqrc8gfgimrmhf24lv6galbjh";
  };

  patches =
    pkgs.callPackage nix/patches { };

  # ncurses is broken in the latest version of static-haskell-nix, so we need to
  # patch it to get Cabal to build.
  patched-static-haskell-nix =
    patches.applyPatches "patched-static-haskell-nix"
      staticHaskellNixpkgs
      [
        patches.static-haskell-nix-ncurses
      ];

  # The `static-haskell-nix` repository contains several entry points for e.g.
  # setting up a project in which Nix is used solely as the build/package
  # management tool. We are only interested in the set of packages that underpin
  # these entry points, which are exposed in the `survey` directory's
  # `approachPkgs` property.
  staticHaskellPkgs =
    let
      p = import (patched-static-haskell-nix + "/survey/default.nix") {
        compiler = "ghc944";
        defaultCabalPackageVersionComingWithGhc = "Cabal_3_8_1_0";
        normalPkgs = import baseNixpkgs { overlays = []; };
      };
    in
      p.approachPkgs;

  # With all the pins and imports done, it's time to build our overlay, in which
  # we are interested in:
  #
  # * Providing a GHC that is capable of building fully-statically-linked
  #   binaries.
  #
  # * Providing any system-level/C libraries and packages that we'll need that
  #   aren't already in the `static-haskell-nix` package set (see below for
  #   examples). These are the packages/libraries we'll link when building
  #   Haskell code that has e.g. C dependencies (think PostgreSQL, SSH2, etc.).
  #
  # We accomplish this by exposing the `static-haskell-nix` package set
  # wholesale as `staticHaskell` and extending _that_ with the things we need.
  # If you don't like this approach/would like to structure your Nix derivations
  # differently, feel free -- the only important bits are the leaf packages
  # (e.g. GHC, etc.) themselves.
  overlay = self: super: {
    staticHaskell = staticHaskellPkgs.extend (selfSH: superSH: {
      # We start with GHC, the compiler and arguably the most important bit. The
      # GHC in `static-haskell-nix` is a good base (it uses Musl via
      # `pkgsMusl` and so has a C library layer designed for static linking) but
      # is not quite perfect. Specifically, we make the following tweaks:
      #
      # * (pic-dynamic) At present, upstream Nixpkgs passes `-fPIC` when
      #   `enableRelocatableStaticLibs` is activated but this is actually not
      #   sufficient for GHC to generate 100% relocatable static library code.
      #   We must also pass `-fexternal-dynamic-refs`, lest GHC generate
      #   `R_X86_64_PC32` relocations which break things. We pass these flags
      #   both when building core GHC libraries (e.g. `base`, `containers`;
      #   through `GhcLibHcOpts`) and when building the GHC runtime system (RTS;
      #   through `GhcRtsHcOpts`). See the `preConfigure` phase for more
      #   information.
      ghc = (superSH.ghc.override {
        # See (pic-dynamic)
        enableRelocatedStaticLibs = true;
        enableShared = false;
      }).overrideAttrs (oldAttrs: {
        preConfigure = ''
          # See (pic-dynamic)
          ${oldAttrs.preConfigure or ""}
          echo "GhcLibHcOpts += -fPIC -fexternal-dynamic-refs" >> mk/build.mk
          echo "GhcRtsHcOpts += -fPIC -fexternal-dynamic-refs" >> mk/build.mk
          echo "GhcLibHcOpts += -g3" >> mk/build.mk
          echo "GhcRtsHcOpts += -g3" >> mk/build.mk
          echo "GhcHcOpts += -DDEBUG -debug" >> mk/build.mk
          echo "EXTRA_HC_OPTS += -debug" >> mk/build.mk
          echo "STRIP_CMD = :" >> mk/build.mk
        '';
        dontStrip = true;
      });

      # A custom derivation that contains both static and dynamic libraries.
      # Note that setting `static = false` isn't sufficient as the derivation at
      # https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/libraries/openssl/default.nix
      # will remove `.a` files in this case. Consequently we build with
      # `static = false` and then explicitly copy the static libraries _back in_
      # from the existing derivation (which sets `static = true`).
      #
      openssl_both =
        (superSH.openssl.overrideAttrs (old: {
          postInstall = ''
            ${old.postInstall}

            cp ${superSH.openssl.out}/lib/*.a $out/lib
          '';
        })).override {
          static = false;
        };

    });

  };

  pkgs = import baseNixpkgs ({ overlays = [overlay]; });

in pkgs
