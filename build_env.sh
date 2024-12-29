export BUILD_SYSROOT="$HOME/Projects/eink/kobo-emacs/mount"
export HOST_SYSROOT="/mnt/onboard/.local"
export BUILD_ARCH="$(gcc -dumpmachine)"
export HOST_ARCH="arm-kobo-linux-gnueabihf"
export TARGET_ARCH="arm-kobo-linux-gnueabihf"
export TC_PATH="$HOME/x-tools/$HOST_ARCH/bin"
export PATH="$TC_PATH:$PATH"
export CFLAGS=" \
--sysroot=$BUILD_SYSROOT \
-I$BUILD_SYSROOT/include -I$BUILD_SYSROOT/usr/include \
-L$BUILD_SYSROOT/lib -L$BUILD_SYSROOT/usr/lib \
-Wl,-rpath=$HOST_SYSROOT/lib:$HOST_SYSROOT/usr/lib \
-Wl,--dynamic-linker=$HOST_SYSROOT/lib/ld-linux-armhf.so.3 \
-O3 -ffast-math -fno-finite-math-only -march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=hard -mthumb -D_GLIBCXX_USE_CXX11_ABI=0 -pipe -fomit-frame-pointer -frename-registers -fweb \
"
export LDFLAGS=" \
--sysroot=$BUILD_SYSROOT \
-I$BUILD_SYSROOT/include -I$BUILD_SYSROOT/usr/include \
-L$BUILD_SYSROOT/lib -L$BUILD_SYSROOT/usr/lib \
-Wl,-rpath=$HOST_SYSROOT/lib:$HOST_SYSROOT/usr/lib \
-Wl,--dynamic-linker=$HOST_SYSROOT/lib/ld-linux-armhf.so.3 \
"
export CPPFLAGS="$CFLAGS"
echo "build=$BUILD_ARCH host=$HOST_ARCH target=$TARGET_ARCH toolchain env vars set"
