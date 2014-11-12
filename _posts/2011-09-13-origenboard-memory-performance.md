---
layout: post
title: Origenboard, memory performance
tags: [arm, samsung, performance, dram]
---

Those who have read my old
[Origenboard, early adopter impressions](http://ssvb.github.com/2011/07/30/origenboard-early-adopter.html)
blog post may wonder why I bought this board in the first place. As far as I know, there is no
freely available public documentation for Exynos 4210 SoC so the "if you want something done, do
it yourself" approach does not work well, and the support provided at
[origenboard.org](http://www.origenboard.org/) has not been very stellar so far.
[OMAP4](http://focus.ti.com/general/docs/wtbu/wtbuproductcontent.tsp?contentId=53243&navigationId=12843&templateId=6123)
based [pandaboard](http://pandaboard.org/) is a lot more open source friendly, has great community
around it and would have been a no-brainer choice, right?
Well, pandaboard is a great piece of of hardware, but the early boards based on early OMAP4 revisions
used to have a rather
[poor](http://computerarch.com/log/2011/03/01/pandaboard/)
[memory](http://groups.google.com/group/pandaboard/browse_thread/thread/24d80cc66f52b789/b977c1ee5eb5a78c?#b977c1ee5eb5a78c)
[performance](http://groups.google.com/group/pandaboard/browse_thread/thread/2d4d82eb530e8195).
According to the information from the pandaboard mailing list, [OMAP4460 is expected to address these problems](http://groups.google.com/group/pandaboard/msg/dfd2d2e1336d435b).
Too bad that there are no OMAP4460 powered pandaboards available for sale yet. And that's why I decided to check the new alternative
solution from Samsung to see what they can offer.

### But who cares about memory performance?

Just any software which works with large sets of data not fitting L1/L2 caches
benefits from fast memory. I'm particularly interested in having fast software
rendered 2D graphics, and this is exactly the case where fast memory is
critical for getting good performance.

Just to give an example, let's take some numbers from my older
[post in the pixman mailing list](http://www.mail-archive.com/pixman@lists.freedesktop.org/msg00695.html):
{% highlight text %}
== Intel Atom N450 @1667MHz, DDR2-667 (64-bit) ==

           add_8888_8888 =  L1: 607.08  L2: 375.34  M:259.53
          over_8888_x888 =  L1: 123.73  L2: 117.10  M:113.56
          over_8888_0565 =  L1: 106.11  L2:  98.91  M: 99.07

== TI OMAP3430/3530, ARM Cortex-A8 @500MHz, LPDDR @166MHz (32-bit) ==

    default build:
           add_8888_8888 =  L1: 227.26  L2:  84.71  M: 44.54
          over_8888_x888 =  L1: 161.06  L2:  88.20  M: 44.86
          over_8888_0565 =  L1: 127.02  L2:  93.99  M: 61.25

    software prefetch disabled (*):
           add_8888_8888 =  L1: 351.44  L2:  97.29  M: 25.35
          over_8888_x888 =  L1: 168.72  L2:  95.04  M: 24.81
          over_8888_0565 =  L1: 128.06  L2:  98.96  M: 32.16
{% endhighlight text %}
All the numbers are provided by lowlevel-blt-bench test program from [pixman](http://pixman.org/)
and are measured in MPix/s.
There are three cases benchmarked for each 2D graphics operation: L1 (data set which fits L1 cache),
L2 (data set which fits L2 cache) and M (data set does not fit caches and has to work with memory).
It becomes very clear that ARM NEON optimized code had been memory bandwidth limited at least on
early OMAP3 devices. And Intel Atom surely had a much better memory bandwidth:
~260 MPix/s * 4 bytes per pixel * (2 reads and 1 write per pixel for add_8888_8888), which is ~3.1 GB/s
total. These are just some microbenchmark numbers, but actual 2D software rendered graphics performance
is also heavily affected by memory speed. And fast memory is important for having responsive
and fast linux desktop even without GPU acceleration. And as far as I know, there are still
[no open source GPU drivers available for mobile devices](http://www.phoronix.com/scan.php?page=news_item&px=OTgyMA).

### Introducing yet another memory benchmark program

If we want to know whether the memory is fast in our system, we need to benchmark it somehow.
There is a popular [STREAM](http://www.cs.virginia.edu/stream/FTP/Code/stream.c) benchmark,
but its results are apparently
[very much compiler dependent when run on ARM](http://groups.google.com/group/pandaboard/msg/1e5f08c949d4bf5d).
Moreover, it uses floating point, making this benchmark unsuitable for
the devices which don't have FPU (it would test just anything but not memory bandwidth).

So I tried to make my own memory benchmark program, which tries to measure the peak
bandwidth of sequential memory accesses and the latency of random memory accesses.
Bandwidth is measured by running different assembly code for the aligned memory blocks
and attempting different prefetch strategies. Also this benchmark program integrates
some of my old [ARM](http://permalink.gmane.org/gmane.comp.graphics.pixman/1104) and
[MIPS32](http://permalink.gmane.org/gmane.comp.graphics.pixman/1026) memory bandwidth
test code.

There are some potential pitfalls when implementing benchmarks. A popular mistake is
related to forgetting to initialize the buffers and have the results distorted by [COW](http://en.wikipedia.org/wiki/Copy-on-write).
But copying data from one memory buffer to another is also not so simple. Depending
on the relative alignment of the source and destination buffers, the
performance may vary a lot. It was noticed by
Måns Rullgård
(mru)
in the [#pandaboard irc](http://pandaboard.org/pbirclogs/index.php?date=2010-11-04#T21:52:53) almost a year ago. And
the effect of offset between the arrays is also mentioned in [STREAM benchmark FAQ](http://www.cs.virginia.edu/stream/ref.html).
Moreover, physical memory fragmentation also plays
some role because the caches in modern processors are physically tagged. So exactly
the same program may provide different results depending on whether it was run on
a freshly rebooted system (with almost no memory fragmentation), or on the system
which has been running for a while. Overall, this looks like some kind of aliasing in the
memory subsystem. And ironically, the performance on a freshly rebooted system
is typically worse.

An empirical solution is to try to ensure that the addresses
of memory accesses in the source and destination buffer, happening close
to each other, differ in as many bits as possible. So I'm using 0xAAAAAAAA,
0x55555555, 0xCCCCCCCC and 0x33333333 patterns for the lowest bits
in the buffer addresses. And this seems to be quite effective, memory copy
benchmark results are now well reproducible and showing high numbers.

The initial release of this benchmark program can be downloaded here: [ssvb-membench-0.1.tar.gz](http://github.com/downloads/ssvb/ssvb-membench/ssvb-membench-0.1.tar.gz)<br>
And the git repository is at [http://github.com/ssvb/ssvb-membench](http://github.com/ssvb/ssvb-membench)

### Origenboard memory benchmark results and performance tuning

The table below shows how the memory performance is affected by different settings in<br>
<a href="http://infocenter.arm.com/help/topic/com.arm.doc.ddi0246f/CHDHIECI.html">L2C-310 Level 2 Cache Controller, Prefetch Control Register</a>
<table>
<th>Prefetch Control Register settings
<th>Memory copy performance
<th>Latency of random accesses in 64 MiB block
<tr><td><a href="http://ssvb.github.com/files/2011-09-13/origen-membench-1.txt">0x30000007 (linaro kernel default)</a>
<td>761.86 MB/s<td>167.9 ns
<tr><td><a href="http://ssvb.github.com/files/2011-09-13/origen-membench-2.txt">0x30000007 + "Double linefill enable"</a>
<td>1179.17 MB/s<td>183.9 ns
<tr><td><a href="http://ssvb.github.com/files/2011-09-13/origen-membench-3.txt">0x30000007 + "Double linefill enable" +<br>"Double linefill on WRAP read disable"</a>
<td>1174.32 MB/s<td>174.0 ns
</table>

Setting "Double linefill on WRAP read disable" regains some of the random access
latency with no regressions to sequential copy performance. Assuming that there are
no hardware bugs related to this setup, enabling double linefill is a no-brainer.
I have submitted [a patch to linaro-dev mailing list](http://lists.linaro.org/pipermail/linaro-dev/2011-September/007462.html)
(<b>update from 2011-09-19:</b> according to the provided feedback, appears that [double linefill is not used for a good reason](http://lists.linaro.org/pipermail/linaro-dev/2011-September/007506.html)).

Probably some more memory performance tweaks can be still applied and
a better configuration can be found by trying different permutations
of the bits in:

* [Cortex-A9, Auxiliary Control Register](http://infocenter.arm.com/help/topic/com.arm.doc.ddi0388g/CIHCHFCG.html)
* [L2C-310 Level 2 Cache Controller, Auxiliary Control Register](http://infocenter.arm.com/help/topic/com.arm.doc.ddi0246f/Beifcidc.html)
* [L2C-310 Level 2 Cache Controller, Prefetch Control Register](http://infocenter.arm.com/help/topic/com.arm.doc.ddi0246f/CHDHIECI.html)


### And finally STREAM benchmark as a bonus

[Origenboard, Samsung Exynos 4210, dual ARM Cortex-A9 @1.2GHz](http://ssvb.github.com/files/2011-09-13/stream-origen.txt)
{% highlight text %}
$ gcc -O2 -fopenmp -mcpu=cortex-a9 -o stream stream.c
$ ./stream
-------------------------------------------------------------
Function      Rate (MB/s)   Avg time     Min time     Max time
Copy:        2284.9071       0.0281       0.0280       0.0282
Scale:       2339.6942       0.0274       0.0274       0.0275
Add:         2028.8679       0.0474       0.0473       0.0474
Triad:       1992.7801       0.0482       0.0482       0.0483
-------------------------------------------------------------
{% endhighlight %}

[Intel Atom N450 @1.67GHz](http://ssvb.github.com/files/2011-09-13/stream-atom.txt)
{% highlight text %}
$ gcc -O2 -fopenmp -march=atom -mtune=atom -o stream stream.c
$ ./stream
-------------------------------------------------------------
Function      Rate (MB/s)   Avg time     Min time     Max time
Copy:        2236.8130       0.0143       0.0143       0.0144
Scale:       2230.3084       0.0144       0.0143       0.0144
Add:         2656.0587       0.0181       0.0181       0.0182
Triad:       2679.3174       0.0180       0.0179       0.0180
-------------------------------------------------------------
{% endhighlight %}

Overall, the [memory performance of Origenboard](http://ssvb.github.com/files/2011-09-13/origen-membench-3.txt)
appears to be not very much inferior to the [memory performance of Intel Atom N450](http://ssvb.github.com/files/2011-09-13/atom-membench.txt)
(<b>update from 2011-09-19</b>: when/if we get Exynos 4212 based boards in our hands).
