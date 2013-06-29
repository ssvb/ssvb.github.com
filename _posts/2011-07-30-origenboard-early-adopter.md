---
layout: post
title: Origenboard, early adopter impressions
tags: [arm, samsung]
---

{{ page.title }}
================

### A little bit of rant

Since a few days ago, I'm a somewhat happy owner of [origenboard](http://www.origenboard.org/) from the first batch.
So why I'm not totally happy yet? Actually I expected that the board would be easy to get up
and running, considering that the same
[Exynos 4210 SoC](http://www.samsung.com/global/business/semiconductor/productInfo.do?fmly_id=844&partnum=Exynos%204210)
is used in a rather popular
[Samsung Galaxy S2](http://en.wikipedia.org/wiki/Samsung_Galaxy_S_II) smartphone already
available on the market (which means that the SoC intself should not have any serious hardware
problems by now). And also because of [the demos like this](http://www.youtube.com/watch?v=vLUne-yDzVE) (which means that at least Linaro should have some usable linux kernel to run these demos on).
So there is no reason not to expect some validation SD card image readily available
for download and some basic getting started instructions, right?

The reality is that the only support area on [origenboard](http://www.origenboard.org/) website is a pre-moderated forum, where
a few other fellow users [have asked about the sources of u-boot](http://www.origenboard.org/forum/viewtopic.php?f=8&t=4).
And my reply to that topic, trying to share the information with them, has not yet passed through moderation as of today.
Hopefully the initial mess will be resolved soon and there will be some usable communication
channel for origenboard users in the future. But considering that there are only [30 days of warranty](http://www.origenboard.org/news/?p=18),
it may be a bit disturbing not to be able to use some validation image and test the board for hardware defects right away.

Because origenboard website refers to [Linaro](http://www.linaro.org/) as the intended provider
of the software part, I tried to see if Linaro can offer something usable for origenboard now.
The information seems to be scarce and scattered there currently (I looked at the downloads area, wiki
pages and asked around on #linaro irc channel). And the downside is that the maturity of
the [currently provided linaro kernel 2.6.39-2011.07](http://git.linaro.org/gitweb?p=people/angus/linux-linaro-2.6.39.git;a=shortlog;h=refs/tags/2.6.39-2011.07) appears
to be not very good yet.

My experience with this board so far is the following:

* [linaro kernel](http://git.linaro.org/gitweb?p=people/angus/linux-linaro-2.6.39.git;a=shortlog;h=refs/tags/2.6.39-2011.07): USB does not work (so no USB ethernet), only a single CPU core is available. Also there is something on HDMI, but monitor reports "out of range" error
* [insignal kernel](http://git.insignal.co.kr/?p=linux-2.6-insignal-dev.git;a=shortlog;h=3645a1cb402be68b83feb9f9c8d7af2728cc8878): USB works, both CPU cores are available (though running at only 1GHz), no HDMI output to monitor at all (and a few random configuration tweaks did not help)

But in any case, the insignal kernel at least provides a usable headless configuration.
And this is surely better than nothing. Also on a positive side, the current situation
inspired me to finally start a blog and post about something. Hopefully blogging could
be entertaining for both me and the prospective readers :)

### Board setup notes

The instructions below are not complete, but are supposed to highlight the most important
steps. All of this has been discovered by using trial and error
method and also by bugging relevant people on #linaro irc channel (thanks for their patience). A total
newbie may still get stuck, but this information should be sufficient for those
having some experience installing linux on any other ARM development boards.

Also this information is likely to get outdated very soon (even if assuming that it was useful in the first place).

#### u-boot and linux kernel sources

The combination of u-boot and kernel that I'm using at the moment is the following:

* u-boot: [linaro-origen-2011.07](http://git.linaro.org/gitweb?p=people/angus/u-boot.git;a=shortlog;h=refs/tags/linaro-origen-2011.07)
* kernel: [insignal 3645a1cb402be68b83feb9f9c8d7af2728cc8878](http://git.insignal.co.kr/?p=linux-2.6-insignal-dev.git;a=shortlog;h=3645a1cb402be68b83feb9f9c8d7af2728cc8878)

This kernel needs to be patched when used with this particular u-boot (as advised by linaro guys):
{% highlight diff %}
diff --git a/arch/arm/mach-s5pv310/mach-origen.c b/arch/arm/mach-s5pv310/mach-origen.c
index e24e8d1..977f0c9 100644
--- a/arch/arm/mach-s5pv310/mach-origen.c
+++ b/arch/arm/mach-s5pv310/mach-origen.c
@@ -549,7 +549,7 @@ static void __init origen_fixup(struct machine_desc *desc,
 	mi->nr_banks = 2;
 }
 
-#if 0
+#if 1
 MACHINE_START(ORIGEN, "ORIGEN")
 #else
 MACHINE_START(SMDKV310, "SMDKV310")
-- 
1.7.3.4
{% endhighlight %}

Compile u-boot (to get u-boot-mmc-spl.bin and u-boot.bin):
{% highlight sh %}
make CROSS_COMPILE=arm-none-linux-gnueabi- mrproper
make CROSS_COMPILE=arm-none-linux-gnueabi- origen_config
make CROSS_COMPILE=arm-none-linux-gnueabi-
{% endhighlight %}

Compile the kernel (to get uImage):
{% highlight sh %}
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi- mrproper
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi- origen_android_defconfig
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi- menuconfig
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi- -j8 uImage
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi- -j8 modules
scp arch/arm/boot/uImage root@origen:/mnt/mmcblk0p1/uImage
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabi- modules_install INSTALL_MOD_PATH=/mnt/origen-nfs-root
{% endhighlight %}

Be sure to tweak configuration options as needed (add drivers for USB ethernet adapters, statically compile in ext3 support, disable CONFIG_ANDROID_PARANOID_NETWORK, etc.)

#### SD card layout

This section is based on the information from [linaro wiki](https://wiki.linaro.org/Boards/Origen/Setup).
In order to successfully boot the system, u-boot binary needs to be put into certain predefined areas on SD card.

<table border=1><tr>
<td colspan="4" style="text-align:center">Raw Sectors (sector size = 512 bytes)</td>
  <td colspan="3" style="text-align:center">Partitions </td>
</tr>
<tr>
  <td>0</td>
  <td>1 to 32</td>
  <td>33 to 64</td>
  <td>65 to 1088</td>
  <td>FAT partition</td>
  <td>any linux partition</td>
</tr>
<tr>
  <td>MBR</td>
  <td>u-boot-mmc-spl.bin</td>
  <td>u-boot environment </td>
  <td>u-boot.bin </td>
  <td>uImage (kernel)</td>
  <td>root filesystem</td>
</tr>
</table>

Writing u-boot into raw sectors of SD card (assuming that SD card is detected as /dev/sdb):
{% highlight sh %}
# dd if=u-boot-mmc-spl.bin of=/dev/sdb bs=512 seek=1
# dd if=u-boot.bin of=/dev/sdb bs=512 seek=65
{% endhighlight %}

#### Install rootfs for the distro of your choice and boot the system

Typical u-boot environment (when using rootfs from SD card instead of NFS):
{% highlight sh %}
baudrate=115200
bootargs=root=/dev/mmcblk0p2 rw rootwait console=ttySAC2,115200
bootcmd=fatload mmc 0 40007000 uImage; bootm 40007000
bootdelay=3
stderr=serial
stdin=serial
stdout=serial
{% endhighlight %}

But in order to get login prompt on serial console, <b>s3c2410_serial2</b> (not <b>ttySAC2</b>) needs to be added to /etc/inittab and /etc/securetty. That's a bit weird, but I have not tried to look into it yet.

Finally turn on the board by pressing <b>switch</b> and then <b>power</b> button.

#### Update from 2011-09-19

Linaro kernel is getting better. Now it supports cpufreq (using 1.2GHz CPU clock frequency is possible), has
a somewhat working USB support (is very slow and sometimes gets stuck for a few seconds), and a somewhat
usable HDMI output which is hardcoded to use 1920x1080 resolution and use only a small 1024x600 area in
the center. Still compared to the initial state, it is a major improvement.

I guess, everything is going to be in a much better shape in a few more months.
