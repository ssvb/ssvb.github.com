#!/usr/bin/env ruby
#
# Copyright © 2014 Siarhei Siamashka <siarhei.siamashka@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'RMagick'

$PAGE_SIZE = 4096

$VISUALIZE_CYCLES  = 740
$TEXT_LABEL_HEIGHT = 16
$TEXT_LABEL_WIDTH  = 40

def rmagick_rectangle(old_cycles, new_cycles, bank_num, color)
    $gc.fill(color)
    $gc.rectangle($TEXT_LABEL_WIDTH + old_cycles, bank_num * $TEXT_LABEL_HEIGHT,
                  $TEXT_LABEL_WIDTH + new_cycles - 1, (bank_num + 1) * $TEXT_LABEL_HEIGHT - 1)
    $gc.draw($image)
end

def simulate_cpu_vs_debe_competition(args)
    dram_freq = args[:dram_freq]
    number_of_bursts_in_cpu_access = args[:number_of_bursts_in_cpu_access]
    backwards = args[:walk_memory_in_backwards_direction]

    xres = args[:xres]
    yres = args[:yres]
    hz   = args[:hz]
    bpp  = args[:bpp]

    $image = Magick::Image.new($VISUALIZE_CYCLES, $TEXT_LABEL_HEIGHT * 8)
    $gc = Magick::Draw.new
    $gc.fill('lightgray')
    $gc.rectangle($TEXT_LABEL_WIDTH, 0, $VISUALIZE_CYCLES, $TEXT_LABEL_HEIGHT * 8)
    $gc.draw($image)

    # Text labels
    0.upto(7) {|bank_num|
        text = Magick::Draw.new
        text.font_family = 'helvetica'
        text.pointsize = 10
        text.fill = 'black'
        text.gravity = Magick::WestGravity
        text.annotate($image, $TEXT_LABEL_WIDTH, $TEXT_LABEL_HEIGHT, 0,
                              $TEXT_LABEL_HEIGHT * bank_num, sprintf("BANK%d", bank_num))
    }

    # Cubieboard1 DRAM timings
    dramc = {
        :dram_freq      => dram_freq,
        :CL             => 6,
        :tRP            => 6,
        :tRCD           => 6,
        :bank_user      => ["CPU"] * 8,
        :bank_last_use  => [-1000] * 8,
        :page_size      => $PAGE_SIZE,
        :burst_bytes    => 32,
        :cycle_counter  => 0,
        :byte_counters  => {"CPU" => 0, "DEBE" => $PAGE_SIZE * 4}
    }

    def dramc_simulate_burst_transfer(dramc, user, backwards, number_of_bursts)
        bank_num = (dramc[:byte_counters][user] / dramc[:page_size]) % 8
        bank_num = 7 - bank_num if backwards

        bank_switch_penalty = dramc[:bank_last_use][bank_num] +
                              dramc[:tRP] + dramc[:tRCD] + dramc[:CL] - dramc[:cycle_counter]

        if dramc[:bank_user][bank_num] != user && bank_switch_penalty > 0 then
            old_cycle_counter = dramc[:cycle_counter]
            dramc[:cycle_counter] += bank_switch_penalty
            if dramc[:cycle_counter] <= $VISUALIZE_CYCLES then
                rmagick_rectangle(old_cycle_counter, dramc[:cycle_counter], bank_num, '#FF8080')
            end
        end

        old_cycle_counter = dramc[:cycle_counter]
        dramc[:cycle_counter] += 4 * number_of_bursts
        if dramc[:cycle_counter] <= $VISUALIZE_CYCLES then
            rmagick_rectangle(old_cycle_counter, dramc[:cycle_counter], bank_num,
                              (user == "CPU" ? 'green' : 'blue'))
        end

        dramc[:bank_user][bank_num] = user
        dramc[:bank_last_use][bank_num] = dramc[:cycle_counter]
        dramc[:byte_counters][user] += number_of_bursts * dramc[:burst_bytes]
    end

    cycles_between_fb_reads = dram_freq.to_f * 1000000 /
                              (xres * yres * bpp * hz / (dramc[:burst_bytes] * 8))

    fb_reads = 0
    1.upto(100000) {
        while dramc[:cycle_counter] >= cycles_between_fb_reads * fb_reads do
            # DEBE requests just one burst in forward direction
            dramc_simulate_burst_transfer(dramc, "DEBE", false, 1)
            fb_reads += 1
        end
        dramc_simulate_burst_transfer(dramc, "CPU", backwards,
                                      args[:number_of_bursts_in_cpu_access])
    }

    $image.write(sprintf("%dx%d-%d@%dhz-ddr3-%dmhz-simulated-%s.png",
                         xres, yres, bpp, hz, dram_freq, (backwards ? "backwards-memset" : "memset")))

    return {
        :theoretical_bandwidth => dramc[:dram_freq] * dramc[:burst_bytes] / 4,
        :cpu_bandwidth         => dramc[:byte_counters]["CPU"] *
                                  dramc[:dram_freq] / dramc[:cycle_counter],
        :debe_bandwidth        => dramc[:byte_counters]["DEBE"] *
                                  dramc[:dram_freq] / dramc[:cycle_counter],
        :cycles_between_fb_reads => cycles_between_fb_reads,
    }
end

if not ARGV[0] then
    printf("Usage: #{$PROGRAM_NAME} [xres] [yres] [dram_page_size]\n")
    exit(1)
end

# Run all simulations

xres = (ARGV[0] or "1920").to_i
yres = (ARGV[1] or "1080").to_i
$PAGE_SIZE = (ARGV[2] or "4096").to_i

[false, true].each {|direction|

printf("
<table border=1 style='border-collapse: collapse; empty-cells: show; font-family: arial; font-size: small; white-space: nowrap; background: #F0F0F0;'>
<caption><b>Table ?. Memory write bandwidth available to the CPU (%s)</b></caption>
<tr><th><th colspan=6>Memory clock speed
<tr><th>Video mode<th>360MHz<th>384MHz<th>408MHz<th>432MHz<th>456MHz<th>480MHz\n", (direction ? "backwards memset" : "memset"))

[32, 24].each {|bpp|
[60, 56, 50].each {|hz|

printf("<tr><td>1920x1080, %dbpp, %dHz", bpp, hz)

(360 .. 480).step(24) {|dram_freq|

    result = simulate_cpu_vs_debe_competition({
           :xres => xres, :yres => yres, :hz => hz, :bpp => bpp,
           :dram_freq => dram_freq,
           :number_of_bursts_in_cpu_access => 1,
           :walk_memory_in_backwards_direction => direction})

    printf("<td bgcolor='%s'>%d MB/s", (result[:cpu_bandwidth] < 550 ? "red" : "lightgreen"),
                                       result[:cpu_bandwidth])
}

printf("</tr>\n")

}}

printf("</table>\n")

}
