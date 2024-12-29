# kobo-emacs
<p align="center">
  <img alt="Cathedrals everywhere for those with eyes to see" src="./images/kobo_emacs_splash.jpeg" width="95%">
</p>

The Kobo Clara BW is a great platform for emacs via [efbpad](https://github.com/enthdegree/efbpad).
This project describes the stuff needed to get terminal emacs running on it natively. 
The process is unchallenging but fairly long. 
This guide is not complete and likely has typos: it should be followed by spirit and not by letter!

# Approach
It is unlikely emacs can or should be cross-compiled:
 - Its usual compile process involves running code on the target platform.
 - Once compiled, emacs has fairly far-reaching system dependencies

Our approach, then, is to use a build machine to cross-compile a modern native toolchain for the Kobo, and also what dependencies we can. 
Then we use these to compile emacs natively on the Kobo.

We want to touch as little as possible outside the exposed directory, `/mnt/onboard/`. Its filesystem has a limitation that is too difficult to live with for our purposes: no symlinks. So instead we'll construct our sysroot inside an ext3 fs `/mnt/onboard/localfs.img` with all our binaries and dependencies in it and mount it to a folder `/mnt/onboard/.local`.
The broad steps are as follows, which are also nearly a table of contents for the more detailed [BUILD.md](./BUILD.md):

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
   - Start `efbpad` and use emacs!

Criticism and problems are included in [TODO.md](./TODO.md)
