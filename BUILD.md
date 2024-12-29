# Build process overview
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

# On the build machine...
## Create toolchains
The main delicacy with these toolchains is they include their own shared glibc and other libraries.
Different versions of these libraries already exist on the Kobo in `/lib`, `/usr/lib`.
We have to be careful during compilation to link to the toolchain ones.
There's several ways of doing this.
Here I have chosen to always pass these CFLAGS:
```
-Wl,-rpath -Wl,$SYSROOT/lib:$SYSROOT/usr/lib \
-Wl,--dynamic-linker=$SYSROOT/lib/ld-linux-armhf.so.3
```

### Create a cross-compile toolchain
Clone the [`koxtoolchain` repo](https://github.com/koreader/koxtoolchain) and use `gen-tc.sh` to produce a kobo toolchain.
This will produce a cross-compile toolchain somewhere, `~/x-tools/arm-kobo-linux-gnueabihf` on my system.
Update variables in `build_env.sh`, in particular:
 - `BUILD_SYSROOT`: Mountpoint for the localfs image we're going to create.
 - `TC_PATH`: The cross-compile toolchain binary folder, containing, e.g., `arm-kobo-linux-gnueabihf-gcc`.

### Create a canadian toolchain
Clone and build `crosstool-ng`. 
Then make a native kobo toolchain at `~/x-tools/HOST_arm-kobo-linux-gnueabihf`:
```
source build_env.sh
cp kobo_cross_native.conf [ct-ng working dir]/.conf
cd [ct-ng working dir]
./ct-ng menuconfig # See below
./ct-ng build
```

`kobo_cross_native.conf` is thinly dervied from koxtoolchain's crosstool-ng kobo config from the previous step. 
On my system the new config pointed to the kernel source kobo published [here](https://github.com/kobolabs/Kobo-Reader/tree/master/hw/mt8113-libraC_vision).
You must either do the same or point the config to the latest preceding version from kernel.org. 
`ct-ng menuconfig` gives an interface for either of these.

## Prepare an initial sysroot
### Create an empty `localfs.img`
Create and mount an FS at `$BUILD_SYSROOT`:
```
fallocate -l 3G localfs.img
mkfs.ext3 localfs.img
mount ./localfs.img $BUILD_SYSROOT -o loop
```
We can't pick anything bigger than 4G because the file is going to live on a FAT partition.
If you really need it there may be workarounds (overlayfs?).

### Install the canadian toolchain to the sysroot
Copy the toolchain into the image:
```
mkdir $BUILD_SYSROOT/opt
cp -r ~/x-tools/HOST_arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf $BUILD_SYSROOT/opt
cp -r $BUILD_SYSROOT/opt/arm-kobo-linux-gnueabihf/arm-kobo-linux-gnueabihf/sysroot/* $BUILD_SYSROOT
```

Symlink all the toolchain bins in`$SYSROOT/opt/arm-kobo-linux-gnueabihf/bin` to un-prefixed versions in `$SYSROOT/bin`. 
(TODO: paste here the ash loops that do this).

Include [`host_env.sh`](./host_env.sh) in `opt/arm-kobo-linux-gnueabihf/env.sh` to help use the toolchain on the device.

Next we will ensure this toolchain actually works on the kobo. 
On the build system, unmount `localfs.img` and move it to the Kobo's `/mnt/onboard/.localfs.img`.
It is helpful to zip/unzip it to make the transfer faster.

```
cd /mnt/onboard
export SYSROOT=/mnt/onboard/.local
mkdir -p $SYSROOT
mount .localfs.img $SYSROOT -o loop
```

Continuing on the Kobo, write a helloworld at `/mnt/onboard/helloworld.c`:
It should compile and run without errors:
```
$ source $SYSROOT/opt/env.sh
$ gcc $CFLAGS ./helloworld.c -o helloworld
$ ./helloworld
Hello world!
```
I accessed the Kobo with usbnet ssh and scp.

### Cross-compile dependencies
Back on the build system, ensure `source build_env.sh` has been run and re-mount `localfs.img` to `$BUILD_SYSROOT`.
Most of the cross-compiled dependencies use autotools.
That is, I compiled and installed each dependency as so:
```
cd [dependency source]
[special ./configure, provided below]
make
make install
```

Here's the list of dependencies, in order, with comments and the ./configure args I used:
  - zlib-1.3.1.tar.gz
    ```
    ./configure --prefix="$BUILD_SYSROOT"
    ```
    
  - gmp-6.3.0.tar.xz
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build="$BUILD_ARCH" --host="$HOST_ARCH" --target="$TARGET_ARCH"
    ```
    
  - libtasn1-4.19.0.tar.gz
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build="$BUILD_ARCH" --host="$HOST_ARCH" --target="$TARGET_ARCH" \
    --without-libffi \
    --without-trust-paths \
    --disable-doc
    ```
    Then replace `tests/Makefile` with the content:
    ```
    install:
    uninstall:
    ```
    
  - nettle-3.10.tar.gz
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    CC_FOR_BUILD="cc -O2" \
    --build="$BUILD_ARCH" --host="$HOST_ARCH" --target="$TARGET_ARCH" \
    --disable-documentation
    ```

  - libffi-3.4.6.tar.gz
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build="$BUILD_ARCH" --host="$HOST_ARCH" --target="$TARGET_ARCH" \
    --disable-docs
    ```

  - p11-kit-0.25.5.tar.xz
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    CC_FOR_BUILD="cc $CFLAGS -O2" \
    --build="$BUILD_ARCH" --host="$HOST_ARCH" --target="$TARGET_ARCH" \
    LIBTASN1_CFLAGS=" " LIBTASN1_LIBS="-ltasn1" \
    --disable-trust-module
    ```
    
  - gnutls-3.7.11
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build="$BUILD_ARCH" --host="$HOST_ARCH" --target="$TARGET_ARCH" \
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
    ```
    ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --build="$BUILD_ARCH" --host="$HOST_ARCH" --target="$TARGET_ARCH" \
    --without-python 
    ```
	
  - (optional) coreutils-9.5
  ```
  ./configure --prefix="$BUILD_SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
  --build="$BUILD_ARCH" --host="$HOST_ARCH" --target=TARGET_ARCH
  ```
    
### Copy `localfs.img` to the Kobo
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
NiLuJe provided a usbnet package containing busybox, tmux and ssh
[here](https://www.mobileread.com/forums/showthread.php?t=254214).
 - As described in the link, it creates several tunnels via udev rule (then `/usr/local/stuff/bin/stuff-daemons.sh`) which should be disabled with
```
touch /mnt/onboard/niluje/usbnet/etc/NO_TELNET # Disable inetd
touch /mnt/onboard/niluje/usbnet/etc/NO_SSH # Disable ssh
```
 - It includes a nice but unusual tmux config at `/mnt/onboard/.niluje/usbnet/etc/tmux.conf`. Overriding its options back to default is a mess. Instead I moved it to `tmux.conf.niluje` and put my own config in `$HOME/.tmux.conf`
 - The `ncurses` build scripts expect different argument handling from usbnet's applet `busybox install`. Correct this by replacing the symlink `/usr/bin/install` with a script:
```
#!/bin/sh
/usr/local/niluje/usbnet/bin/busybox install $@
```

## Native dependency compilation
On the Kobo we run `source opt/env.sh` then `./configure [...]; make; make install`.

  - ncurses-6.3
    - For this we need a `/usr/bin/install` that works... see the usbnet config comment above.
    ```
    ./configure --prefix="$SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    --without-manpage \
    --with-shared \
    --with-termlib
    ```

 - perl-5.38.2
   - We need perl because the emacs compile process calls the perl utility `texinfo`.
   - We can't build perl-5.40.0 (current stable as of 12/28/2024) because of locale issues, see [TODO.md](./TODO.md).
   ```
   ./Configure -des -Dprefix=$SYSROOT -Dcc="cc $CFLAGS" -A ccflags="$CFLAGS"
   ```
   
 - texinfo-7.2
   ```	
    ./configure --prefix="$SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
   ```

 - emacs-29.4
   ```
    ./configure --prefix="$SYSROOT" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
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
