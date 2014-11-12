---
layout: post
title:  Revisiting FullHD X11 desktop performance of the Allwinner A10
tags: [allwinner, performance, dram]
---

In my [previous blog post]({{ site.url }}/2013/06/27/fullhd-x11-desktop-performance-of-the-allwinner-a10.html),
I was talking about a pathologically bad Linux desktop performance with FullHD monitors on Allwinner A10 hardware.

A lot of time has passed since then. Thanks to the availability of Rockchip
[sources](https://github.com/ssvb/Rockchip-GPL-Kernel/blob/master/arch/arm/mach-rk29/ddr.c)
and [documentation](http://www.cnx-software.com/2012/11/04/rockchip-rk3066-rk30xx-processor-documentation-source-code-and-tools/),
we have learned a lot of information about the DRAM controller in Allwinner A10/A13/A20 SoCs.
Both Allwinner and Rockchip are apparently licensing the DRAM controller IP from
the same [third-party vendor](http://www.synopsys.com/dw/ipdir.php?ds=dwc_ddr2-lite_mem).
And their DRAM controller hardware registers are sharing a lot of similarities (though
unfortunately this is not an exact match).

Having a much better knowledge about the hardware allowed us to revisit
this problem, investigate it in more details and
[come up with a solution back in April 2014](https://github.com/linux-sunxi/u-boot-sunxi/commit/4e1532df5ebc6e0dd56c09dddb3d116979a2c49b).
The only missing part was providing an update in this blog. At least
to make it clear that the problem has been resolved now. So here we go...

<!--more-->

## The most likely culprit (DRAM bank conflicts)

A lot of general information about how DRAM works is readily available in the Internet at
various places
[[1]](http://www.anandtech.com/show/3851/everything-you-always-wanted-to-know-about-sdram-memory-but-were-afraid-to-ask)
[[2]](http://www.lostcircuits.com/mambo//index.php?option=com_content&task=view&id=35&Itemid=60).
Not to mention the official JEDEC DDR3 specification and all the datasheets from the DDR3 chip
vendors.

The DDR3 memory is typically organized as 8 interleaved banks. Only one page can be open in each
bank at the same time. If two competing DRAM users (such as the CPU and the display controller) are
occasionally trying to access different pages from the same bank, then there is a significant
performance penalty because the previous page needs to be closed first (this takes tRP cycles),
then the next page needs to be open (this takes tRCD cycles) and finally have an additional
tCAS cycles delay before the back-to-back bursts can be served from the newly open page
at the tCCD rate.

Now we only need to know how bad are the bank conflicts in practice and whether they
can explain the performance problems earlier observed on the
[Cubieboard](https://linux-sunxi.org/Cubietech_Cubieboard) and
[Mele A2000](https://linux-sunxi.org/Mele_A2000)
devices when they were driving a FullHD monitor.

## What we know about the hardware

The Cubieboard default DRAM timing values for tRP (6), tRCD (6) and tCCD (4) can be easily
identified by decoding the [SDR_TPR0](http://linux-sunxi.org/A10_DRAM_Controller_Register_Guide#SDR_TPR0)
hardware register bitfields. The page size is 4096 in the Cubieboard (two 2048 sized pages
from two 16-bit DRAM chips combined), which means that any physical addresses that differ
by a multiple of 32K bytes belong to the same bank. The 32-bit data bus width allows to
transfer 32 bytes of data per each 8-beat burst.

Additionally, we can have a look at some of the listed
[Synopsys DesignWare® DDR2/3-Lite SDRAM Memory Controller IP](http://www.synopsys.com/dw/ipdir.php?ds=dwc_ddr2-lite_mem)
features:
{% highlight text %}
* Includes a configurable multi-port arbiter with up to 32 host ports using Host
  Memory Interface (HMI), AMBA AHB or AMBA 3 AXI
* Command re-ordering and scheduling to maximize memory bus utilization
   * Command reordering between banks based on bank status
   * Programmable priority arbitration and anti-starvation mechanisms
   * Configurable per-command priority with up to eight priority levels; also
     serves as a per-port priority
* Automatic scheduling of activate and precharge commands
{% endhighlight text %}

And compare these features with the 'arch/arm/mach-sun7i/include/mach/dram.h' header
file from the linux-sunxi kernel (this is the only information available to
us about the DRAM controller host ports):

{% highlight C %}
typedef struct __DRAM_HOST_CFG_REG{
    unsigned int    AcsEn:1;        //bit0, host port access enable
    unsigned int    reserved0:1;    //bit1
    unsigned int    PrioLevel:2;    //bit2, host port poriority level
    unsigned int    WaitState:4;    //bit4, host port wait state
    unsigned int    CmdNum:8;       //bit8, host port command number
    unsigned int    reserved1:14;   //bit16
    unsigned int    WrCntEn:1;      //bit30, host port write counter enable
    unsigned int    RdCntEn:1;      //bit31, host port read counter enable
} __dram_host_cfg_reg_t;

typedef enum __DRAM_HOST_PORT{
    DRAM_HOST_CPU   = 16,
    DRAM_HOST_GPU   = 17,
    DRAM_HOST_BE    = 18,
    DRAM_HOST_FE    = 19,
    DRAM_HOST_CSI   = 20,
    DRAM_HOST_TSDM  = 21,
    DRAM_HOST_VE    = 22,
    DRAM_HOST_USB1  = 24,
    DRAM_HOST_NDMA  = 25,
    DRAM_HOST_ATH   = 26,
    DRAM_HOST_IEP   = 27,
    DRAM_HOST_SDHC  = 28,
    DRAM_HOST_DDMA  = 29,
    DRAM_HOST_GPS   = 30,
} __dram_host_port_e;
{% endhighlight C %}

The actual DRAM controller host port settings are presented as tables in the u-boot bootloader.
The priority of the DRAM_HOST_BE (Display Engine Backend) is set higher than the priority
of DRAM_HOST_CPU (CPU).

All of this information is sufficient to implement a simple software simulation.

## Software simulation

The following quickly hacked <a href="{{ site.url }}/files/2014-11-11/simulate-cpu-vs-debe-competition.rb">
ruby script</a> tries to model the competition between the display controller and the CPU, also
taking into account DRAM bank conflict penalties whenever they happen. In this model, we
assume that the display controller has the highest priority and attempts to do standalone
32-byte burst reads at regular intervals whenever possible. And all the leftover memory
bandwidth is consumed by the CPU. Below are the simulation results produced by this script:

<div><table border=1 style='border-collapse: collapse; empty-cells: show; font-family: arial; font-size: 13.34px; white-space: nowrap; background: #F0F0F0;'>
<caption><b>Table 1. Simulated memory write bandwidth available to the CPU (memset)</b></caption>
<tr><th><th colspan=6>Memory clock speed
<tr><th>Video mode<th>360MHz<th>384MHz<th>408MHz<th>432MHz<th>456MHz<th>480MHz
<tr><td>1920x1080, 32bpp, 60Hz<td bgcolor='red'>499 MB/s<td bgcolor='red'>500 MB/s<td bgcolor='red'>500 MB/s<td bgcolor='red'>500 MB/s<td bgcolor='red'>500 MB/s<td bgcolor='red'>500 MB/s</tr>
<tr><td>1920x1080, 32bpp, 56Hz<td bgcolor='red'>466 MB/s<td bgcolor='red'>466 MB/s<td bgcolor='red'>466 MB/s<td bgcolor='red'>466 MB/s<td bgcolor='red'>466 MB/s<td bgcolor='lightgreen'>1950 MB/s</tr>
<tr><td>1920x1080, 32bpp, 50Hz<td bgcolor='red'>416 MB/s<td bgcolor='red'>416 MB/s<td bgcolor='red'>416 MB/s<td bgcolor='lightgreen'>1858 MB/s<td bgcolor='lightgreen'>1244 MB/s<td bgcolor='lightgreen'>2071 MB/s</tr>
<tr><td>1920x1080, 24bpp, 60Hz<td bgcolor='red'>375 MB/s<td bgcolor='lightgreen'>1502 MB/s<td bgcolor='lightgreen'>809 MB/s<td bgcolor='lightgreen'>1864 MB/s<td bgcolor='lightgreen'>1864 MB/s<td bgcolor='lightgreen'>1865 MB/s</tr>
<tr><td>1920x1080, 24bpp, 56Hz<td bgcolor='lightgreen'>1463 MB/s<td bgcolor='lightgreen'>1129 MB/s<td bgcolor='lightgreen'>1687 MB/s<td bgcolor='lightgreen'>1740 MB/s<td bgcolor='lightgreen'>1740 MB/s<td bgcolor='lightgreen'>1177 MB/s</tr>
<tr><td>1920x1080, 24bpp, 50Hz<td bgcolor='lightgreen'>1553 MB/s<td bgcolor='lightgreen'>1553 MB/s<td bgcolor='lightgreen'>1553 MB/s<td bgcolor='lightgreen'>1337 MB/s<td bgcolor='lightgreen'>1919 MB/s<td bgcolor='lightgreen'>2383 MB/s</tr>
</table></div>
<br>
<div><table border=1 style='border-collapse: collapse; empty-cells: show; font-family: arial; font-size: 13.34px; white-space: nowrap; background: #F0F0F0;'>
<caption><b>Table 2. Simulated memory write bandwidth available to the CPU (backwards memset)</b></caption>
<tr><th><th colspan=6>Memory clock speed
<tr><th>Video mode<th>360MHz<th>384MHz<th>408MHz<th>432MHz<th>456MHz<th>480MHz
<tr><td>1920x1080, 32bpp, 60Hz<td bgcolor='lightgreen'>1496 MB/s<td bgcolor='lightgreen'>1496 MB/s<td bgcolor='lightgreen'>1595 MB/s<td bgcolor='lightgreen'>1920 MB/s<td bgcolor='lightgreen'>2206 MB/s<td bgcolor='lightgreen'>2492 MB/s</tr>
<tr><td>1920x1080, 32bpp, 56Hz<td bgcolor='lightgreen'>1397 MB/s<td bgcolor='lightgreen'>1578 MB/s<td bgcolor='lightgreen'>1843 MB/s<td bgcolor='lightgreen'>2129 MB/s<td bgcolor='lightgreen'>2422 MB/s<td bgcolor='lightgreen'>3235 MB/s</tr>
<tr><td>1920x1080, 32bpp, 50Hz<td bgcolor='lightgreen'>1600 MB/s<td bgcolor='lightgreen'>1887 MB/s<td bgcolor='lightgreen'>2193 MB/s<td bgcolor='lightgreen'>2888 MB/s<td bgcolor='lightgreen'>2889 MB/s<td bgcolor='lightgreen'>2889 MB/s</tr>
<tr><td>1920x1080, 24bpp, 60Hz<td bgcolor='lightgreen'>1869 MB/s<td bgcolor='lightgreen'>2599 MB/s<td bgcolor='lightgreen'>2600 MB/s<td bgcolor='lightgreen'>2600 MB/s<td bgcolor='lightgreen'>2601 MB/s<td bgcolor='lightgreen'>2601 MB/s</tr>
<tr><td>1920x1080, 24bpp, 56Hz<td bgcolor='lightgreen'>2426 MB/s<td bgcolor='lightgreen'>2426 MB/s<td bgcolor='lightgreen'>2427 MB/s<td bgcolor='lightgreen'>2427 MB/s<td bgcolor='lightgreen'>2428 MB/s<td bgcolor='lightgreen'>2428 MB/s</tr>
<tr><td>1920x1080, 24bpp, 50Hz<td bgcolor='lightgreen'>2167 MB/s<td bgcolor='lightgreen'>2167 MB/s<td bgcolor='lightgreen'>2167 MB/s<td bgcolor='lightgreen'>2168 MB/s<td bgcolor='lightgreen'>2168 MB/s<td bgcolor='lightgreen'>2364 MB/s</tr>
</table></div>

The results from the two tables above can be directly compared with the actual experimental data
from the [previous blog post]({{ site.url }}/2013/06/27/fullhd-x11-desktop-performance-of-the-allwinner-a10.html).
The simulation model is very limited and does not take into account all the possible
factors limiting the memory bandwidth, so the green cells in the tables with
simulated results tend to be overly optimistic. But we are only interested in the
crossover point, where the performance becomes pathologically bad (the red table cells).
And the simulation seems to be reasonably accurately representing the memset
performance drop.

## Timeline charts

As an additional bonus, below are the timeline charts of the simulated memory accesses
from the display controller (shown as blue), accesses from the CPU (shown
as green) and the cycles wasted on the bank switch penalties (shown as red). When generating
these charts, the page size had been artificially reduced to 128 bytes for illustrative
purposes. The behaviour with 4096 bytes per page does not differ much, but just needs
much larger timeline chart pictures, which would not fit here well.

<p><div class="image">
<b>Chart 1. 1920x1080-32@60Hz, DDR3 @360MHz, memset simulation<br></b>
<a href="{{ site.url }}/files/2014-11-11/1920x1080-32@60hz-ddr3-360mhz-simulated-memset-page128.png">
<img src="{{ site.url }}/files/2014-11-11/1920x1080-32@60hz-ddr3-360mhz-simulated-memset-page128.png"
alt="1920x1080-32@60hz-ddr3-360mhz-simulated-memset-page128.png"</img></a>
</div></p>

The chart 1 demonstrates one of the configurations with a pathological memset performance
drop. The CPU memory accesses from memset quickly catch up with the framebuffer scanout and
start fighting for the same bank. The gaps between the memory accesses from the display
controller are too small and don't allow switching to a different page in the bank, performing
more than one burst by the CPU and switching back to serve the next request from the display
controller in time. As a result, the CPU and the display controller can't escape each
other and keep progressing at roughly the same slow speed (~500 MB/s). Most of the
memory bandwidth is wasted on the pointless page switch overhead.

Another important thing is that in reality the display refresh also gets somewhat
disrupted. On Allwinner A10 hardware it manifests itself as occasional screen shaking
up/down and does not look very nice.

<p><div class="image">
<b>Chart 2. 1920x1080-32@60Hz, DDR3 @360MHz, backwards memset simulation<br></b>
<a href="{{ site.url }}/files/2014-11-11/1920x1080-32@60hz-ddr3-360mhz-simulated-backwards-memset-page128.png">
<img src="{{ site.url }}/files/2014-11-11/1920x1080-32@60hz-ddr3-360mhz-simulated-backwards-memset-page128.png"
alt="1920x1080-32@60hz-ddr3-360mhz-simulated-backwards-memset-page128.png"</img></a>
</div></p>

The chart 2 demonstrates backwards memset behaviour. As the CPU is walking memory in the
opposite direction, bank conflicts with the display controller do not last long and,
after escaping, the CPU is able to circle through all the banks until clashing with
the display controller again. The overall performance is much better compared to what
we had with the chart 1.

<p><div class="image">
<b>Chart 3. 1920x1080-24@50Hz, DDR3 @480MHz, memset simulation<br></b>
<a href="{{ site.url }}/files/2014-11-11/1920x1080-24@50hz-ddr3-480mhz-simulated-memset-page128.png">
<img src="{{ site.url }}/files/2014-11-11/1920x1080-24@50hz-ddr3-480mhz-simulated-memset-page128.png"
alt="1920x1080-24@50hz-ddr3-480mhz-simulated-memset-page128.png"</img></a>
</div></p>

The chart 3 demonstrates much less demanding display refresh bandwidth (color depth
and refresh rate are both reduced) and a higher DRAM clock speed. Unlike what happened
on chart 1, now the memory accesses from the CPU (green) are able to slip between the
memory accesses from the display controller (blue). The performance is good.

## Analysis of the results and a solution for the problem

In fact, we have no idea what is really happening in the DRAM controller, because we have
neither proper tools nor good documentation. But the selected software simulation model
appears to provide somewhat reasonable results, which are consistent with the previously
collected experimental data. So until proven otherwise, we just assume that this model
is correct.

It looks like the root cause of the severe memory performance drop and screen shaking
glitches on the HDMI monitor is that the display controller in Allwinner A10 is not
particularly well behaved. Having higher priority for it means that the DRAM controller
must serve the requests from the display controller as soon as they arrive without
trying to postpone and/or coalesce them into larger batches in order to minimize bank
conflict penalties. Reducing the priority of the display controller host ports and
making it the same as the CPU/GPU actually improves the situation a lot, because the
DRAM controller is now free to schedule memory accesses. At least the memset performance
gets much better.

But what about the screen shaking HDMI glitches? If there is some kind of buffering
in the display controller, then we do not really care about high priority and
minimizing latency of memory accesses, but only need to ensure that the average
framebuffer scanout bandwidth is sufficient. Does such buffering exist? Unfortunately
this does not seem to be the case for DEBE (Display Engine Backend) and reducing the
DRAM_HOST_BE priority makes the HDMI glitches much worse (for example, even moving
the mouse cursor is enough to cause a disruption). However the DEFE (Display Engine
Frontend), which is responsible for scaling the hardware layers, seems to implement
some sort of buffering. So a reduction of the DRAM_HOST_FE priority does not cause
troubles with the HDMI signal for scaled layers, while resolving the memory
performance problems!

To sum it up, we have a solution. However it is not perfect. Scaled DEFE layers now
work great, but there are only two of them. And ordinary non-scaled DEBE layers
still remain broken.

## Benchmarking on real hardware

[A10-OLinuXino-LIME](https://linux-sunxi.org/Olimex_A10-OLinuXino-Lime) development
board has only 16-bit DRAM bus width. And driving a FullHD monitor is even more
challenging for it, when compared to the other Allwinner A10 devices. So it is
an interesting hardware to test. And this time testing involves the glmark2-es2 3D
graphics benchmark, which is run with proprietary Mali400 drivers:

<table border=1 style='border-collapse: collapse; empty-cells: show; font-family: arial; font-size: 13.34px; white-space: nowrap; background: #F0F0F0;'>
<caption><b>Table 3. Final score from <a href='https://github.com/glmark2/glmark2'>glmark2-es2</a> 2012.12 (the benchmark is run in a 800x600 window)</b></caption>
<tr><th><th colspan=6>Monitor resolution and refresh rate (32bpp X11 desktop)
<tr><th>Allwinner A10 based device<th>1280x720p50<th>1280x720p60<th>1920x1080p50<th>1920x1080p60</tr>
<tr><td><a href='https://linux-sunxi.org/Mele_A2000'>Mele A2000</a>, 32-bit DDR3 @360MHz (before the fix)<td>151<td>148<td>140<td>136</tr>
<tr><td><a href='https://linux-sunxi.org/Cubietech_Cubieboard'>Cubieboard</a>, 32-bit DDR3 @480MHz (before the fix)<td>166<td>166<td>161<td>157</tr>
<tr><td><a href='https://linux-sunxi.org/Olimex_A10-OLinuXino-Lime'>A10-OLinuXino-LIME</a>, 16-bit DDR3 @480MHz (before the fix)<td bgcolor='lightgreen'>100<td bgcolor='lightgreen'>91<td bgcolor='red'>56<td bgcolor='red'>48</tr>
<tr><td><a href='https://linux-sunxi.org/Olimex_A10-OLinuXino-Lime'>A10-OLinuXino-LIME</a>, 16-bit DDR3 @480MHz (after the fix)<td bgcolor='lightgreen'>114<td bgcolor='lightgreen'>110<td bgcolor='lightgreen'>94<td bgcolor='lightgreen'>85</tr>
</table></div>

The last row in the table shows the performance improvement after switching
to the use of DEFE layers ([scaler mode](http://linux-sunxi.org/Fex_Guide#disp_init_configuration))
and applying the
[DRAM host ports priority tweak](https://github.com/linux-sunxi/u-boot-sunxi/commit/4e1532df5ebc6e0dd56c09dddb3d116979a2c49b)
to u-boot. This tweak has already made it to the mainline u-boot.

The future KMS driver will probably need to have some special plane
properties to resolve the problem for Allwinner A10. The newer
Allwinner A20 SoC is not affected.

The usual and completely unsurprising thing is that both NEON optimized
2D software rendering and 3D acceleration like fast memory very much.
Having fast memory is pretty much critical for running a linux desktop
system on ARM hardware.

## References

1. [Everything You Always Wanted to Know About SDRAM (Memory): But Were Afraid to Ask](http://www.anandtech.com/show/3851/everything-you-always-wanted-to-know-about-sdram-memory-but-were-afraid-to-ask) (anandtech.com)
2. [DDR2 - An Overview](http://www.lostcircuits.com/mambo//index.php?option=com_content&task=view&id=35&Itemid=60) (lostcircuits.com)
