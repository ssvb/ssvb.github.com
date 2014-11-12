---
layout: post
title: Discovering instructions scheduling secrets
tags: [arm, x86, mips, assembly, performance]
---

Knowing the instructions scheduling rules is quite important when implementing
assembly optimizations. That's especially true for the simple embedded processors
such as ARM or MIPS, which don't typically implement [out-of-order execution](http://en.wikipedia.org/wiki/Out-of-order_execution)
or where the out-of-order instructions execution is just rudimentary at best. Instruction cycle timings are quite well documented
for some processors such as [ARM11](http://infocenter.arm.com/help/topic/com.arm.doc.ddi0211k/Cjaedced.html)
or [ARM Cortex-A8](http://infocenter.arm.com/help/topic/com.arm.doc.ddi0344k/Cfacfihf.html),
even sometimes providing a comprehensive [scheduling example](http://infocenter.arm.com/help/topic/com.arm.doc.ddi0344k/Babeghic.html).
But some processors such as [ARM Cortex-A9](http://infocenter.arm.com/help/topic/com.arm.doc.ddi0388f/Cjaedcef.html)
are apparently either too complex or maybe just too new to be described in more detail, and the
instruction cycle timings information is rather poor (more about Cortex-A9 maybe in another blog post).
And some ARM compatible processors even don't seem to have any public documentation at all.

Even having a good documentation, there always can be some ambiguity or omission of the fine details.
For example, ARM Cortex-A8 supports limited dual-issue for NEON instructions. But
can it really sustain 2 instructions per cycle execution rate on a long sequence of instructions?
Another example is accumulator forwarding for multiply-accumulate instructions. Using
back to back multiply-accumulate instructions is fine, but will the forwarding still work
if an unrelated instruction is inserted between them?

The solution is really simple. In addition to just reading and (mis)interpreting the manuals,
it makes a lot of sense to verify every important detail by running some tests
and benchmarks. Especially considering, that it is actually not very difficult at all.
The easy way to do this is just to create some *.S file and add the sequence
of the instructions to be investigated there, placing them in a simple loop. Then compile
and run this test program, measuring how much time it takes to run. Very simple.
And in order to make it easier to convert time into CPU cycles, it makes sense
to set the number of loop iterations to run to be equal to the CPU clock frequency.
In this case, the time of execution of the test program in seconds would be equal
to the number of cycles spent in the loop body.

Below is a trivial test program (tried on different CPU architectures, not just ARM),
which benchmarks the performance of a long sequence of back-to-back ADD instructions.
Addition is a simple and fast operation, which typically takes just 1 cycle to provide
the result. And because each instruction depends on the result of the previous one,
they can't dual-issue. So for most processors (with some exceptions) the performance
of this code will be exactly 1 cycle per ADD instruction.

### ARM

{% highlight gas %}
.text
.arch armv7-a
.global main

#ifndef CPU_CLOCK_FREQUENCY
#error CPU_CLOCK_FREQUENCY must be defined
#endif

#define LOOP_UNROLL_FACTOR   100

main:
        push        {r4-r12, lr}
        ldr         ip, =(CPU_CLOCK_FREQUENCY / LOOP_UNROLL_FACTOR)
        b           1f

    .balign 64
1:
    .rept LOOP_UNROLL_FACTOR
        add         r0, r0, r0
        add         r0, r0, r0
        add         r0, r0, r0
        add         r0, r0, r0
        add         r0, r0, r0
    .endr
        subs        ip, ip, #1
        bne         1b

        mov         r0, #0
        pop         {r4-r12, pc}
{% endhighlight %}

And the results of this benchmark from ARM Cortex-A8 @1GHz:

{% highlight sh %}
$ gcc -DCPU_CLOCK_FREQUENCY=1000000000 bench.S && time ./a.out

real    0m5.017s
user    0m5.016s
sys     0m0.000s
{% endhighlight %}

A few more explanations about this test program and the interpretation of results. The '.rept LOOP_UNROLL_FACTOR / ... / .endr' block repeats the code contained
inside it LOOP_UNROLL_FACTOR times (more information about gnu assembler macros can be found by reading 'info as').
This helps to reduce the loop overhead so that it becomes insignificant and can be ignored. Unrolling even more is good, though we need to be careful
in order not to exceed the instructions cache size. The end result is that the block of 5 ADD
instructions is executed CPU_CLOCK_FREQUENCY times when running this test program.
If the test program takes 5 seconds to execute, then it means that the sequence of instructions
inside of .rept block needs 5 cycles. If we had a non-integer number of seconds, then it would
mean that something likely went wrong.

Multiple variations are also possible. Earlier I posted some [code template for experimenting with NEON instructions scheduling](http://lists.freedesktop.org/archives/pixman/attachments/20110410/d6062de3/attachment.obj),
tailored for tuning ARM NEON optimizations specifically for the [pixman library](http://cgit.freedesktop.org/pixman).

### MIPS

{% highlight gas %}
.text
.set noreorder

#ifndef CPU_CLOCK_FREQUENCY
#error CPU_CLOCK_FREQUENCY must be defined
#endif

#define LOOP_UNROLL_FACTOR  100

.global main
.type main, @function
main:
        li      $t9, (CPU_CLOCK_FREQUENCY / LOOP_UNROLL_FACTOR) - 1
1:
    .rept LOOP_UNROLL_FACTOR
        addu    $t0, $t0, $t0
        addu    $t0, $t0, $t0
        addu    $t0, $t0, $t0
        addu    $t0, $t0, $t0
        addu    $t0, $t0, $t0
    .endr

        bnez    $t9, 1b
        addiu   $t9, $t9, -1

        j       $ra
        li      $v0, 0
{% endhighlight %}

MIPS74K @480MHz:
{% highlight sh %}
$ gcc -DCPU_CLOCK_FREQUENCY=480000000 bench.S && time ./a.out

real    0m10.064s
user    0m10.060s
sys     0m0.003s
{% endhighlight %}

MIPS24Kc @680MHz:
{% highlight sh %}
$ gcc -DCPU_CLOCK_FREQUENCY=680000000 bench.S && time ./a.out

real    0m5.040s
user    0m5.030s
sys     0m0.000s
{% endhighlight %}

This was a variant of the same benchmarking code for MIPS, which shows that MIPS74K has a higher latency and needs 2 cycles per addition.

### x86, and also taking a look at SMT

A similar benchmarking method can be also extended to analyze the efficiency of [SMT](http://en.wikipedia.org/wiki/Simultaneous_multithreading)
capable processors (Intel Atom, IBM Cell PPE and friends). Because the resources of a single CPU core are shared
between two hardware threads, there can't be 100% scalability and it may be interesting
to see how much SMT can actualy help on real or artificial workload. The test program for x86 may look like this:
{% highlight gas %}
.intel_syntax noprefix
.text
.global main
.global fork
.global wait

#ifndef CPU_CLOCK_FREQUENCY
#error CPU_CLOCK_FREQUENCY must be defined
#endif

#define LOOP_UNROLL_FACTOR  100

main:
#ifdef TWO_THREADS
        call    fork
#endif
        mov     ecx, (CPU_CLOCK_FREQUENCY / LOOP_UNROLL_FACTOR)
        jmp     1f

    .balign 64
1:
    .rept LOOP_UNROLL_FACTOR
        addps   xmm1, xmm1
        add     eax,  eax
        add     eax,  eax
        addps   xmm2, xmm2
        add     eax,  eax
        add     eax,  eax
        addps   xmm3, xmm3
        add     eax,  eax
        add     eax,  eax
    .endr
        dec     ecx
        jnz     1b

#ifdef TWO_THREADS
        push    0
        call    wait
        add     esp, 4
#endif
        mov     eax, 0
        ret
{% endhighlight %}

And the results of this benchmark from Intel Atom N450 @1.66GHz:

{% highlight sh %}
$ gcc -m32 -DCPU_CLOCK_FREQUENCY=1660000000 ht-bench.S && time ./a.out

real    0m6.034s
user    0m6.032s
sys     0m0.000s

$ gcc -m32 -DCPU_CLOCK_FREQUENCY=1660000000 -DTWO_THREADS ht-bench.S && time ./a.out

real    0m9.088s
user    0m18.097s
sys     0m0.028s
{% endhighlight %}

When running just one thread, 6 cycles are needed for each 9 instructions
from the loop body (ADDPS instructions can dual issue with ADD instructions,
so the whole loop is limited only by ADD instructions performance). And two
threads need 9 cycles for each 2 * 9 = 18 instructions, reaching the maximum
theoretically possible IPC = 2 for this processor.

This particular benchmark is quite interesting, because I used it to verify
the hypothesis from some other person, who suggested that at any given CPU cycle,
only the instructions from one hardware thread may be processed (either a single
instruction or a pair of instructions), but never from both. But just because
there are 12 ADD instructions to be executed in 9 cycles and they can't dual
issue within a single thread, there is no other way for the processor but to occasionally
execute a pair of ADD instructions fetched from different threads simultaneously.

Though there is still something wrong with Intel Atom hyper-threading
implementation, because actually removing all the ADDPS instructions from the
benchmark program causes performance regression for the multithreaded case.
It regresses to 12 cycles per each 2 * 6 = 12 remaining ADD instructions,
so hyper-threading becomes useless. Two threads running simultaneously need
exactly the same time to complete as would be needed to run just a single
thread twice. So those additional extra ADDPS instructions work as some kind
of "catalyst" and improve multithreaded performance for this particular code
sequence!

### But what about the hardware performance counters available in modern processors?

The hardware performance counters are surely useful. And moreover, they have many
interesting events monitored in addition to just a simple cycle counter, which
surely expose some additional information about what is happening inside of
the processor and help to better understand it.

However simple time based tests are just fine and may be preferable in some
cases. The most important is when you want to ask somebody else to
run some benchmark on his hardware, but the performance counters are not
accessible from the userspace by default and that person is reluctant
to touch the kernel.

On the other hand, the simple timer based tests described here are problematic
when something like [turbo-boost](http://en.wikipedia.org/wiki/Intel_Turbo_Boost)
is supported by the hardware and is enabled, causing the CPU clock frequency to drift.
