# SDVideo
A set of tools by Samuel Devulder that converts videos for the [SDDrive](http://dcmoto.free.fr/bricolage/sddrive/index.html) hardware by D.Coulom. 

[![](http://dcmoto.free.fr/programmes/sddrive-medley3/c1.jpg)](http://dcmoto.free.fr/bricolage/sddrive/index.html)

There are actually two programs which can be used:
* [`conv_sd.lua`](#user-content-conv_sdlua) ([usage](#user-content-usage))
* [`sdvideo.lua`](#user-content-sdvideolua) ([usage](#user-content-usage-1))

# conv_sd.lua

This is the first one that I made back in 2018.

## History

This converter was originally discussed in the "[[Thomson] SDDrive Vidéo](https://forum.system-cfg.com/viewtopic.php?p=141650#p141650)" thread of system-cfg's forum. The idea was to 
* show lots of colors on the TO/MO machines in spite of color-clashes.
* be fast enough to be enjoyable

To achieve this, a pseudo-graphics mode of 80x50 pseudo-pixels is used. Each pseudopixel can take one color out of a 4³=64 colors palette. This mode was the one I used in the "[Oh la belle bleue!](http://dcmoto.free.fr/programmes/oh-la-belle-bleue/index.html)" demo by Puls ([pouet.net](https://www.pouet.net/prod.php?which=57343)), and was expected to be able to produce good looking animations.

![](https://www.cjoint.com/doc/15_06/EFctmoAbHxr_Kylie%20Minogue%20-%20Spinning%20Around.gif) ![](http://www.cjoint.com/doc/15_06/EFctpDY8IJr_Star%20Wars%20A%20New%20Hope%201977%20Trailer.gif)

Each pixel needs 6 bits, meaning that one can pack 4 pixels in only 3 bytes. As a result, the [ASM player](asm/player.ass) outputs one audio sample every 199µs (5.025 khz) which is pretting good considering the bandwidth of SDDrive.

## Usage
	
	[FPS=<N>] [GRAY=<0/1>] tools/luajit conv_sd.lua <video-files>
	
`GRAY=1` creates a grayscale picture.

`FPS=<N>` allow choosing a proper FPS for the video. Don't take it too hight otherwise the converter will reduce the image size to keep up with the FPS you choose. A negative value will reduce the FPs too keep a full-screen image. The default value of 11 fps is a good compromise.

`<Video-files>` can be any video file (MP4/AVI/MOV/MKV) you wish to convert or even a YouTube or Vimeo or any other [youtube-dl](https://youtube-dl.org/) compatible URL. YouTube playlists are treated as the set of all the videos in the playlist.

*Note*: URL videos are fetched from internet by youtube-dl and stored in the current folder with a MKV extension. Ensure you have write-access to that folder before you use this feature.

## Example

One can find an example of video made using this tool in the [Demonstration section](http://dcmoto.free.fr/programmes/sddrive-bad-apple/index.html) of the DCMOTO web site.

![](http://dcmoto.free.fr/programmes/sddrive-bad-apple/01.png) ![](http://dcmoto.free.fr/programmes/sddrive-bad-apple/02.png) ![](http://dcmoto.free.fr/programmes/sddrive-bad-apple/03.png) ![](http://dcmoto.free.fr/programmes/sddrive-bad-apple/04.png)

# sdvideo.lua

This is the second converter/player that I made in 2019 in an attempt to improve video quality and playback speed if possible.

## History

`conv_sd.lua` uses a 80x50 pixel screen which is nice, but the thomson can have more finer graphics.

By the [end of 2018](https://forum.system-cfg.com/viewtopic.php?p=144980#p144980) I had an idea for another type of screen rendering which quadruples the vertical resolution resuling in pretty tempting gif mockups using the standard palette:

![](https://www.cjoint.com/doc/18_11/HKnxpa65Pvr_Kylie-Minogue---Spinning-Around.gif) ![](https://www.cjoint.com/doc/18_11/HKnxkQwKgkr_MMD-Bad-Apple-Now-in-3D-with-more-Color-.gif) 

as well as modified palettes allowing to create even more pseudo-colors:

![](https://www.cjoint.com/doc/18_11/HKpxISZ5oir_Creedence-Clearwater-Revival---Down-on-the-Corner-1969.gif) ![](https://www.cjoint.com/doc/18_11/HKpxKJDkbLr_Custom-Knight-rider-intro-1---Classic.gif)
 
The issue was then to checkout if the bandwidth of SDDrive was able to cope with that many color changes for each frame. The solution that I found is to 
* automatically reduce screen size (hence less color changes) and
* use a kind of interlaced mode (changed one line out of N at each frame) 
which allows playing most video between 11 to 13 frames per second which is pretty astonishing for the poor mc6809@1mhz running the Thomson's machines.

## Usage

	[FPS=<N>] [MODE=<DESC>] [COLOR=0xPQ] tools/luajit sdvideo.lua <video-files>

`<Video-files>` can be any video file (MP4/AVI/MOV/MKV) you wish to convert or even a YouTube or Vimeo or any other [youtube-dl](https://youtube-dl.org/) compatible URL. YouTube playlists are treated as the set of all the videos in the playlist.

*Note*: URL videos are fetched from internet by youtube-dl and stored in the current folder with a MKV extension. Ensure you have write-access to that folder before you use this feature.
	
`FPS=<N>` allow choosing a proper FPS for the video. Don't take it too high otherwise the converter will reduce the image size to keep up with the FPS you choose. A negative value will reduce the FPs too keep a full-screen image. The default value of 11 fps is a good compromise. A value bigger than 31 will convert fullscreen image at 30fps, but consecutive images can be merged together resuling in mlore blurry pictures from time to time.
	
`MODE=<DESC>` is actually a numerical parameter indicating the type of output to produce. To every machine is able do play each mode, but high-end machines (MO6, TO8, TO9+) can play all. Default mode (if omitted) is 7 which usually gives colorful result without sacrificing too much of the resolution.

Here is a table summing this up:
Mode| Resolution | Colors | TO7 | MO5 | TO770 | MO6 | TO8(D), TO9+ | Comment
----|------------|--------|-----|-----|-------|-----|----|------
EDGE| 320x200    | 2      |  X  |  X  |   X   |  X  |  X |  Monochromatic (edge detection)
OTSU| 320x200    | 2      |  X  |  X  |   X   |  X  |  X |  Monochromatic (automatic threshold)
BAYR| 320x200    | 2      |  X  |  X  |   X   |  X  |  X |  Monochromatic (bayer 8x8 dithering, 64 levels)
DITH| 320x200    | 2      |  X  |  X  |   X   |  X  |  X |  Monochromatic (half-8x8 bayer, 32 levels)
VACD| 320x200    | 2      |  X  |  X  |   X   |  X  |  X |  Monochromatic (void and cluster dithering, 64 levels
HLFT| 320x200    | 2      |  X  |  X  |   X   |  X  |  X |  Monochromatic (halftone dithering, 32 levels²)
BM59| 160x200    | 4      |     |     |       |  X  |  X |  Grayscale (special bm4 mode with 2x1 pixels)
RGB2| 320x66     | 8*     |  X  |  X  |   X   |  X  |  X | One of R/G/B color on each line so 66 is actually 200/3
C345|  80x100    | 60*    |     |     |       |  X  | X  | Specific palette. R/G B one two separate rows. 16 Real colors (3*4 + 5 - 1) but 60 virtual (3*4*5).
RGB6|  80x66     | 216*   |     |     |       |  X  | X  | One of R/G/B component (6 levels each) set at every pixel, creating 6*6*6=216 virtual colors.
RGB4| 80x200     | 68*    |     |     |       |  X  | X  | 4 levels of R/G/B + 4 levels of gray.
RGB5| 80x200     | 128*   |     |     |       |  X  | X  | 5 levels of R/G/B + 3 saturated mixed colors.
CR16| 80x200     | 16     |     |     |       |  X  | X  | Colors are created from a color-reduction algorithm running over all the frames of the video. *Slow process!*

**Notice:**
* A start (*) after the number of color indicates that this is indeed the number of virtual colors. These are colors that your eyes build up when it merges adjacent ones.

`COLOR=0xPQ` allow changing the forground (P) and the background (Q) color for monochromatic modes. Default is white on black.

## How to view SDVideo files in DCMOTO ?

If you don't have the SDDrive hardware you can still use the [DCMOTO emulator](http://dcmoto.free.fr/emulateur/index.html) to view the file.

In order to do so, ensure you have selected the SDDRIVE external controller in the "options" menu:
![](http://forum.system-cfg.com/download/file.php?id=19604)

Then in the "Removable devices" menu and panel select the SD file you want to see, and ensure that you have checked the "SDDRIVE interface", and not the "Floppy drive" (which is otherwise the default):
![](http://forum.system-cfg.com/download/file.php?id=19605)

Then simply boot your virtual Thomson machine to any "basic" you want (the provided SD file is auto-boot). You should now see the SDDRIVE boot menu allowing to select the only visible SD file (_Notice_: the file name might be truncated):
![](http://forum.system-cfg.com/download/file.php?id=19606)

Then relax and enjoy the video.


## Examples

There is an `examples/` folder in the distributon. You will find various sub-folders within it, each one containing a `runme` script that you can run to populate that folder with an example.

Alternatively you can find an example of video made using this tool in the [Demonstration section](http://dcmoto.free.fr/programmes/sddrive-medley3/index.html) of the DCMOTO web site.

![](http://dcmoto.free.fr/programmes/sddrive-medley3/02.png) ![](http://dcmoto.free.fr/programmes/sddrive-medley3/04.png) ![](http://dcmoto.free.fr/programmes/sddrive-medley3/09.png) ![](http://dcmoto.free.fr/programmes/sddrive-medley3/10.png) ![](http://dcmoto.free.fr/programmes/sddrive-medley3/11.png) ![](http://dcmoto.free.fr/programmes/sddrive-medley3/12.png)

You can also find some of my tests on Youtube:

Mode | Converted video (click to view on YouTube)
----|----
MODE=C345 | [![MODE=C345](https://img.youtube.com/vi/sKI7Ro2MoOs/0.jpg)](https://www.youtube.com/watch?v=sKI7Ro2MoOs) 
MODE=RGB4 | [![MODE=RGB4](https://img.youtube.com/vi/ZnYCgsjjhs4/0.jpg)](https://www.youtube.com/watch?v=ZnYCgsjjhs4) 
MODE=RGB5 | [![MODE=RGB5](https://img.youtube.com/vi/ECxBXCi1PeU/0.jpg)](https://www.youtube.com/watch?v=ECxBXCi1PeU) 

Here is how an MO6 machine can playback a well known [PC-demo](https://www.pouet.net/prod.php?which=63) of 1993:

[![](https://img.youtube.com/vi/3PXrQAOnrnc/0.jpg)](https://www.youtube.com/watch?v=3PXrQAOnrnc)

or a TO8 replaying with MODE=C345 a [famous game](https://en.wikipedia.org/wiki/Another_World_(video_game)) intro:

[![](https://img.youtube.com/vi/jIY-GlHY2e4/0.jpg)](https://www.youtube.com/watch?v=jIY-GlHY2e4)

or its [remake](https://www.youtube.com/watch?v=1Nlmje-rUQs):

[![](https://img.youtube.com/vi/jrnNccdIbkA/0.jpg)](https://www.youtube.com/watch?v=jrnNccdIbkA)


