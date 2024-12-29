# kobo-emacs
<p align="center">
  <img alt="Cathedrals everywhere for those with eyes to see" src="./images/kobo_emacs_splash.jpeg" width="95%">
</p>

The Kobo Clara BW is a great platform to run emacs on via [efbpad](https://github.com/enthdegree/efbpad).
This project describes the stuff needed to get terminal emacs running on it natively. The process is unchallenging but fairly long. This guide is not complete and likely has typos. It should be followed by spirit instead of by letter!

Criticism and problems are included in [TODO.md](./TODO.md)

# Structure
It is unlikely emacs can or should be cross-compiled:
 - Its usual compile process involves running code on the target platform.
 - Once compiled, emacs has fairly far-reaching system dependencies

Our approach, then, will be to use a build machine to cross-compile a modern native toolchain for the Kobo plus some dependencies. Then we'll use these to compile emacs natively on the Kobo.

We want to touch as little as possible outside the exposed directory, `/mnt/onboard/`. Its filesystem has a limitation that is too difficult to live with for our purposes: no symlinks. So instead we'll construct our sysroot inside an ext3 fs `/mnt/onboard/localfs.img` and mount it to a folder `/mnt/onboard/.local`.

The broad steps are as follows, which are also nearly a table of contents for the rest of the document

 - On the build machine
   - Create toolchains
     - Create a cross-compile toolchain (build=build machine, host=build machine, target=kobo)
     - Create a canadian toolchain (build=build machine, hist=kobo, target=kobo)
   - Prepare a sysroot image
     - Create an empty fs image `localfs.img` and mount it someplace.
     - Copy the canadian toolchain into the sysroot.
     - Cross-compile dependencies into the sysroot.
     - Copy `localfs.img` into the kobo `/mnt/onboard/localfs.img`
 - On the kobo
   - Add conveniences to `/mnt/onboard/.efbpad_profile`
   - Adjust usbnet configs, if you're using those
   - Compile a few late dependencies, finally emacs
   - Win!

# On the build machine...
## Create toolchains
The main delicacy with these toolchains is they include their own shared glibc and other libraries.
Different versions of these libraries already exist on the Kobo in `/lib`, `/usr/lib`.
We have to be careful during compilation to link to the toolchain ones.

There's several ways of doing this.
I chose to always include the following parameters in CFLAGS:
```
-Wl,-rpath -Wl,$SYSROOT/lib:$SYSROOT/usr/lib \
-Wl,--dynamic-linker=$SYSROOT/lib/ld-linux-armhf.so.3
```

### Create a cross-compile toolchain
Clone NiLuJe's `koxtoolchain` repo and use `gen-tc.sh` to produce a kobo toolchain.
This will produce a toolchain in `~/x-tools/arm-kobo-linux-gnueabihf`

### Create a canadian toolchain
Clone and build `crosstool-ng`. Then make a native kobo toolchain at `~/x-tools/HOST_arm-kobo-linux-gnueabihf`:
```
export $PATH="$HOME/x-tools/arm-kobo-linux-gnueabihf/bin:$PATH"
cp [this repo]/kobo_cross_native.conf [ct-ng path]/.conf
./ct-ng menuconfig # See below
./ct-ng build
```

`kobo_cross_native.conf` is thinly dervied from koxtoolchain's crosstool-ng kobo config from the previous step. 
On my system the new config pointed to the kernel source kobo published here: https://github.com/kobolabs/Kobo-Reader/tree/master/hw/mt8113-libraC_vision
You need to either download this source and point the config to it or point the config to the latest preceding version from kernel.org. `ct-ng menuconfig` gives an interface for either of these.

## Prepare an initial sysroot
### Create an empty `localfs.img`
Set some mount point for the project, `export BUILD_SYSROOT=[...]`.
Create and mount an FS there:
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

Symlink all the toolchain bins in`$SYSROOT/opt/arm-kobo-linux-gnueabihf/bin` to un-prefixed versions in `$SYSROOT/bin`. 
(TODO: paste here the ash loops that do this).

At `opt/env.sh` write a script to help use the toolchain on the device:
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
source $SYSROOT/opt/env.sh
```

Continuing on the kobo, write a helloworld at `/mnt/onboard/helloworld.c`:
It should compile and run without errors:
```
$ gcc $CFLAGS ./helloworld.c -o helloworld
$ ./helloworld
Hello world!
```
I accessed the Kobo with usbnet ssh and scp.

### Cross-compile dependencies
Back on the build system, re-mount `localfs.img` to `$BUILD_SYSROOT`.
We need to set some environment variables to get our cross-compile toolchain to link properly and install the cross-compiled dependencies to `$BUILD_SYSROOT`.
I put these variables in a script `env.sh`:

```
export BUILD_SYSROOT=[same as above]
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

# On the Kobo
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

### usbnet configs
NiLuJe has helpfully provided a usbnet package containing busybox, tmux and ssh
[here](https://www.mobileread.com/forums/showthread.php?t=254214).
 - As described in the link, it creates several tunnels via udev rule (then `/usr/local/stuff/bin/stuff-daemons.sh`) which should be disabled with
```
touch /mnt/onboard/niluje/usbnet/etc/NO_TELNET # Disable inetd
touch /mnt/onboard/niluje/usbnet/etc/NO_SSH # Disable ssh
```
 - It includes a nice but unusual tmux config at `/mnt/onboard/.niluje/usbnet/etc/tmux.conf`. Overriding its options back to default is a mess. Instead I moved it to `tmux.conf.niluje` and put my own config in `$HOME/.tmux.conf`
 - The `ncurses` build scripts expect different argument handling from usbnet's applet `busybox install`. Correct this by replacing the `/usr/bin/install` symlink with a script:
```
#!/bin/sh
/usr/local/niluje/usbnet/bin/busybox install $@
```

## Native dependency compilation
On the kobo we run `source opt/env.sh` then `./configure [...]; make; make install`.

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
