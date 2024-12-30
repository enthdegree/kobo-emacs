 - The current `kobo_cross_native.conf` produces utilities in `arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/usr/bin` that reference `/` instead of `$SYSROOT`. 
   One affected binary, `$SYSROOT/usr/bin/locale`, causes problems for programs like `bash` unless started safely. See [`$SYSROOT/bin/bash_helper.sh`](./scripts/bash_helper.sh).
 - Rather than `./configure` with a bunch of hand-written `[LIBRARY]_CFLAGS= [LIBRARY]_LIBS=` it may be more maintainable to compile perl earlier, then compile and use `pkg-config`
 - We currently rely on shipped autoconf scripts instead of using autotools to generate them.
 - Add links to the exact sources used.
 - Is it necessary to include linker options in `LDFLAGS`?
 - Is there a low-effort way to automate all this? Could the compilation be performed natively in a VM?
 
