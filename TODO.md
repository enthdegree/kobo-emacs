 - Add links to the exact sources used.
 - Split the script snippets out into their own files.
 - The current `kobo_cross_native.conf` produces utilities in `sysroot/usr/bin` linked against `/` instead of `$SYSROOT`. Adding `-Wl,-rpath=`, `-Wl,--dynamic-linker=`, etc to the ct-ng option `CT_GLIBC_EXTRA_CFLAGS` makes the build fail. The bad `/usr/bin/locale` causes problems for programs like `bash` unless called in a safe environment (`unset LC_ALL; unset LANG;`)
 - Rather than `./configure` with a bunch of hand-written `[LIBRARY]_CFLAGS= [LIBRARY]_LIBS=` it may be more maintainable to compile perl earlier, then compile and use `pkg-config`
 - Is it necessary to include linker options in `LDFLAGS`?
 - Is there a low-effort way to automate all this? Could the compilation be performed natively in a VM?
 
