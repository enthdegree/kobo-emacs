 - The current `kobo_cross_native.conf` produces utilities in `sysroot/usr/bin` that reference `/` instead of `$SYSROOT`. 
   Adding `-Wl,-rpath=`, `-Wl,--dynamic-linker=`, etc to the ct-ng option `CT_GLIBC_EXTRA_CFLAGS` makes the build fail. 
   The bad `/usr/bin/locale` causes problems for programs like `bash` unless started safely (in the release image see `$SYSROOT/bin/bash_helper.sh`)
 - Rather than `./configure` with a bunch of hand-written `[LIBRARY]_CFLAGS= [LIBRARY]_LIBS=` it may be more maintainable to compile perl earlier, then compile and use `pkg-config`
 - We currently rely on shipped autoconf scripts instead of using autotools to generate them.
 - Add links to the exact sources used.
 - Is it necessary to include linker options in `LDFLAGS`?
 - Is there a low-effort way to automate all this? Could the compilation be performed natively in a VM?
 
