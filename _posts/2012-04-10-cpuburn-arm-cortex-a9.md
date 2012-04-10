---
layout: post
title: Is your ARM Cortex-A9 hot enough?
---

{{ page.title }}
================

Inspired by the [google+ post](https://plus.google.com/u/0/100242854243155306943/posts/QCpWUZEkF9i) by Koen Kooi, I decided to check whether NEON is also hot in Cortex-A9.
Appears that [cpuburn tool](http://packages.debian.org/sid/cpuburn) supports ARM since 2010. And openembedded uses an alternative
[cpuburn-neon](http://cgit.openembedded.org/openembedded/commit/?id=7bc322831d1ed3487d36dee4687b7fa3b5cc81e4) implementation.
As we have at least two implementations, naturally one of them might be more efficient on Cortex-A9 than the other.
So I tested both of them on my old OMAP4430 based [pandaboard](http://pandaboard.org/)  (I would not miss this board too much
if it actually burns). The results of this comparison are provided in the table at the bottom.

I could have stopped at this point, but that would be not fun :) So I tried to experiment a bit with Cortex-A9 power consumption myself. Turns out
that Cortex-A9 can actually run a bit hotter. On the NEON side, <b>VLDx</b> instructions seem to be more power hungry than anything else
by a large margin. And aligned 128-bit reads are the best at generating heat. Using <b>VLD2</b> variant with
post-increment makes it do a bit more work than the plain <b>VLD1</b>. Moving to the ARM side, conditional branches and <b>SMLAL</b>
instructions are also rather hot. Mixing everything together, we get [one more implementation of cpuburn for Cortex-A9](http://ssvb.github.com/files/2012-10-04/ssvb-cpuburn-a9.S).
Maybe more improvements are still possible if I overlooked some better instructions, tricks with L2->L1 prefetches or anything else.
Also I have not tried running any tests on Cortex-A8 yet. But Cortex-A8 needs different tuning and I would not be
surprised if the the older cpuburn implementations can actually do a better job there. Finally,
the obligatory warning: <b>This program tries to stress the processor, attempting to generate
as much heat as possible. Improperly cooled or otherwise flawed hardware may potentially overheat and fail. Use at your own risk!</b>

As for the table below, each implementation has been tested with both Cortex-A9 cores fully loaded (starting two instances of
cpuburn if needed). Current draw values were measured after running the test non-interrupted for 10-15 minutes.
Honestly, the total ~1640 mA sustained current draw by pandaboard looks quite scary to me. At least I would
not dare to even try additionally stressing GPU and/or the hardware video decoder at the same time. 
<table>
<th>cpuburn implementation, running on both A9 cores
<th>current draw from 5V PSU (whole board, not just CPU)
<tr><td>idle system (this kernel has no power management)
<td>~550 mA
<tr><td><a href="http://hardwarebug.org/files/burn.S">cpuburn-neon</a>
<td>~1130 mA
<tr><td><a href="http://packages.debian.org/sid/cpuburn">cpuburn-1.4a</a> (burnCortexA9.s)
<td>~1180 mA
<tr><td><a href="http://ssvb.github.com/files/2012-10-04/ssvb-cpuburn-a9.S">ssvb-cpuburn-a9.S</a>
<td><b>~1640 mA</b>
</table>
<br>
