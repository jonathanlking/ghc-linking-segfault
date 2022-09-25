let pkgs = import ./default.nix;
in
  pkgs.mkShell {
    buildInputs = [
      pkgs.staticHaskell.ghc
      pkgs.staticHaskell.cabal-install
      pkgs.which
    ];

    OPENSSL_LIB = "${pkgs.staticHaskell.openssl_both.out}/lib";
  }
