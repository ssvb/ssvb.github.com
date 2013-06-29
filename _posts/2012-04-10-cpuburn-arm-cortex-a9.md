---
layout: post
title: Is your ARM Cortex-A9 hot enough?
tags: [arm, cpuburn, assembly]
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
instructions are also rather hot. Mixing everything together, we get [one more implementation of cpuburn for Cortex-A9](http://github.com/downloads/ssvb/ssvb.github.com/ssvb-cpuburn-a9.S):
{% highlight text %}
    .syntax unified
    .text
    .arch armv7-a
    .fpu neon
    .arm

    .global main
    .global sysconf
    .global fork

/* optimal value for LOOP_UNROLL_FACTOR seems to be BTB size dependent */
#define LOOP_UNROLL_FACTOR   110
/* 64 seems to be a good choice */
#define STEP                 64

.func main
main:

#ifdef __linux__
        mov         r0, 84 /* _SC_NPROCESSORS_ONLN */
        blx         sysconf
        mov         r4, r0
        cmp         r4, #2
        blt         1f
        blx         fork /* have at least 2 cores */
        cmp         r4, #4
        blt         1f
        blx         fork /* have at least 4 cores */
1:
#endif

        ldr         lr, =(STEP * 4 + 15)
        subs        lr, sp, lr
        bic         lr, lr, #15
        mov         ip, #STEP
        mov         r0, #0
        mov         r1, #0
        mov         r2, #0
        mov         r3, #0
        ldr         r4, =0xFFFFFFFF
        b           0f
    .ltorg
0:
    .rept LOOP_UNROLL_FACTOR
        vld2.8      {q0}, [lr, :128], ip
        it          ne
        smlalne     r0, r1, lr, r4
        bne         1f
1:
        vld2.8      {q1}, [lr, :128], ip
        it          ne
        smlalne     r2, r3, lr, r4
        bne         1f
1:
        vld2.8      {q2}, [lr, :128], ip
        vld2.8      {q3}, [lr, :128], ip
        it          ne
        subsne      lr, lr, #(STEP * 4)
    .endr
        bne         0b
.endfunc
{% endhighlight text %}

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
<tr><td><a href="http://github.com/downloads/ssvb/ssvb.github.com/ssvb-cpuburn-a9.S">ssvb-cpuburn-a9.S</a>
<td><b>~1640 mA</b>
</table>
<br>

### And also a cpuburn tweak for ARM Cortex-A8 (added on 2011-04-11)

A quick test on Cortex-A8 shows that using <b>SMLAL</b> is a bad idea there, but extra NEON arithmetic instructions
can be added because Cortex-A8 supports dual issue for NEON.

This time experimenting with DM3730 based [IGEPv2 board](http://igep.es/index.php?option=com_content&view=article&id=46&Itemid=55)
(ARM Cortex-A8 @1GHz) and using [dm3730-temp-sensor](https://github.com/mrj10/dm3730-temp-sensor) for temperature measurements:
<table>
<th>cpuburn implementation
<th>temperature
<tr><td>idle system (this kernel has no power management)
<td>~57.75 C
<tr><td><a href="http://hardwarebug.org/files/burn.S">cpuburn-neon</a>
<td>~92.75 C
<tr><td><a href="http://packages.debian.org/sid/cpuburn">cpuburn-1.4a</a> (burnCortexA8.s)
<td>~96.00 C
<tr><td><a href="http://github.com/downloads/ssvb/ssvb.github.com/ssvb-cpuburn-a8.S">ssvb-cpuburn-a8.S</a>
<td><b>~104.25 C</b>
</table>
<strike>If the sensor is not lying, then maybe using a plastic case for this board was not a good choice after all.</strike> The sensor is most likely lying as explained by Nishanth Menon in the [google+ comments](https://plus.google.com/u/0/113201731981878354205/posts/44WtAFbQcaK).

### Final words (added on 2011-04-11)

Before anybody jumps to wild conclusions, I would like to note that:<ul>
<li>Pandaboard is not a mobile device and it is not designed for really low power consumption. It is a known fact that it [requires a PSU rated at 4A](http://omappedia.org/wiki/PandaBoard_FAQ#What_are_the_specs_of_the_Power_supply_I_should_use_with_a_PandaBoard.3F). I don't have any idea where most of the heat is dissipated, but it is quite likely that not only OMAP chip is involved.</li>
<li>Cpuburn is very different from any typical workload and can't be used for estimating power consumption. It's just a hardware reliability testing tool</li>
</ul>
<br>
