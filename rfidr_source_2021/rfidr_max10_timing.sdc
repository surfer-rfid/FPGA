#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#
#    rfidr_max10_timing.sdc
#
#    Author: Edward Keehr
#
#    Copyright Superlative Semiconductor LLC 2021
#    This source describes Open Hardware and is licensed under the CERN-OHL-P v2
#    You may redistribute and modify this documentation and make products
#    using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).
#    This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED
#    WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY
#    AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2
#    for applicable conditions.
#
#    This file sets timing contraints for the RFIDr design within the MAX10 FPGA
#
#    The pins of the design are:
#
#    clk_36_in_pin:                36MHz input clock from SDR ASIC. This clock may be active or inactive. We gate it internally for power savings
#    rst_n_pin:                    Asynchronous input reset pin. Is synchronized internally.
#    in_i_pin:                     Incoming 36MHz I data pin from SDR ASIC.
#    in_q_pin:                     Incoming 36MHz Q data pin from SDR ASIC.
#    out_i_pin:                    Outgoing 36MHz I data in to SDR ASIC. Synced to 36Mhz clock.
#    out_q_pin:                    Outgoing 36MHz Q data in to SDR ASIC. Synced to 36Mhz clock.
#    mcu_irq_pin:                  Outgoing interrupt to the MCU ASIC.
#    prphrl_pclk_pin:              SPI PCLK incoming from MCU ASIC. Treated as asynchronous and resynced in spi.v.
#    prphrl_cipo_pin:              SPI data output going to MCU ASIC. Currently combinationally driven :/. We'll need to review this. For now, assume it is flopped and reclocked with prphrl_pclk_pin.
#    prphrl_copi_pin:              SPI data input coming from MCU ASIC. Treated as asynchronous and resynced in spi.v.
#    prphrl_nps_pin:               SPI active low select signal coming from MCU ASIC. Treated as asynchronous and resynced in spi.v.
#    cntrlr_pclk_pin:              SPI controller clock. Running at 6MHz, div'd down by 4 from the 27P5MHz clock.
#    cntrlr_copi_cap0_rdio_pin:    SPI data output going to SDR and DTC0.
#    cntrlr_copi_cap1_pin:         SPI data output going to SDR and DTC0.
#    cntrlr_copi_cap2_pin:         SPI data output going to SDR and DTC0.
#    cntrlr_copi_cap3_pin:         SPI data output going to SDR and DTC0.
#    cntrlr_cipo_pin:              SPI data input from SDR. 
#    cntrlr_nps_rdio_pin:          SPI active low select going to SDR.
#    cntrlr_nps_dtc_pin:           SPI active low select going to all 4 DTC.
#
#    022716 - Notes upon file creation:
#
#    1. It may be easier from a timing perspective to have controller SPI output pins retime the data during passthru mode.
#    This certainly allows data to always be driven by flops, but may complicate SPI data reception at the MCU. We need to check
#    MCU data sheet to see what sort of RX data delay is acceptable.
#
#    2. As of now, we will not treat the internally generated cntrlr_pclk pin as a clock.
#    It may be easiest to treat it as a signal and just ensure that all of the signal output delays are constrained by some max/min from internal clock.
#
#    3. We have clock buffers and gated clocks in the clock generation module.
#
#    022816 - Upon second thought - SPI passthru will work much better if the data is buffered each way and then
#    played out back the other end. I mean, the buffers are there anyway, one might as well use them to avoid having wacky timing
#    constraints.
#
#    091916 - Update after we complete top level simulations
#
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

derive_pll_clocks
derive_clock_uncertainty

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Set clock parameters 
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

# CLK_55 is the 55MHz +/- 20% oscillator generated internally in the FPGA
# set    CLK_55_PERIOD            "15.1"
set    CLK_55_PERIOD              "11.1"
set    CLK_55_RTFT                "0.3"

# CLK_SDR is the 36MHz crystal-based clock which comes from the SDR
# Jitter number is just a guess, but should be small
# We need to take RT and FT seriously - it's going to be difficult to get it under 3ns on the board

set    CLK_SDR_PERIOD          "27.7"
set    CLK_SDR_RTFT            "3.0"
set    CLK_SDR_SKEW            "2.0"
set    VIRTUAL_CLK_SDR_DLY     "2.0"
set    VIRTUAL_CLK_SDR_SKEW    "2.0"

# CLK_CNTRLR_SPI is the outgoing controller SPI clock
set CLK_CNTRLR_SPI_PERIOD    [expr 8*$CLK_55_PERIOD]

# CLK_PRPHRL_SPI is the incoming peripheral SPI clock from the BTLE/MCU.
# Interestingly, it has a (low) maximum speed of 4Mbps
# It expects data to be valid on RE and for it to change on the FE
# The data sheet of NRF51822 says that RT/FT is 100ns maximum
# Also, it implies that duty cycle can be as low as 16%. Really?

set    CLK_PRPHRL_SPI_PERIOD         "200.0"
set    CLK_PRPHRL_SPI_RTFT           "20.0"
set    VIRTUAL_CLK_PRPHRL_SPI_DLY    "2.0"
set    VIRTUAL_CLK_CNTRLR_SPI_DLY    "2.0"

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Create source object clocks
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

# set_clock_transition apparently not supported by Synplify Pro
# set_clock_latency apprently not supported on virtual clocks by Synplify pro

# Create the clk_55 clock. It comes from the internal 55MHz oscillator
create_clock -name "CLK_55" -period $CLK_55_PERIOD -add [get_pins clk_and_reset_mgmt0|clk_mgmt0|osc_55mhz|int_osc_0|oscillator_dut|clkout]
#set_clock_transition    $CLK_55_RTFT    [get_clocks CLK_55]

# Create the SDR clock. It comes from the clk_36_in_pin
create_clock -name "CLK_SDR" -period $CLK_SDR_PERIOD [get_ports clk_36_in_pin]
#set_clock_transition    $CLK_SDR_RTFT    [get_clocks CLK_SDR]

# Create a virtual SDR clock to represent the data coming from the SX1257.
# Skew the data about 2ns from when the real clock is launched, to approximate actual operation.
create_clock -name "VIRTUAL_CLK_SDR" -period $CLK_SDR_PERIOD
#set_clock_transition    $CLK_SDR_RTFT    [get_clocks VIRTUAL_CLK_SDR]
#set_clock_latency    $VIRTUAL_CLK_SDR_DLY [get_clocks VIRTUAL_CLK_SDR]

# Create the peripheral SPI clock. It comes from the clk_36_in_pin
create_clock -name "CLK_PRPHRL_SPI" -period $CLK_PRPHRL_SPI_PERIOD [get_ports prphrl_pclk_pin]
#set_clock_transition    $CLK_PRPHRL_SPI_RTFT    [get_clocks CLK_PRPHRL_SPI]

# Create a virtual peripheral SPI clock to represent the data coming from the NRF51822.
# Skew the data about 2ns from when the real clock is launched, to approximate actual operation.
create_clock -name "VIRTUAL_CLK_PRPHRL_SPI" -period $CLK_PRPHRL_SPI_PERIOD
#set_clock_transition    $CLK_PRPHRL_SPI_RTFT    [get_clocks VIRTUAL_CLK_PRPHRL_SPI]
#set_clock_latency    $VIRTUAL_CLK_PRPHRL_SPI_DLY [get_clocks VIRTUAL_CLK_PRPHRL_SPI]

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Create generated clocks
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

# Create the internal 36MHz clock. Note that this comes out of a clock gate, then a clock buffer in the clk_mgmt.v module.
create_generated_clock    -name "CLK_36"                                          \
                          -source [get_ports clk_36_in_pin]                       \
                          -master_clock [get_clocks CLK_SDR]                      \
                          -divide_by 1                                            \
                          [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_36|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk]
                        
# Create the a debug 36MHz clock. Note that this comes out of a clock gate, then a clock buffer in the clk_mgmt.v module.
#create_generated_clock    -name "CLK_36_DEBUG"                                   \
#                          -source [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_36|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk]                        \
#                          -master_clock [get_clocks CLK_36]                      \
#                          -divide_by 1                                           \
#                          [get_ports clk_36_debug_pin]
                        
# Create the internal 27P5MHz clock. Note that this comes out of a register, then a clock buffer.
create_generated_clock    -name "CLK_27P5_UNBUF"                                                                                    \
                          -source [get_pins clk_and_reset_mgmt0|clk_mgmt0|osc_55mhz|int_osc_0|oscillator_dut|clkout]                \
                          -master_clock [get_clocks CLK_55]                                                                         \
                          -divide_by 3                                                                                              \
                          [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_27p5_unbuf|q]

# Create the internal 27P5MHz clock. Note that this comes out of a register, then a clock buffer.
create_generated_clock    -name "CLK_27P5"                                                               \
                        -source [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_27p5_unbuf|q]                \
                        -master_clock [get_clocks CLK_27P5_UNBUF]                                        \
                        -divide_by 1                                                                     \
                        [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_27p5|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk]

# Create the internal 4P5MHz unbuffered block. This clock is used to synchronize resets for 4.5MHz and 36MHz networks.
# The reason a separate clock is required here is because we need it to drive the resettable flops for gating CLK_4P5. 
create_generated_clock    -name "CLK_4P5_UNBUF"                                    \
                          -source [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_36|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk]                        \
                          -master_clock [get_clocks CLK_36]                        \
                          -divide_by 8                                             \
                          [get_pins clk_and_reset_mgmt0|clk_mgmt0|u_clk_mgmt_div_by_8_0|clk_4p5_unbuf_out|q]
                        
# Create the internal 4P5MHz clock. Note that this comes out of a clock gate, then a clock buffer in the clk_mgmt.v module.
create_generated_clock    -name "CLK_4P5"                                          \
                          -source [get_pins clk_and_reset_mgmt0|clk_mgmt0|u_clk_mgmt_div_by_8_0|clk_4p5_unbuf_out|q]                        \
                          -master_clock [get_clocks CLK_4P5_UNBUF]                 \
                          -divide_by 1                                             \
                          [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_4p5|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk]

# Create the outgoing SPI clock. Note that this comes out of a register, then an inferred I|O pin.
# Therefore we need to refer it to the outgoing port.
# Note that we aren't going to do anything fancy with the SPI pass-thru after all
# SPI passthru will be peripheral writing to buffer, then SPI sending and collecting data for later
# retrieval by the MCU.

create_generated_clock    -name "CLK_CNTRLR_SPI_PRE"                               \
                          -source [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_27p5|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk]                \
                          -master_clock [get_clocks CLK_27P5]                      \
                          -divide_by 4                                             \
                          [get_pins spi0|spi_cntrlr0|cntrlr_pclk|q]
                        
create_generated_clock    -name "CLK_CNTRLR_SPI"                                   \
                          -source [get_pins spi0|spi_cntrlr0|cntrlr_pclk|q]        \
                          -master_clock [get_clocks CLK_CNTRLR_SPI_PRE]            \
                          -divide_by 1                                             \
                          [get_ports cntrlr_pclk_pin]
    
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^                        
# Create clock gating checks for gated generated clocks
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

# For both clocks, we ensure that the gating signal does not change until 1ns after the clock signal changes
# Instead of using the actual clock name to constrain the timing, we refer to the output pin of the hand-instantiated AND gate used to
# perform the actual gating

# Apparently this is not supported by Synplify Pro

# For the 36MHz clock
# set_clock_gating_check    -setup 1 -hold 1 [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_36|clk_gate_and0|out_y]

# For the 4.5MHz clock
# set_clock_gating_check    -setup 1 -hold 1 [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_4p5|clk_gate_and0|out_y]

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Declare asynchronous clock groups
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

set_clock_groups     -asynchronous \
                     -group {CLK_55 CLK_27P5 CLK_27P5_UNBUF CLK_CNTRLR_SPI CLK_CNTRLR_SPI_PRE}\
                     -group {CLK_SDR CLK_36 CLK_4P5 CLK_4P5_UNBUF VIRTUAL_CLK_SDR}\
                     -group {CLK_PRPHRL_SPI VIRTUAL_CLK_PRPHRL_SPI}

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Declare exclusive clock groups
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
                    
# As far as we know, there is no multiplexing of clocks anywhere in the design, so we don't set any exclusive clock groups.

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Declare false paths
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

# First, we declare everything going through the synchronizers in clock_crossings.v is a false path
# Why do we include from clock, through block, to clock? Because this is a check that our assumptions about what we did in clock_crossings is correct.

# These commands are actually redundant in light of the set_clock_groups command.
# As proof, see the definition of set_clock_groups for Altera TimeQuest.
# Interpretation of this command may vary between tools, but here it is likely the same.
# We comment them out in order to minimize the number of warnings we are getting.

#set_false_path -from [get_clocks CLK_4P5]  -through    [get_cells clk_crossings0|*]    -to [get_clocks CLK_27P5]
#set_false_path -from [get_clocks CLK_27P5] -through    [get_cells clk_crossings0|*]    -to [get_clocks CLK_4P5]

# Somehow the timing tool is overlaying CLK_SDR through the CLK_4P5 clock gate and causing a timing violation 
# in the CDR DR integrators.
# In order to correct this, the tool is adding 133 extra LUT.
# Since this clock overlay should not be happening, we false path it to recover the LUT.

#set_false_path    -from [get_clocks CLK_SDR] -through [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_4p5|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk] -to [get_clocks CLK_4P5]
#set_false_path    -from [get_clocks CLK_4P5_UNBUF] -through [get_pins clk_and_reset_mgmt0|clk_mgmt0|clk_buf_4p5|altclkctrl_0|clk_gate_buf_altclkctrl_0_sub_component|clkctrl1|outclk] -to [get_clocks CLK_4P5]

# There is no constraint explicitly on the delay of the output pad.

set_false_path -from [get_pins spi0|spi_cntrlr0|cntrlr_pclk|q] -to [get_ports cntrlr_pclk_pin]

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Set timing requirements on data signaling pins to the SDR ASIC
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

#For the receiver, the I|Q output changes shortly after the RE of the clock and should be sampled on the falling edge (p21 of SDR data sheet)
#For the transmitter, the I|Q output must change shortly after the RE of clk36 and will be captured on the falling edge of said clock in the SDR
#The best reference we found on how to deal with this was AN433 from Altera. Here, we adopt the FPGA-centric output delay|timing requirements
#for the output pins due to the fact that the precise timing requirements of the SX1257 really aren't known.

#The first thing that we do is to set_output_delay between the 36MHz input clock and the I|Q data output pins.
#We constrain the delay from input clock to output data launch to be a minimum of 0 (trivial)
#and a maximum of half the clock period minus nearly a quarter of the clock period

set_output_delay -min 0 -clock [get_clocks CLK_SDR] -add_delay [get_ports out_i_pin]
set_output_delay -max [expr $CLK_SDR_PERIOD*0.5-$CLK_SDR_SKEW] -clock [get_clocks CLK_SDR] -add_delay [get_ports out_i_pin]
set_output_delay -min 0 -clock [get_clocks CLK_SDR] -add_delay [get_ports out_q_pin]
set_output_delay -max [expr $CLK_SDR_PERIOD*0.5-$CLK_SDR_SKEW] -clock [get_clocks CLK_SDR] -add_delay [get_ports out_q_pin]

#set_output_delay -min 0 -clock [get_clocks CLK_36_DEBUG] -add_delay [get_ports in_i_debug_pin]
#set_output_delay -max [expr $CLK_SDR_PERIOD*0.5-$CLK_SDR_SKEW-5] -clock [get_clocks CLK_36_DEBUG] -add_delay [get_ports in_i_debug_pin]
#set_output_delay -min 0 -clock [get_clocks CLK_36_DEBUG] -add_delay [get_ports in_q_debug_pin]
#set_output_delay -max [expr $CLK_SDR_PERIOD*0.5-$CLK_SDR_SKEW-5] -clock [get_clocks CLK_36_DEBUG] -add_delay [get_ports in_q_debug_pin]

#set_output_delay -min 0 -clock [get_clocks CLK_36] -add_delay [get_ports clk_36_debug_pin]
#set_output_delay -max [expr $CLK_SDR_PERIOD*0.5-$CLK_SDR_SKEW-5] -clock [get_clocks CLK_36] -add_delay [get_ports clk_36_debug_pin]

#The next thing we do is note that default setup timing checks occur from launch clock|to latch clock RE|nextRE, FE|nextFE, RE|nextFE, FE|nextRE
#and also note that default setup timing checks occur from RE from latch clock|to launch clock RE|existingRE, FE|existingFE, RE|nextFE, FE|nextRE
#We need to false path the same-edge timing checks so that they are not checked.

# 030116 - Apparently these are not needed for reasons described elsewhere in this file

# set_false_path -setup -rise_from [get_clocks CLK_SDR] -rise_to [get_ports out_i_pin]
# set_false_path -setup -fall_from [get_clocks CLK_SDR] -fall_to [get_ports out_i_pin]
# set_false_path -hold  -rise_from [get_clocks CLK_SDR] -rise_to [get_ports out_i_pin]
# set_false_path -hold  -fall_from [get_clocks CLK_SDR] -fall_to [get_ports out_i_pin] 
 
# set_false_path -setup -rise_from [get_clocks CLK_SDR] -rise_to [get_ports out_q_pin]
# set_false_path -setup -fall_from [get_clocks CLK_SDR] -fall_to [get_ports out_q_pin]
# set_false_path -hold  -rise_from [get_clocks CLK_SDR] -rise_to [get_ports out_q_pin]
# set_false_path -hold  -fall_from [get_clocks CLK_SDR] -fall_to [get_ports out_q_pin]

#The next thing that we do is to set_input_delay between the virtual clock and the I|Q data input pins.
#We assume that the delay may range from zero to several ns for the time being.
#Note that if we are setting input delay with a virtual clock, set input delay min is the negative skew, as shown on Page 50 of AN 334.
#However, if we were setting input delay with the actual clock, the 'min' value is greater than the hold time, which may be greater than the 'max' value.

set_input_delay -min [expr 0-$VIRTUAL_CLK_SDR_SKEW] -clock [get_clocks VIRTUAL_CLK_SDR] -add_delay [get_ports in_i_pin]
set_input_delay -max $VIRTUAL_CLK_SDR_SKEW -clock [get_clocks VIRTUAL_CLK_SDR] -add_delay [get_ports in_i_pin]
set_input_delay -min [expr 0-$VIRTUAL_CLK_SDR_SKEW] -clock [get_clocks VIRTUAL_CLK_SDR] -add_delay [get_ports in_q_pin]
set_input_delay -max $VIRTUAL_CLK_SDR_SKEW -clock [get_clocks VIRTUAL_CLK_SDR] -add_delay [get_ports in_q_pin]

#Finally, we must again false_path RE|nextRE transitions.
#Be careful, as in this case we need to constrain with respect to the clock which is actually latching the data, as opposed to the input clk.

#Actually, we apparently do not need to false path these transitions because the timing tool
#does not detect any paths from VIRTUAL_CLK_SDR to CLK_36 with RE|RE, FE|FE unateness.
#This is almost certainly because of the set_input_delay statements above where we DO NOT USE
#the -clock_fall option which would denote that the constraint refers to a FE-launched data edge.

#set_false_path -setup -rise_from [get_clocks VIRTUAL_CLK_SDR] -rise_to [get_clocks CLK_36]
#set_false_path -setup -fall_from [get_clocks VIRTUAL_CLK_SDR] -fall_to [get_clocks CLK_36]
#set_false_path -hold  -rise_from [get_clocks VIRTUAL_CLK_SDR] -rise_to [get_clocks CLK_36]
#set_false_path -hold  -fall_from [get_clocks VIRTUAL_CLK_SDR] -fall_to [get_clocks CLK_36] 

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Set timing requirements on SPI Master Output Pins
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

#    SX1257 SPI timing requirements:
#    COPI setup time    -    from COPI change to PCLK rising edge:    30ns min.     *** w|c setup time
#    COPI hold time     -    from PCLK rising edge to COPI change:    60ns min.     ***    w|c hold time
#    NPS setup time     -    from NPS falling edge to PCLK RE:        30ns min.
#    NPS hold time      -    from PCLK falling edge to NPS RE:        100ns min.    ***    meet this structurally
#    NPS high time between SPI access:                                20ns min.
#    Data hold and setup time - what is this???                       250ns min.
#    Says that typical rise time should be:                           5ns

#    DTC SPI timing requirements
#    Interesting - PEN is not active low, in fact, 
#    COPI setup time    -    from COPI valid to PCL RE:               13.2ns min.
#    COPI hold time     -    COPI must be valid after PCL RE:         13.2ns min.
#    NPS setup time     -    from PEN valid to PCL RE:                19.2ns min.
#    NPS hold time      -    PEN must be valid after PCL RE:          19.2ns min.
#    PEN falling edge to PEN rising edge:                             38.4ns min. (26MHz clock)

#    One interesting thing that needs to be noted here is that the DTC SPI PEN usage is different than usual usage.
#    For SX1257, NPS and COPI change on PCLK FE and are captured by PCLK RE at SX1257.
#    NPS falls at first COPI bit and rises just after last COPI bit.
#    Also for SX1257, CIPO changes on PCLK FE and should be captured on PCLK RE.

#    For DTC, PEN is inverted but otherwise the same.
#    We should suspend bus access for one 4.5MHz or 6MHz clock cycle in between DTC data transfers to meet the PEN FE to PEN RE requirement.

#    CLK_CNTRLR_SPI period is 166.66ns. Half of this is 83ns.

set    SX1257_TSETUP    "30.0"
set    SX1257_TMARGN    "10.0"
set    MSPI_OUT_MAX    [expr $SX1257_TSETUP+$SX1257_TMARGN]

set_output_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_cipo_pin]
set_output_delay -max $MSPI_OUT_MAX -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_cipo_pin]
set_output_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap0_rdio_pin]
set_output_delay -max $MSPI_OUT_MAX -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap0_rdio_pin]
set_output_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap1_pin]
set_output_delay -max $MSPI_OUT_MAX -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap1_pin]
set_output_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap2_pin]
set_output_delay -max $MSPI_OUT_MAX -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap2_pin]
set_output_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap3_pin]
set_output_delay -max $MSPI_OUT_MAX -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_copi_cap3_pin]
set_output_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_nps_rdio_pin]
set_output_delay -max $MSPI_OUT_MAX -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_nps_rdio_pin]
set_output_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_nps_dtc_pin]
set_output_delay -max $MSPI_OUT_MAX -clock [get_clocks CLK_CNTRLR_SPI] -add_delay [get_ports cntrlr_nps_dtc_pin]

# Multicycle paths are setup|hold 2|1 because data is latched on the opposite clock edge at the SX1257
# Use the -start option because launching clock is the source clock (CLK_27P5) and the latching clock at the SX1257 is CLK_CNTRLR_SPI
# Also, multicycle information is relative to the start clock, not the end clock.
# Use -through [get_pins because -from [get_ports and -through [get_ports don't work.

set_multicycle_path 2 -setup -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap0_rdio|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 1 -hold -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap0_rdio|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 2 -setup -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap1|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 1 -hold -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap1|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 2 -setup -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap2|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 1 -hold -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap2|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 2 -setup -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap3|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 1 -hold -start -through [get_pins spi0|spi_cntrlr0|cntrlr_copi_cap3|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 2 -setup -start -through [get_pins spi0|spi_cntrlr0|cntrlr_nps[1]|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 1 -hold -start -through [get_pins spi0|spi_cntrlr0|cntrlr_nps[1]|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 2 -setup -start -through [get_pins spi0|spi_cntrlr0|cntrlr_nps[0]|q] -to [get_clocks "CLK_CNTRLR_SPI"]
set_multicycle_path 1 -hold -start -through [get_pins spi0|spi_cntrlr0|cntrlr_nps[0]|q] -to [get_clocks "CLK_CNTRLR_SPI"]

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Set timing requirements on SPI Controller Input Pin, cntrlr_cipo_pin
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

#    This is an example of a clock launching data on a remote register on FE and capturing on RE
#    Since FPGA registers are going to have smaller setup and hold times as the SX1257, we just use the 
#    same requirements as in the previous section.

# 030416 - Currently we don't know what the minimum and maximum delays are for the SX1257.
# It may be that we have to latch the cntrlr_cipo register with the SPI clock.
# For now, keep it as it is, with a maximum delay of 26ns.

#    Note that incoming data is launched on the falling edge of SPI clk and latched on the RE
#    So, we use -clock_fall option

set_input_delay -min 0 -clock [get_clocks CLK_CNTRLR_SPI] -clock_fall -add_delay [get_ports cntrlr_cipo_pin]
set_input_delay -max [expr $CLK_55_PERIOD*1.5] -clock [get_clocks CLK_CNTRLR_SPI] -clock_fall -add_delay [get_ports cntrlr_cipo_pin]

# Multicycle paths are setup|hold 2|1 because data is latched on the opposite clock edge back at the input pin.
# Use the -end option because launching clock is CLK_CNTRLR_SPI and the latching clock is the source clock.
# Also, multicycle information is relative to the end clock, not the start clock.
# Use -through [get_pins because -from [get_ports and -through [get_ports don't work.

set_multicycle_path 2 -setup -end -from [get_clocks CLK_CNTRLR_SPI] -through [get_pins spi0|spi_cntrlr0|cntrlr_rx_buf[0]|q]
set_multicycle_path 1 -hold -end -from [get_clocks CLK_CNTRLR_SPI] -through [get_pins spi0|spi_cntrlr0|cntrlr_rx_buf[0]|q] 

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Set timing requirements on mcu_irq_pin, an asynchronous output pin.
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

#    Just false-path it

set_false_path    -to [get_ports mcu_irq_pin]

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Set timing requirements on asynchronous input pins: rst_n and the 3 peripheral SPI inputs
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

#    According to http://www.alteraforum.com/forum/showthread.php?t=28070, asynchronous inputs are false-pathed
#    Some people constrain with set_multicycle_path, but the forum doesn't say why.
#    One thing that we need to do though is to keep the delays of the 3 peripheral inputs within one 27P5MHz clock cycle of each other so that
#    our edge-detecting methodology isn't compromised.
#    This is done by constraining the inputs relative to the peripheral spi clock

#    Below, the real delay allowable is half of the 27P5MHz data period, or about 20ns.

#    Note that incoming data is launched on the falling edge of SPI clk and latched on the RE
#    So, we use -clock_fall option

#    Why do we use a negative minimum input delay? Because the skew can be such that the data arrives before the virtual peripheral spi clock

set_input_delay -min [expr -0.5*$CLK_55_PERIOD] -clock [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -clock_fall -add_delay [get_ports prphrl_copi_pin]
set_input_delay -max [expr 0.5*$CLK_55_PERIOD] -clock [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -clock_fall -add_delay [get_ports prphrl_copi_pin]
set_input_delay -min [expr -0.5*$CLK_55_PERIOD] -clock [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -clock_fall  -add_delay [get_ports prphrl_nps_pin]
set_input_delay -max [expr 0.5*$CLK_55_PERIOD] -clock [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -clock_fall  -add_delay [get_ports prphrl_nps_pin]

#    We must again false_path RE/nextRE transitions.
#    Be careful, as in this case we need to constrain with respect to the clock which is actually latching the data, as opposed to the input clk.
#    But in this case, the interface is actually asynchronous and we need to constrain back with respect to the peripheral SPI clock.

#    These false paths not needed for reasons described elsewhere in this file

# set_false_path -setup -rise_from [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -rise_to [get_clocks CLK_PRPHRL_SPI]
# set_false_path -setup -fall_from [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -fall_to [get_clocks CLK_PRPHRL_SPI]
# set_false_path -hold  -rise_from [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -rise_to [get_clocks CLK_PRPHRL_SPI]
# set_false_path -hold  -fall_from [get_clocks VIRTUAL_CLK_PRPHRL_SPI] -fall_to [get_clocks CLK_PRPHRL_SPI] 

#    Finally, false path the rst_n pin
#    We comment out most of these because most of the paths don't exist in the first place and having the 
#    check in will result in a warning message.

set_false_path -from [get_ports rst_n_pin]

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Set timing requirements on prphrl_cipo_pin
#vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv

# Ideally, when sending back data to an interface clocked by another chip, we retime the data with the clock sent by said chip.
# However, in the case of SPI this results in unacceptable delay due to the resynchronizers used to accept the input data.
# Rather, we use the fact that the 27P5MHz clock is much faster than the SPI clock to send the data back.
# But, there is a requirement on output delay! Namely, the 27P5MHz clock may detect the SPI clock FE nearly 1 27P5MHz clock late.
# And then, there is another delay due to the double flop synchronization.
# This means that the maximum allowable max delay is 1/27P5MHz.
# Some of this maximum allowable delay will be eaten up inside the chip.
# We assume 10ns max outside the chip.

set_output_delay -min 0 -clock [get_clocks CLK_27P5] -add_delay [get_ports prphrl_cipo_pin]
set_output_delay -max 10 -clock [get_clocks CLK_27P5] -add_delay [get_ports prphrl_cipo_pin]