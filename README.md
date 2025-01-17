# kobo-emacs
<p align="center">
  <img alt="Cathedrals everywhere for those with eyes to see" src="./images/kobo_emacs_splash.jpeg" width="95%">
</p>

The Kobo Clara BW is a great platform for emacs via [efbpad](https://github.com/enthdegree/efbpad).
This project describes a build process for native terminal emacs on the Clara BW. It should extend directly to other devices too. 
vim, which relies on only a subset of emacs's dependencies, is included.
The build process is uncomplicated but fairly long. 
It is described in [BUILD.md](./BUILD.md).
It should be followed by spirit and not by letter!
Criticism and problems are included in [TODO.md](./TODO.md)

This is completely untested works-for-me-ware. Although this doesn't touch any non-user directories, you could still brick your device if you don't know what you're doing so be careful. 

# Prebuilt image
Instead of compiling everything you can try things out with a (maybe out-of-date) pre-built image from [here](https://mega.nz/folder/HdZlBQYA#4n_5f8hWzS3yp6b-KKa4hA):

 - Install `efbpad` and ensure it's working
 - From the zip move `onboard/.efbpad_profile` and `onboard/.localfs.img` onto `/mnt/onboard`. 
   The kobo's shipped `tar` seems to have issues unzipping large files there so they should be transferred to the device directly.
 - `emacs` should now be in the `PATH`.

You should still read [`BUILD.md`](./BUILD.md) for information on how to configure things.
