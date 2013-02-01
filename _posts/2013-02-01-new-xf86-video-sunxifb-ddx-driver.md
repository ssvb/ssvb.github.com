---
layout: post
title: New xf86-video-sunxifb DDX driver for Xorg
---

{{ page.title }}
================

## A short introduction

[Allwinner A10/A13 SoC](http://en.wikipedia.org/wiki/Allwinner_A1X) is very interesting
because it is used in a lot of very affordable electronic devices from China, such as USB
dongles, media boxes, tablets, netbooks and even the [cubieboard.org development board](http://cubieboard.org/).
Because of a very competitive price, these devices make a good alternative for [Raspberry Pi](http://en.wikipedia.org/wiki/Raspberry_Pi).

One rather unique and somewhat attractive feature is that this platform does
not have a corporate backing and does not suffer from "too many cooks"
problem :-) All the hardware adaptation support is provided by the
community at [http://linux-sunxi.org/](linux-sunxi.org), where the people
are currently trying to clean up the kernel and fix numerous bugs.

## 3D graphics performance

Allwinner A10 uses a single-core [Mali-400 GPU](http://en.wikipedia.org/wiki/Mali_%28GPU%29) running
at 320MHz, which provides OpenGL ES 2.0 acceleration. The OpenGL ES implementation itself relies
on the [proprietary closed source libMali.so library](http://forums.arm.com/index.php?/topic/16259-how-can-i-upgrade-mali-device-driver/page__p__39744#entry39744).
But the integration with the X server is provided by the [open source reference driver xf86-video-mali](http://malideveloper.arm.com/develop-for-mali/drivers/open-source-mali-gpus-linux-exadri2-and-x11-display-drivers/).
Many users might assume that it's a ready-to-use complete solution and a natural choice for their devices.
However this is not quite true. The performance of the system is also largely dependent on the
optimal integration with the display controller hardware, because Mali itself can only render
3D images to memory buffers. Here is a quote from the readme file included in xf86-video-mali:
{% highlight text %}
xf86-video-mali" is provided as a basis for creating your own X Display
Driver. It requires a recent version of the xorg-server, as well as a
successfull integration of UMP with your display device driver.
{% endhighlight text %}
As such, a more complete implementation of X11 driver is needed, and my attempt to develop one
(based on xf86-video-fbdev) is available here:
[xf86-video-sunxifb](https://github.com/ssvb/xf86-video-sunxifb). Below is the screenshot
of it running on [Mele A2000 TV box](https://plus.google.com/u/0/113201731981878354205/posts/daJfhBRvWjk)

<a href="/images/2013-02-01-mali400-acceleration.png"><img src ="/images/2013-02-01-mali400-acceleration-lowres.png" alt="2013-02-01-mali400-acceleration.png"</img></a>

The glmark2 2012.12 scores with 1280x720-32@60Hz monitor look like this:

<table border=1 style='border-collapse: collapse; empty-cells: show; font-family: arial; font-size: small; white-space: nowrap; background: #F0F0F0;'>
<tr><th>X11 DDX driver<th>Fullscreen (1280x720)<th>Window (800x600)<th>Partially obscured window (800x600)</tr>
<tr><td>xf86-video-mali r3p0<td>38<td>65<td>66</tr>
<tr><td>xf86-video-sunxifb-0.2.0<td>115<td>165<td>50</tr>
</table>

As expected from the implementation which is aware of the hardware overlays
supported by the display controller, the performance of xf86-video-sunxifb
with fullscreen and fully visible windows is significantly better
than xf86-video-mali. Though rendering to partially obscured window
currently goes through the fallback path involving many memory copy
operations, and the overhead of these memory copy operations is even
higher than for xf86-video-mali (mostly because of the use of
shadow framebuffer).

## 2D graphics performance

Now this is the most interesting part, because surprisingly 2D tends
to be rather problematic for many drivers. Below is the chart based
on the results from [cairo-perf-trace running trimmed-cairo-traces](https://github.com/ssvb/trimmed-cairo-traces).

<a href="/images/2013-02-01-cairo-perf-chart-sunxifb.png"><img src ="/images/2013-02-01-cairo-perf-chart-sunxifb-lowres.png" alt="2013-02-01-cairo-perf-chart-sunxifb.png"</img></a>

Looks xf86-video-sunxifb is implementing some great performance optimizations?
I wish this was the case, but in fact it is basically just the functionality entirely
provided by the original xf86-video-fbdev code, which was used as
the base for xf86-video-sunxifb. It merely tries not to get in the
way and just lets ARM NEON code from [pixman](http://www.pixman.org/)
run without too much extra overhead.

So then what is wrong with the xf86-video-mali? It suffers from the same
problem as many other X11 drivers for ARM hardware. DRI2 extension
(the thing which is used for the integration of GLES acceleration)
needs some specific, hardware-specific buffers allocation
([UMP](http://malideveloper.arm.com/develop-for-mali/drivers/open-source-mali-gpus-ump-user-space-drivers-source-code-2/)
in the case of xf86-video-mali). And EXA framework (a convenience
layer for adding 2D acceleration hooks) supports overriding pixmap
buffers allocation as part of its functionality. So the guys apparently
decided that it's a good idea to override the allocation of absolutely
all pixmaps without exception and not just the ones needed for DRI2. This was a total
2D performance disaster for the [SGX PVR driver](http://ssvb.github.com/2012/05/04/xorg-drivers-and-software-rendering.html)
driver. It is also killing performance for xf86-video-mali. But because
xf86-video-mali is an open source driver, I could run one more test.
UMP also allows allocation of cached buffers, so with a small tweak
xf86-video-mali can be changed to do cached allocations instead (let's
just ignore the potential cache coherency issues for the buffers
shared with Mali hadrware via DRI2). The benchmark results for
cached UMP allocations are shown as green bars on the chart above.
In some cases (t-firefox-fishtank), the performance for cached
UMP allocations managed to catch up with xf86-video-sunxifb (and
naturally xf86-video-fbdev). But many other cases are still slow.
It's not just uncached memory killing performance, the UMP
allocations themselves also require expensive ioctls and have
very heavy overhead. So sorry, the following suggestion
from xf86-video-mali readme file is simply not going to fly:
{% highlight text %}
The provided "xf86-video-mali" driver contains an EXA module which has been
integrated with the UMP system. Your 2D driver may therefore require an
integration with UMP as well. The suggestion is to pass the secure ID down to
the kernel device driver for your hardware, but it is also possible to get the
CPU-mapped address for the memory by calling ump_mapped_pointer_get.

Please refer to UMP documentation for more information regarding this.
{% endhighlight text %}
BTW, if anyone has some doubts and wonders if these colored bars
in the chart are really correlated with reality, I sugest checking
my youtube video about [Linux on ARM Chromebook: xf86-video-armsoc vs. xf86-video-fbdev](http://www.youtube.com/watch?v=Vzmckw3fAQo).
The xf86-video-armsoc driver has all the same 2D performance problems :-(

It really puzzles me why nearly all the X11 drivers for ARM hardware
are making the same mistake. An [old X11 DDX driver from Nokia N900](http://maemo.org/packages/view/xserver-xorg-video-fbdev/)
at least could do separate allocation for DRI2 buffers and normal
pixmaps, while being not the best and cleanest implementation for sure.

## The future of xf86-video-sunxifb

XV and XRANDR still need to be implemented. And of course there is still
a lot of room for real 2D performance improvements :-)
