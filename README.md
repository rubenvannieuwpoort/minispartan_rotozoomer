# miniSpartan6+ rotozoomer
A rotozoomer for the miniSpartan 6+, written in VHDL, and using [Mike Fields HDMI signal generation](https://github.com/scarabhardware/miniSpartan6-plus).

This rotates a 256x256 image on the HDMI out of the miniSpartan 6+ (it doesn't zoom yet - so technically it shouldn't be called a rotozoomer... but hey, who cares).
https://www.youtube.com/watch?v=n5g-sjUP02Y
[![Video of the result](https://img.youtube.com/vi/n5g-sjUP02Y/hqdefault.jpg)](https://www.youtube.com/watch?v=n5g-sjUP02Y)

## Getting started

To get the rotozoomer working:
  - Doubleclixk dvid_serdes.xise to open the ISE Project Navigator. If a prompt appears, click 'create'.
  - In the 'files' pane, doubleblick tmds_out_fifo.xco. A wizard should appear (this might take a while).
  - Click generate and choose 'yes' at the prompt. Wait until the process is finished.
  - In the design pane, make sure that the radio button 'implementation' is selected, and that the dvid_serdes file is highlighted. Now click on 'Generate Programming File' in the process pane.
  - Wait until generating the programming file has finished.
  - Connect the miniSpartan6+ to your computer via USB and run
    xc3sprog -c ftdi init.bit
    xc3sprog -c ftdi -I path/to/dvid_serdes.bit
  - Disconnect the miniSpartan6+ from your computer.
  - Connect it to an HDMI monitor (a TV with HDMI probably won't work) and power it up.
  - Watch the rotozoomer.
  - Think about what you could have done in the 20 minutes of your life that you spent to get this thing working.

## Chroma subsampling

The image used is a 256x256 24bpp image of Lena Dunhum (a famous image that is often used as a test picture for image processing). Uncompressed, a 256x256 24bpp image takes 256 * 256 * 3 bytes or 192 KB. The Spartan 6 LX25 has just 117 KB of distributed RAM available. So, compression is needed. This is tricky since decompression needs to happen almost instantly, on-the-fly, and not in a predetermined order. A lossy compression scheme is used, which is very similar to a YUV encoding.

First, the RGB channels are split into three new channels, which I will call Y, U, and V (even though they are *not* the same Y, U, and V in the YUV color space - but the idea is similar):
    
    Y = ( R + G + B) / 3
    U = (2R - G - B) / 3
    V = (-R +2G - B) / 3

Now, the values of the R, G, and B channels can be retrieved by the inverse transformation:
    
    R = Y + U
    G = Y + V
    B = Y - U - V

The U and V channel need to be rescaled to fit into a single byte:
    
    U_enc = (U / 340 * 255) + 127
    V_enc = (V / 340 * 255) + 127

Of course the inverse transformation needs to be done on the FPGA to compute the U and V values:
    
    U = (U_enc - 127) * 340 / 255
    V = (V_enc - 127) * 340 / 255

(Actually, I clamp the values to be in the range 0-255. There might be a way to avoid the need for clamping, but I haven't really analyzed the problem - it probably has to do with round-off errors.)

Some color information is lost in the rescaling. This is not too big a deal: The Y channel has the grayscale information of the picture, and is most important. In fact, the Y channel is the only channel that is put in the RAM of the FPGA completely. The U and V channels are *subsampled*. Instead of storing a 256x256 array of bytes, a 128x128 array is used, which used only a quarter of the memory (for those two channels). Again, since most of the information is in the Y channel, the compressed image is almost indistinguishable from the original.

This technique of subsampling the channels in which the 'color' information (as opposed to the grayscale information) is stored, is called *chroma subsampling*.

As a result of chroma subsampling, only 256 * 256 + 128 * 128 * 2 bytes or 96 KB of RAM is needed to store the picture (instead of the 256 * 256 * 3 = 192 KB we would need for storing the whole image uncompressed). The Spartan 6 LX25 has 117 KB of distributed RAM, which means we have some room left for lookup tables for the sine and the cosine :)

# TODO
1. Refactor and comment code
2. Implement zooming
3. Document file contents

# Bugs
1. On the left and top edge, the texture wraps around by a single pixel.
