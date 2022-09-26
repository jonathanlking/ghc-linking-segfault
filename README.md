## A minimal example of a GHC linking segfault

This repo provides a _slightly more minimal_ example of the linking
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

We can call `file $(cabal exec which bin-no-th)` to confirm that our built executable is statically linked (the static linking is configured in the `cabal.project` file).

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

### Hacking

We have built GHC with some flags to make debugging easier:

- `-g3` provides symbols for GDB, so you can refer to function names/line numbers.
- `-debug` enables RTS debug logs (see `debugBelch` lines in the GHC source), which are printed when certain environment variable flags are set, e.g. `GHCRTS=-Dl` for linker logs.

#### GHC in GDB

It's helpful to be able to run `ghc` from within `gdb` to step through exactly
what's happening before the segfault.

The easiest way to do this I found was to directly edit the wrapper script that
you can find at `which ghc` (within the nix-shell):

```diff
-exec "$executablename" -B"$topdir" ${1+"$@"}
+exec gdb --args "$executablename" -B"$topdir" ${1+"$@"}
```

Note, you'll need to change this back again to get Cabal to build things again!

#### GHC arguments

To get the arguments passed (to recreate the call by Cabal) you can use a similar trick:

```diff
+for word in ${1+"$@"}; do echo "$word" >> /tmp/ghc-args.txt; done
+echo "---------------" >> /tmp/ghc-args.txt
```

We add the `-`s as a simple separator between the different calls; the lines
after the last set should be the arguments passed to the segfaulting call.

#### Dependencies

Cabal has built other things (e.g the FFI lib) before the call to GHC to
build the `bin-th` executable, so when we call GHC directly we need to make
sure all these files are in place.

I run `cabal clean` and then `cabal run bin-th --extra-lib-dirs=$OPENSSL_STATIC_LIB`
(making sure that the GHC wrapper _isn't_ calling `gdb`) to get the directories into a good state.

#### Running GDB and interesting breakpoints

Firstly, I recommend having a copy of GHC locally with checked-out at `ghc-9.2.4-release`.
In `gdb` if you enter `set directories <your-ghc-code-path>` it will present where you are in the source code.

Once GDB has started, if you `run` then it should segfault.
You can get a backtrace by entering `bt`.

In the call stack you should see `ocRunInit_ELF`. 
We can break here and print the value of the `ObjectCode` it's trying to run with:

```gdb
break ocRunInit_ELF
command
print *oc
end
```

I've found the faulting line to be `init_f(argc, argv, envv);` (inside `ocRunInit_ELF`), which on our version of GHC you can break at with `break rts/linker/Elf.c:2005`.

You can then "step inside" this call with `si` to explore the assembly instructions of the `.init` section of `x86_64cpuid.o` (in `libcrypto.a`) being run.

### Attribution

- [minirepo](https://github.com/lunaris/minirepo) for providing the nix derivation for building a statically linked Haskell toolchain.
- [postgrest](https://github.com/PostgREST/postgrest) for providing known "good" versions of `static-haskell-nix` and `nixpkgs`, with patches for broken things (e.g. `static-haskell-nix-ncurses.patch`).
