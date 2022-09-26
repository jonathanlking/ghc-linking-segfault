## A minimal example of a GHC linking segfault

This repo is trying to recreate a _slightly less minimal_ example of the linking
segfault in the [minirepo](https://github.com/jonathanlking/minirepo/compare/master...jonathanlking:minirepo:openssl-segfault)
(see also [minirepo on 9.2.4](https://github.com/jonathanlking/minirepo/compare/openssl-segfault...jonathanlking:minirepo:openssl-segfault-924))
without using Bazel (and [`rules_haskell`](https://github.com/tweag/rules_haskell)).

We use the same patched version of GHC, derived from [`static-haskell-nix`](https://github.com/nh2/static-haskell-nix/tree/bd66b86b72cff4479e1c76d5916a853c38d09837/), but instead use Cabal to build things.

You will need `nix` [installed](https://nixos.org/download.html) to build the example.

Subsequent commands are run from within a `nix-shell --pure` shell.

The example is structured as follows:

- An "FFI" lib, that foreign imports the `OPENSSL_hexchar2int` from `libcrypto` and exports `hexchar2int`, a Haskell wrapped version.
- A "no Template Haskell" binary, that just prints the result of `hexchar2int 'a'` in its `main`.
- A "Template Haskell" binary, that evaluates `hexchar2int 'a'` at compile time.

We also build `libcrypto` and `libssl` and expose paths to them through environment variables.
`$OPENSSL_STATIC_LIB` contains just the `.a` files, while `$OPENSSL_BOTH_LIB` contains `.so` files too.

The observed behaviour is:

- Running `cabal run bin-no-th --extra-lib-dirs=$OPENSSL_STATIC_LIB` will compile, run and output `10`.
- Running `cabal run bin-th --extra-lib-dirs=$OPENSSL_STATIC_LIB` will segfault during compilation.

This replicates the behaviour of `bazel run //minimal-segfault:bin-th` in the [Bazel based example](https://github.com/jonathanlking/minirepo/tree/openssl-segfault-924).

Interestingly though, running `cabal run bin-th --extra-lib-dirs=$OPENSSL_BOTH_LIB` does **not segfault** and `libcrypto.so` is loaded (preferentially over `libcrypto.a`).

We can call `file $(cabal exec which bin-no-th)` to confirm that out built executable is statically linked (the static linking is configured in the `cabal.project` file).

### Cachix

As we use a custom-built version of GHC, this can take some time to build (~50 minutes on my desktop machine).
I've set up a [Cachix cache](https://app.cachix.org/cache/ghc-linking-segfault#pull), so you shouldn't need to build anything locally (if you're on an x86 Linux machine).

With cachix installed you just need to run `cachix use ghc-linking-segfault`.

To populate the cache I ran:

```bash
nix-build \
  -A staticHaskell.ghc \
  -A staticHaskell.cabal-install \
  -A staticHaskell.openssl_both.out \
  | cachix push ghc-linking-segfault

```

### Attribution

- [minirepo](https://github.com/lunaris/minirepo) for providing the nix derivation for building a statically linked Haskell toolchain.
- [postgrest](https://github.com/PostgREST/postgrest) for providing known "good" versions of `static-haskell-nix` and `nixpkgs`, with patches for broken things (e.g. `static-haskell-nix-ncurses.patch`).
