# kobo-emacs
<p align="center">
  <img alt="Cathedrals everywhere for those with eyes to see" src="./images/kobo_emacs_splash.jpeg" width="95%">
</p>

The Kobo Clara BW is a great platform for emacs via [efbpad](https://github.com/enthdegree/efbpad).
This project describes the process to get terminal emacs running on it natively.

The process is unchallenging but fairly involved. 
It is described in [BUILD.md](./BUILD.md) which is not complete and likely has typos.
It should be followed by spirit and not by letter!
Criticism and problems are included in [TODO.md](./TODO.md)

# Prebuilt image
Instead of compiling everything you can try things out with a (maybe out-of-date) pre-built image from [here](https://mega.nz/folder/HdZlBQYA#4n_5f8hWzS3yp6b-KKa4hA):

 - Install `efbpad` and ensure it's working
 - From the image move `onboard/.efbpad_config` and `onboard/.localfs.img` onto `/mnt/onboard`

You should still read `BUILD.md` for information on how to configure things.