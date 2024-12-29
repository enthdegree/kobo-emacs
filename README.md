# kobo-emacs

The Kobo Clara HD is a great platform to run emacs on via [efbpad](https://github.com/enthdegree/efbpad).
This project describes the stuff needed to get emacs running on it natively. 
Though not challenging the process is fairly long.
This guide is not complete and can probably be improved.

Criticism and problems are included in [TODO.md](./TODO.md)

# Structure
It is unlikely emacs can or should be cross-compiled:
 - Its usual compile process involves running code on the target platform.
 - Once compiled, emacs has fairly far-reaching system dependencies
Our approach, then, will be to use a build machine to cross-compile a modern native toolchain for the Kobo plus some dependencies. Then we'll use these to compile emacs natively on the Kobo.

We want to touch as little as possible outside the exposed directory, `/mnt/onboard/`. Its filesystem has a limitation that is too difficult to live with for our purposes: no symlinks. So instead we'll construct our sysroot inside an ext3 fs `/mnt/onboard/localfs.img` and mount it to a folder `/mnt/onboard/.local`.

The broad steps are as follows, which are also nearly a table of contents for the rest of the document

 - Build machine
   - Create toolchains
     - Create a cross-compile toolchain (build=build machine, host=build machine, target=kobo)
     - Create a canadian toolchain (build=build machine, hist=kobo, target=kobo)
   - Prepare a sysroot image
     - Create an empty fs image `localfs.img` and mount it someplace.
     - Copy the canadian toolchain into the sysroot.
     - Cross-compile all the dependencies into the sysroot.
     - Copy `localfs.img` into the kobo `/mnt/onboard/localfs.img`
 - Kobo
   - Add conveniences to `/mnt/onboard/.efbpad_profile`
   - Adjust NiLuJe usbnet configs, if you're using those
   - Compile a few late dependencies, finally emacs
   - Win!

# Build Machine
## Create toolchains
The main delicacy with these toolchains is that they're going to ship their own shared glibc and other libraries.
Different versions of some of these libraries already exist on the Kobo in standard directories: `/lib`, `/usr/lib`, etc.
We have to be careful during dependency compilation to use the right linker, and point it to our local sysroot instead of `/`.
Otherwise nothing will run.

There's several ways of doing this.
I chose, somewhat a hack, to always include the following parameters in CFLAGS:
```
-Wl,-rpath -Wl,$SYSROOT/lib \
-Wl,-rpath -Wl,$SYSROOT/usr/lib \
-Wl,--dynamic-linker=$SYSROOT/lib/ld-linux-armhf.so.3
```

### Create a cross-compile toolchain
Clone NiLuJe's `koxtoolchain` repo and use `gen-tc.sh` to produce a kobo toolchain.
This will produce a toolchain in `~/x-tools/arm-kobo-linux-gnueabihf`

### Create a canadian toolchain
Clone and build `crosstool-ng`. Then make a toolchain to be run on the Kobo:
```
  export $PATH="$HOME/x-tools/arm-kobo-linux-gnueabihf/bin:$PATH"
  cp [this repo]/kobo_cross_native.conf [ct-ng path]/.conf
  ./ct-ng build
```
This should put a Kobo-native toolchain inside `$HOME/x-tools/HOST_arm-kobo-linux-gnueabihf`
`kobo_cross_native.conf` is thinly dervied from NiLuJe's kobo config in the previous step.

## Prepare an initial sysroot
### Create an empty `localfs.img`
```
fallocate -l 3G localfs.img
mkfs.ext3 localfs.img
mount ./localfs.img $BUILD_SYSROOT -o loop
```
We can't pick anything bigger than 4G because the file is going to live on a FAT partition.
Maybe there's workarounds (overlayfs?) but I don't have the need for them.

### Install the canadian toolchain to the sysroot
Copy the toolchain over:
```
mkdir $BUILD_SYSROOT/opt
cp -r ~/x-tools/HOST_arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf $BUILD_SYSROOT/opt
cp -r $BUILD_SYSROOT/opt/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/* $BUILD_SYSROOT
```

Inside `opt/` include an environment setup script `opt/env.sh` to help use the toolchain on the device:
```
# Set some useful environment variables for the kobo native toolchain (mainly `PATH`, `SYSROOT` and `CFLAGS`)

export SYSROOT=/mnt/onboard/.local
export HOST_TC=arm-kobo-linux-gnueabihf
export TC_PATH=$SYSROOT/opt/arm-kobo-linux-gnueabihf/bin
export PATH="$TC_PATH:$PATH"
export CFLAGS="--sysroot=$SYSROOT -O3 -ffast-math -fno-finite-math-only -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb -D_GLIBCXX_USE_CXX11_ABI=0 -pipe -fomit-frame-pointer -frename-registers -fweb -I$SYSROOT/include -I$SYSROOT/usr/include -L$SYSROOT/lib -L$SYSROOT/usr/lib -Wl,-rpath=$SYSROOT/lib:$SYSROOT/usr/lib -Wl,--dynamic-linker=$SYSROOT/lib/ld-linux-armhf.so.3"
export LDFLAGS="-I$SYSROOT/include -I$SYSROOT/usr/include -L$SYSROOT/lib -L$SYSROOT/usr/lib -Wl,-rpath=$SYSROOT/lib:$SYSROOT/usr/lib -Wl,--dynamic-linker=$SYSROOT/lib/ld-linux-armhf.so.3"
export CPPFLAGS="$CFLAGS"

echo "$HOST_TC native toolchain env vars set."
```

Next we will ensure this toolchain actually works on the kobo. On the build system, unmount `localfs.img` and move it to the kobo's `/mnt/onboard/.localfs.img`.
It is helpful to zip/unzip it to make the transfer faster.

```
cd /mnt/onboard
export SYSROOT=/mnt/onboard/.local
mkdir -p $SYSROOT
mount .localfs.img $SYSROOT -o loop
source /mnt/onboard/.local/opt/env.sh
```

Continuing on the kobo, write a helloworld at `/mnt/onboard/helloworld.c`:
You should be able to compile and run it without compile or linker errors:
```
$ arm-linux-gnueabihf-gcc $CFLAGS ./helloworld.c -o helloworld
$ ./helloworld
Hello world!
```

### Cross-compile dependencies
Back on the build system, re-mount `localfs.img` to `$BUILD_SYSROOT`.
We need to set some environment variables to get our cross-compile toolchain to link properly and install the cross-compiled dependencies to `$BUILD_SYSROOT`.
I put these variables in a script `env.sh`:

```
export BUILD_SYSROOT=
export BUILD_TC=arm-kobo-linux-gnueabihf
export TC_PATH=~/x-tools/$BUILD_TC/bin
export PATH="$TC_PATH:$PATH"

export HOST_SYSROOT=/mnt/onboard/.local
export CFLAGS="--sysroot=$BUILD_SYSROOT -O3 -ffast-math -fno-finite-math-only -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb -D_GLIBCXX_USE_CXX11_ABI=0 -pipe -fomit-frame-pointer -frename-registers -fweb -I$BUILD_SYSROOT/include -I$BUILD_SYSROOT/usr/include -L$BUILD_SYSROOT/lib -L$BUILD_SYSROOT/usr/lib -Wl,-rpath=$HOST_SYSROOT/lib:$HOST_SYSROOT/usr/lib -Wl,--dynamic-linker=$HOST_SYSROOT/lib/ld-linux-armhf.so.3"
export LDFLAGS="-$BUILD_SYSROOT/include -I$BUILD_SYSROOT/usr/include -L$BUILD_SYSROOT/lib -L$BUILD_SYSROOT/usr/lib -Wl,-rpath=$HOST_SYSROOT/lib:$HOST_SYSROOT/usr/lib -Wl,--dynamic-linker=$HOST_SYSROOT/lib/ld-linux-armhf.so.3"
export CPPFLAGS="$CFLAGS"

echo "$HOST_TC native toolchain env vars set."
```

All the cross-compiled dependencies use autotools.
I compiled and installed them as so:
```
cd [dependency source]
[special ./configure, provided below]
make
make install
```

...and here's the list of dependencies, in order, with comments and the ./configure args I used:
  - zlib-1.3.1.tar.gz
    ```
    ./configure --prefix="$BUILD_SYSROOT"
    ```
    
  - gmp-6.3.0.tar.xz
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC
    ```
    
  - libtasn1-4.19.0.tar.gz
    - replace `tests/Makefile` with the content:
    ```
    install:
    uninstall:
    ```
    -
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC \
    --without-libffi \
    --without-trust-paths \
    --disable-doc
    ```
    
  - nettle-3.10.tar.gz
    -
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    CC_FOR_BUILD="cc -O2" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC \
    --disable-documentation
    ```

  - libffi-3.4.6.tar.gz
    -
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC \
    --disable-docs
    ```

  - p11-kit-0.25.5.tar.xz
    -
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    CC_FOR_BUILD="cc $CFLAGS -O2" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC \
    LIBTASN1_CFLAGS=" " LIBTASN1_LIBS="-ltasn1" \
    --disable-trust-module
    ```
    
  - gnutls-3.7.11
    -
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC \
    NETTLE_CFLAGS=" " NETTLE_LIBS="-lnettle" \
    HOGWEED_CFLAGS=" " HOGWEED_LIBS="-lhogweed" \
    LIBTASN1_CFLAGS=" " LIBTASN1_LIBS="-ltasn1" \
    LIBZ_CFLAGS=" " LIBZ_LIBS="-lz" \
    P11_KIT_CFLAGS="-I$BUILD_SYSROOT/include/p11-kit-1" P11_KIT_LIBS="-lp11-kit" \
    GNUTLS_SYSTEM_PRIORITY_FILE="$BUILD_SYSROOT/etc/gnutls/config" \
    --with-included-unistring \
    --without-brotli \
    --without-zstd \
    --disable-doc
    ```
    
  - libxml2-v2.3.15
    -
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC \
    --without-python 
    ```
    
### Copy `localfs.img` to the kobo
Nothing special here.
Same as when `localfs.img` was moved over to test the native toolchain.

# Kobo
## Configuration

### efbpad profile
`/mnt/onboard/.efbpad_profile` can set up the new sysroot every time efbpad is started.
For example: 
```
#!/bin/sh

export LOCALFS="/mnt/onboard/.localfs.img"
export SYSROOT="/mnt/onboard/.local"
mkdir -p "$SYSROOT"
mountpoint -q $SYSROOT || 
export HOME="$SYSROOT/home/user"
mkdir -p "$HOME"
```

### NiLuJe usbnet configs
NiLuJe's usbnet package provides `ssh,tmux,busybox`.
It is a convenient way to avoid more tedious compilation, but it comes with some oddities:
 - sshd, telnetd, ftpd give root and fs access without auth. Configs in `/usr/local/niluje/usbnet/etc`
 - There is a nice and extensive but unusual tmux config at  `/mnt/onboard/.niluje/usbnet/etc/tmux.conf`.
  Overriding its options back to default is a mess.
  Instead I renamed it to `tmux.conf.niluje` and put my own config in `$HOME/.tmux.conf`
 - Compiling `ncurses` natively, the build scripts expect slightly different behavior from usbnet's provided `busybox install`.
 This can be corrected by replacing `/usr/bin/install` with a script:
 
 ```
 #!/bin/bash
 /usr/local/niluje/usbnet/bin/busybox install $@
 ```

## Native compilation
Finally on the Kobo we can leverage our host toolchain.
Similarly run `source opt/env.sh` then `./configure [...]; make; make install`.

  - ncurses-6.3
    - For this we need a `/usr/bin/install` that works... see the NiLuJe usbnet config comment above.
    -
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build=$BUILD_TC --host=$HOST_TC --target=$HOST_TC \
    --without-manpage \
    --with-shared \
    --with-termlib
    ```

 - perl-5.38.2
   - We need perl because the emacs compile process calls a perl program, texinfo.
   - We can't build perl-5.40.0 (current stable as of 12/28/2024) because of locale issues, possibly the one mentioned in [TODO.md](./TODO.md).
   -
   ```
   ./Configure -des -Dprefix=$BUILD_SYSROOT -Dcc="cc $CFLAGS" -A ccflags="$CFLAGS"
   ```
   
 - texinfo-7.2
   -
   ```	
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
   ```

 - emacs-29.4
   -
   ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    LIBGNUTLS_CFLAGS=" " LIBGNUTLS_LIBS="-lgnutls" \
    LIBXML2_CFLAGS="-I$SYSROOT/include/libxml2" LIBXML2_LIBS="-lxml2" \
    --with-xml2 \
    --with-zlib \
    --without-x \
    --without-sound \
    --without-xpm \
    --without-jpeg \
    --without-tiff \
    --without-gif \
    --without-png \
    --without-rsvg \
    --without-imagemagick \
    --without-xft \
    --without-libotf \
    --without-m17n-flt \
    --without-xaw3d \
    --without-toolkit-scroll-bars \
    --without-gpm \
    --without-dbus \
    --without-gconf \
    --without-gsettings \
    --without-compress-install
    ```
