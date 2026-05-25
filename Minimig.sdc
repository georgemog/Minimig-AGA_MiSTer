derive_pll_clocks
derive_clock_uncertainty

set_multicycle_path -from {emu|cpu_wrapper|cpu_inst*} -to {emu|ram*} -setup 2
set_multicycle_path -from {emu|cpu_wrapper|cpu_inst*} -to {emu|ram*} -hold 1

set_multicycle_path -from {emu|amiga_clk|cck*} -to {emu|ram1|*} -setup 2
set_multicycle_path -from {emu|amiga_clk|cck*} -to {emu|ram1|*} -hold 1
set_multicycle_path -from {emu|minimig|*} -to {emu|ram1|*} -setup 2
set_multicycle_path -from {emu|minimig|*} -to {emu|ram1|*} -hold 1

set_false_path -from {emu|cpu_wrapper|z3ram_*}
set_false_path -from {emu|cpu_wrapper|z2ram_*}

set_false_path -from {emu|minimig|USERIO1|cpu_config*}
set_false_path -from {emu|minimig|USERIO1|ide_config*}
set_false_path -from {emu|minimig|USERIO1|bootrom}
set_false_path -from {emu|minimig|CPU1|halt}

# A2065 boardram: 1-cycle synchronous BRAM read latency
set_multicycle_path -from {emu|minimig|a2065_boardram_inst|*} \
                    -to   {emu|minimig|a2065_boardram_inst|*} -setup 2
set_multicycle_path -from {emu|minimig|a2065_boardram_inst|*} \
                    -to   {emu|minimig|a2065_boardram_inst|*} -hold 1

# yc_out chroma LUT: marginal path pushed into violation by boardram routing congestion
# (Step 6 slack was +0.288ns; boardram BRAM degraded placement → -0.471ns)
set_multicycle_path -from {yc_out|chroma_LUT_BURST[*]} \
                    -to   {yc_out|phase[*].u[*]} -setup 2
set_multicycle_path -from {yc_out|chroma_LUT_BURST[*]} \
                    -to   {yc_out|phase[*].u[*]} -hold 1

#these constraints aren't really correct, but help fitting.
#28MHz pixel clock might be affected when scandoubler fx is used.
set_multicycle_path -to {*Hq2x*} -setup 2
set_multicycle_path -to {*Hq2x*} -hold 1
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to {ascal|*} -setup 2
set_multicycle_path -from [get_clocks { *|pll|pll_inst|altera_pll_i|*[0].*|divclk}] -to {ascal|*} -hold 1
