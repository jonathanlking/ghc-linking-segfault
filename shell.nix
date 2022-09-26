let pkgs = import ./default.nix;
in
  pkgs.mkShell {
    buildInputs = [
      pkgs.staticHaskell.ghc
      pkgs.staticHaskell.cabal-install
      pkgs.which
      pkgs.gdb
    ];

    OPENSSL_STATIC_LIB = "${pkgs.staticHaskell.openssl.out}/lib";
    OPENSSL_BOTH_LIB = "${pkgs.staticHaskell.openssl_both.out}/lib";
  }
