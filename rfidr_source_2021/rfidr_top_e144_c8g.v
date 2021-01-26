/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : RFIDr Top Level                                                        //
//                                                                                 //
// Filename: rfidr_top_e144_c8g.v                                                  //
// Creation Date: 1/10/2016                                                        //
// Author: Edward Keehr                                                            //
//                                                                                 //
// Copyright Superlative Semiconductor LLC 2021                                    //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2     //
// You may redistribute and modify this documentation and make products            //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).        //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                    //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2              //
// for applicable conditions.                                                      //
//                                                                                 //
// Description:                                                                    //
//                                                                                 //
//    This is the top level for the entire digital back end of the software-       //
//    defined RFID reader. It is intended to fit into an Altera/Intel 10M02 FPGA   //
//    with 36 pins. The current implementation is synthesized for an E144 package  //
//    to ease the assembly of the RFID reader FPGA.                                //
//                                                                                 //
//    Revisions:                                                                   //
//    111016 - Added support for true inventorying                                 //
//    082817 - Upgraded DTC control for automated TMN measurements.                //
//    Also remove input buffering and re-output.                                   //
//    021518 - Added support for kill command                                      //
//    120520 - Added support for improved-robustness programming.                  //
//                                                                                 //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module rfidr_top_e144_c8g (
// {ALTERA_ARGS_BEGIN} DO NOT REMOVE THIS LINE!
    clk_36_in_pin,
    rst_n_pin,
    in_i_pin,
    in_q_pin,
    out_i_pin,
    out_q_pin,
    mcu_irq_pin,
    prphrl_pclk_pin,
    prphrl_cipo_pin,
    prphrl_copi_pin,
    prphrl_nps_pin,
    cntrlr_pclk_pin,
    cntrlr_copi_cap3_pin,
    cntrlr_copi_cap2_pin,
    cntrlr_copi_cap1_pin,
    cntrlr_copi_cap0_rdio_pin,
    cntrlr_cipo_pin,
    cntrlr_nps_rdio_pin,
    cntrlr_nps_dtc_pin
    
// {ALTERA_ARGS_END} DO NOT REMOVE THIS LINE!
);
// {ALTERA_IO_BEGIN} DO NOT REMOVE THIS LINE!

    //Note that Quartus has a known bug wherein you need to use Verilog 2001 style attributes in order for them all to be picked up properly
    //Put all the attributes in the same attribute statement otherwise only the last one will be utilized    
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) input     clk_36_in_pin                /*synthesis chip_pin = "91" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) input     rst_n_pin                    /*synthesis chip_pin = "19" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) input     in_i_pin                     /*synthesis chip_pin = "89" */;     
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) input     in_q_pin                     /*synthesis chip_pin = "88" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"16MA\" ; -name SLEW_RATE \"2\" "*) output   out_i_pin                    /*synthesis chip_pin = "67" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"16MA\" ; -name SLEW_RATE \"2\" "*) output   out_q_pin                    /*synthesis chip_pin = "69" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    mcu_irq_pin                  /*synthesis chip_pin = "106" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) input     prphrl_pclk_pin              /*synthesis chip_pin = "113" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    prphrl_cipo_pin              /*synthesis chip_pin = "115" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) input     prphrl_copi_pin              /*synthesis chip_pin = "130" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) input     prphrl_nps_pin               /*synthesis chip_pin = "13" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    cntrlr_pclk_pin              /*synthesis chip_pin = "90" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    cntrlr_copi_cap0_rdio_pin    /*synthesis chip_pin = "52" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) inout     cntrlr_cipo_pin              /*synthesis chip_pin = "54" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    cntrlr_nps_rdio_pin          /*synthesis chip_pin = "42" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    cntrlr_nps_dtc_pin           /*synthesis chip_pin = "40" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    cntrlr_copi_cap3_pin         /*synthesis chip_pin = "26" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    cntrlr_copi_cap2_pin         /*synthesis chip_pin = "25" */;
    (* altera_attribute = "-name IO_STANDARD \"3.0-V LVCMOS\" ; -name CURRENT_STRENGTH_NEW \"4MA\" ; -name SLEW_RATE \"2\" "*) output    cntrlr_copi_cap1_pin         /*synthesis chip_pin = "105" */;
    
// {ALTERA_IO_END} DO NOT REMOVE THIS LINE!
// {ALTERA_MODULE_BEGIN} DO NOT REMOVE THIS LINE!
    //Wire declarations
    
    wire             rst_4p5_sw, rst_n_27p5, rst_n_4p5, rst_n_36_in, rst_n_36;
    wire             clk_27p5, clk_4p5, clk_4p5_stretch_en, clk_36_start, clk_36, clk_36_valid, clk_36_running;
    wire             radio_busy_4p5, radio_done_4p5, txcancel_rdy_4p5, radio_busy_27p5, radio_done_27p5, txcancel_rdy_27p5, txcancel_csel_4p5, txcancel_csel_27p5;
    wire    [3:0]    sdm_offset_27p5, sdm_offset_4p5, zgn_offset_27p5, zgn_offset_4p5;
    wire    [2:0]    write_cntr_4p5, write_cntr_27p5;
    wire    [1:0]    radio_mode_27p5, radio_mode_4p5, radio_exit_code_4p5, radio_exit_code_27p5;
    wire             alt_radio_fsm_loop_27p5, alt_radio_fsm_loop_4p5, end_radio_fsm_loop_27p5, end_radio_fsm_loop_4p5, use_select_pkt_27p5, use_select_pkt_4p5;
    wire    [7:0]    txcancel_data_4p5, txcancel_data_27p5;
    wire             wave_storage_done_4p5, wave_storage_running_4p5, wave_storage_done_27p5, wave_storage_running_27p5;
    wire             radio_go_27p5, radio_ack_27p5, radio_go_4p5, radio_ack_4p5;
    wire             prphrl_copi_27p5, prphrl_nps_27p5, prphrl_pclk_27p5;
    wire             radio_done, radio_running;
    wire    [9:0]    radio_sram_addr_27p5, txcancel_sram_addr_27p5;
    wire    [8:0]    radio_sram_address_tx, radio_sram_address_rx;
    wire    [7:0]    radio_sram_wdata_27p5, txcancel_sram_wdata_27p5, radio_sram_rdata_27p5, txcancel_sram_rdata_27p5, radio_sram_rdata_4p5, radio_sram_wdata_4p5;
    wire             radio_sram_we_data_27p5, txcancel_sram_we_data_27p5, radio_sram_wren, radio_sram_txrxaccess;
    wire    [12:0]   wvfm_sram_addr;
    wire    [7:0]    wvfm_sram_rdata_27p5;
    wire             wvfm_go;
    wire    [7:0]    wvfm_offset_27p5;
    wire             radio_go, irq_ack;
    wire             rx_done, rx_timeout, rx_fail_crc, tx_done, last_tx_write, rx_block, rx_go, tx_go, tx_en;
    wire             tx_error_27p5, tx_error_4p5;
    wire    [4:0]    radio_state;
    wire    [15:0]   dc_i, dc_q, chfilt_i, chfilt_q;
    wire             dc_ready_i, dc_ready_q, in_posedge_i, in_posedge_q, out_i_baseband_4p5;
    wire             use_i_27p5, use_i_4p5;
    wire             bit_decision_from_dr, shift_rn16_from_dr, shift_rn16_to_txgen, shift_handle_from_dr, shift_handle_to_txgen;
    wire             rn16_to_txgen, handle_to_txgen;
    wire             irq_fsm, irq_clock, irq_spi;
    wire    [14:0]   txcancel_data_aux_4p5, txcancel_data_aux_27p5;
    wire             dtc_test_mode;
    wire             kill_write_pkt_4p5, kill_write_pkt_27p5, kill_first_pkt;

    //Modules
    
    clk_and_reset_mgmt    clk_and_reset_mgmt0(
        //Clk mgmt Inputs
        .clk_36_in(clk_36_in_pin),
        .clk_36_start(clk_36_start),                    //Needs to come from spi.v
        //Reset mgmt Inputs
        .rst_n_ext(rst_n_pin),                          //Active low reset from external pin
        .rst_4p5_sw(rst_4p5_sw),
        //Clk mgmt outputs
        .clk_36(clk_36),
        .clk_4p5(clk_4p5),
        .clk_4p5_stretch_en(clk_4p5_stretch_en),
        .clk_36_valid_reg(clk_36_valid),                //Needs to go to spi.v
        .clk_36_running_reg(clk_36_running),            //Needs to go to spi.v
        .clk_36_irq(irq_clock),
        .clk_27p5(clk_27p5),
        //Reset Mgmt Outputs
        .rst_n_27p5(rst_n_27p5),
        .rst_n_4p5(rst_n_4p5),
        .rst_n_36_in(rst_n_36_in),
        .rst_n_36(rst_n_36)
    );
        
    irq_merge    irq_merge0(
        .irq_fsm(irq_fsm),
        .irq_clock(irq_clock),
        .irq_spi(irq_spi),
        .irq_extra(1'b0),
        .clk_27p5(clk_27p5),
        .rst_n_27p5(rst_n_27p5),
        .mcu_irq(mcu_irq_pin)
    );
    
    clk_crossings    clk_crossings0(
        //Inputs from 4.5MHz domain to 27p5MHz domain
        .radio_busy_in(radio_busy_4p5),                    //From radio_fsm.v to rfidr_fsm.v
        .radio_exit_code_in(radio_exit_code_4p5),          //From radio_fsm.v to spi.v
        .radio_done_in(radio_done_4p5),                    //From radio_fsm.v to rfidr_fsm.v
    
        .txcancel_data_in(txcancel_data_4p5),              //From tx_cancel.v to spi.v
        .txcancel_data_aux_in(txcancel_data_aux_4p5),      //From tx_cancel.v to spi.v
        .txcancel_csel_in(txcancel_csel_4p5),              //From tx_cancel.v to spi.v
        .txcancel_rdy_in(txcancel_rdy_4p5),                //From tx_cancel.v to spi.v
        
        .tx_error_in(tx_error_4p5),
        .write_cntr_in(write_cntr_4p5),
    
        .wave_storage_done_in(wave_storage_done_4p5),
        .wave_storage_running_in(wave_storage_running_4p5),
    
        //Inputs from 27p5MHz domain to 4.5MHz domain
        .radio_go_in(radio_go_27p5),                        //From rfidr_fsm.v to radio_fsm.v
        .radio_mode_in(radio_mode_27p5),                    //From spi.v to radio_fsm.v
        .radio_ack_in(radio_ack_27p5),                      //From spi.v to tx_cancel.v
        .use_i_in(use_i_27p5),
        .alt_radio_fsm_loop_in(alt_radio_fsm_loop_27p5),
        .end_radio_fsm_loop_in(end_radio_fsm_loop_27p5),
        .use_select_pkt_in(use_select_pkt_27p5),
        .kill_write_pkt_in(kill_write_pkt_27p5),
        .sdm_offset_in(sdm_offset_27p5),
        .zgn_offset_in(zgn_offset_27p5),
    
        //Inputs from external async domain to 27p5MHz domain
    
        .prphrl_copi_in(prphrl_copi_pin),                    //From external to spi.v
        .prphrl_nps_in(prphrl_nps_pin),                      //From external to spi.v
        .prphrl_pclk_in(prphrl_pclk_pin),                    //From external to spi.v
    
        //Clock and reset inputs
    
        .clk_27p5(clk_27p5),
        .clk_4p5(clk_4p5),
        .rst_n_27p5(rst_n_27p5),
        .rst_n_4p5(rst_n_4p5),
    
        //Outputs from 4.5MHz domain to 27p5MHz domain
        .radio_busy_out(radio_busy_27p5),                    //From radio_fsm.v to rfidr_fsm.v
        .radio_exit_code_out(radio_exit_code_27p5),          //From radio_fsm.v to spi.v
        .radio_done_out(radio_done_27p5),                    //From radio_fsm.v to rfidr_fsm.v
    
        .txcancel_data_out(txcancel_data_27p5),              //From tx_cancel.v to spi.v
        .txcancel_data_aux_out(txcancel_data_aux_27p5),      //From tx_cancel.v to spi.v
        .txcancel_csel_out(txcancel_csel_27p5),              //From tx_cancel.v to spi.v
        .txcancel_rdy_out(txcancel_rdy_27p5),                //From tx_cancel.v to spi.v    
        
        .tx_error_out(tx_error_27p5),
        .write_cntr_out(write_cntr_27p5),
    
        .wave_storage_done_out(wave_storage_done_27p5),
        .wave_storage_running_out(wave_storage_running_27p5),
    
        //Outputs from 27p5MHz domain to 4.5MHz domain
        .radio_go_out(radio_go_4p5),                         //From rfidr_fsm.v to radio_fsm.v
        .radio_mode_out(radio_mode_4p5),                     //From spi.v to radio_fsm.v
        .radio_ack_out(radio_ack_4p5),                       //From spi.v to tx_cancel.v    
        .use_i_out(use_i_4p5),
        .alt_radio_fsm_loop_out(alt_radio_fsm_loop_4p5),
        .end_radio_fsm_loop_out(end_radio_fsm_loop_4p5),
        .use_select_pkt_out(use_select_pkt_4p5),
        .kill_write_pkt_out(kill_write_pkt_4p5),
        .sdm_offset_out(sdm_offset_4p5),
        .zgn_offset_out(zgn_offset_4p5),
        
        //Outputs from external async domain to 27p5MHz domain
        .prphrl_copi_out(prphrl_copi_27p5),                   //From external to spi.v
        .prphrl_nps_out(prphrl_nps_27p5),                     //From external to spi.v
        .prphrl_pclk_out(prphrl_pclk_27p5)                    //From external to spi.v
    );
    
    spi spi0(
    
    //Inout
        .cntrlr_cipo(cntrlr_cipo_pin),                         //A bidirectional pin that is ordinarily tristated and used as input only when cntrlr_nps[4] is low
    
    //Peripheral Inputs
        .prphrl_copi(prphrl_copi_27p5),                        //Needs double flop synchronizer external to this block
        .prphrl_nps(prphrl_nps_27p5),                          //Needs double flop synchronizer external to this block
        .prphrl_pclk(prphrl_pclk_27p5),                        //Needs double flop synchronizer external to this block
    
        .radio_sram_rdata(radio_sram_rdata_27p5),
        .wvfm_sram_rdata(wvfm_sram_rdata_27p5),
        .txcancel_sram_rdata(txcancel_sram_rdata_27p5),
    
        .clk(clk_27p5),                                      //27p5MHz clock 
        .rst_n(rst_n_27p5),        
    
    //Controller Inputs    
        .txcancel_data(txcancel_data_27p5),                  //Needs double flop synchronizer external to this block
        .txcancel_data_aux(txcancel_data_aux_27p5),          //Needs double flop synchronizer external to this block
        .txcancel_csel(txcancel_csel_27p5),                  //Needs double flop synchronizer external to this block
        .txcancel_rdy(txcancel_rdy_27p5),                    //Needs double flop synchronizer external to this block    
        .radio_running(radio_running),                       //Needs double flop synchronizer external to this block    
    
    //Peripheral Inputs related to control registers
    
        .wave_storage_running(wave_storage_running_27p5),    //Needs double flop synchronizer external to this block
        .wave_storage_done(wave_storage_done_27p5),          //Needs double flop synchronizer external to this block
        .radio_exit_code(radio_exit_code_27p5),              //Needs double flop synchronizer external to this block
        .radio_done(radio_done),                             //Needs double flop synchronizer external to this block
        .tx_error(tx_error_27p5),                            //Needs double flop synchronizer external to this block
        .write_cntr(write_cntr_27p5),
        .clk_36_valid(clk_36_valid),
        .clk_36_running(clk_36_running),

    //Peripheral Outputs
        .prphrl_cipo(prphrl_cipo_pin),
    
        .radio_sram_addr(radio_sram_addr_27p5),
        .radio_sram_wdata(radio_sram_wdata_27p5),
        .radio_sram_we_data(radio_sram_we_data_27p5),
        .txcancel_sram_addr(txcancel_sram_addr_27p5),
        .txcancel_sram_wdata(txcancel_sram_wdata_27p5),
        .txcancel_sram_we_data(txcancel_sram_we_data_27p5),
        .wvfm_sram_addr(wvfm_sram_addr),
        
    //Peripheral Outputs
        .cntrlr_nps_rdio(cntrlr_nps_rdio_pin),                //One-hot encoded since this maps to pins 4:Radio, 3-0: DTCs
        .cntrlr_nps_dtc(cntrlr_nps_dtc_pin),
        .cntrlr_pclk(cntrlr_pclk_pin),
        
        .cntrlr_copi_cap3(cntrlr_copi_cap3_pin),
        .cntrlr_copi_cap2(cntrlr_copi_cap2_pin),
        .cntrlr_copi_cap1(cntrlr_copi_cap1_pin),
        .cntrlr_copi_cap0_rdio(cntrlr_copi_cap0_rdio_pin),
    
        .radio_ack(radio_ack_27p5),                            //Assert this when txcancel_rdy is high and packet has been processed
        .irq_spi(irq_spi),
    
    //Peripheral Outputs related to control registers
    
        .go_radio(radio_go),
        .irq_ack(irq_ack),
        .radio_mode(radio_mode_27p5),
        .alt_radio_fsm_loop(alt_radio_fsm_loop_27p5),
        .end_radio_fsm_loop(end_radio_fsm_loop_27p5),
        .use_select_pkt(use_select_pkt_27p5),
        .kill_write_pkt(kill_write_pkt_27p5),
        .sw_reset(rst_4p5_sw),
        .wvfm_offset(wvfm_offset_27p5),
        .clk_36_start(clk_36_start),
        .use_i(use_i_27p5),
        .dtc_test_mode(dtc_test_mode),
        .sdm_offset(sdm_offset_27p5),
        .zgn_offset(zgn_offset_27p5)
    );

    rfidr_fsm    rfidr_fsm0(
        //Inputs
        .radio_go_in(radio_go),                   //This needs to be a one-shot signal from the SPI control registers
        .radio_busy_in(radio_busy_27p5),
        .radio_done_in(radio_done_27p5),          //This needs to be a one-shot signal from the radio
        .irq_acked(irq_ack),                      //This needs to be a one-shot signal from the SPI control registers
        .clk(clk_27p5),
        .rst_n(rst_n_27p5),
        //Outputs
        .radio_go_out(radio_go_27p5),
        .radio_running(radio_running),            //This signal is required in order to disable SPI peripheral writes and SPI peripheral feedthrough
        .radio_done_out(radio_done),
        .mcu_irq(irq_fsm)
    );
    
    radio_fsm    radio_fsm0(
        // *** Note that wires marked with stars "***" must undergo clock domain crossings.
        // Output signals so denoted must be launched from flops, obviously
        // ??? denotes signals that we haven't determined whether we need them or not.
        
        // Inputs
        .go(radio_go_4p5),                        //    *** From top-level FSM
        .alt_radio_fsm_loop(alt_radio_fsm_loop_4p5),
        .end_radio_fsm_loop(end_radio_fsm_loop_4p5),
        .use_select_pkt(use_select_pkt_4p5),
        .kill_write_pkt(kill_write_pkt_4p5),
        .mode(radio_mode_4p5),                    //    *** From memory-mapped registers interfacing with SPI
        .rx_done(rx_done),                        //    The RX has completed its reception, made valid its indicators, and stored its results in SRAM
        .rx_fail_crc(rx_fail_crc),                //    The RX CRC reception has failed
        .rx_timeout(rx_timeout),                  //    The RX has timed out while waiting for a packet
        .rx_dlyd_err(1'b0),                       //    The RX has received an error in a delayed response packet (e.g. write)
        .rx_hndl_mmtch(1'b0),                     //    The RX has received a packet with the wrong handle
        .rx_collision(1'b0),                      //    The RX has detected a RN16 packet with a high probability of collision
        .tx_done(tx_done),                        //    The TX has completed transmitting its packet
        .last_tx_write(last_tx_write),            //    From TX_Gen - reading SRAM will tell when we are at the last word to be written
        .rst_n(rst_n_4p5),                        //    4.5MHz domain reset signal.
        .clk(clk_4p5),                            //    4.5MHz clock            
    
        // Outputs
        .state(radio_state),                      //     Tell DR / TX Gen which operation to do and which RX/TX address to place the data
        .txrxaccess(radio_sram_txrxaccess),       //    Permits either TX or RX to access the shared variable packet data RAM
        .rx_block(rx_block),                      //    Block the RX from seeing crazy TX signal
        .rx_go(rx_go),                            //    Kick off the RX DR state machine
        .tx_go(tx_go),                            //    Kick off the TX Gen state machine
        .tx_en(tx_en),                            //    ??? Enable SX1257 TX, TX PA ??? - Use this to enable TX Gen CW at least
        .wvfm_go(wvfm_go),                        //     Kick off waveform recording
        .busy(radio_busy_4p5),                    //    *** Tell top-level FSM and memory-mapped register that radio is busy.
        .exit_code(radio_exit_code_4p5),          //    *** Pass (0) or fail (1)
        .kill_first_pkt(kill_first_pkt),          //    Clear the flag which disables delayed response during kill    
        .write_cntr(write_cntr_4p5),              //    Write counter - control which write word is sent from memory over-the-air.
        .done(radio_done_4p5)                     //    *** Tell top-level FSM that the radio FSM is done
    );

    tx_cancel tx_cancel0(
        // Inputs
        .dc_in_i(dc_i),
        .dc_in_q(dc_q),
        .dc_ready(dc_ready_i && dc_ready_q),
        .rst_n(rst_n_4p5),
        .spi_ack(radio_ack_4p5),                  //This signal comes in from controller 48 MHz to 4p5 MHz synchronizer
        .clk_4p5(clk_4p5),                        //4p5 MHz clock is used here
        .mem_wdata(txcancel_sram_wdata_27p5),
        .mem_wraddress(txcancel_sram_addr_27p5),
        .mem_clk(clk_27p5),
        .mem_wren(txcancel_sram_we_data_27p5),
        .go_radio(radio_go_4p5 && use_select_pkt_4p5), //Modified so that we don't reset this internally for each query (rep) during inventory. Sort of a temp fix for now. 111217
        
        // Outputs
        .mem_rdata(txcancel_sram_rdata_27p5),
        .spi_data_out(txcancel_data_4p5),
        .spi_data_aux_out(txcancel_data_aux_4p5),
        .spi_data_csel(txcancel_csel_4p5),         //This is the chip select for which of the DTC/Radio is targeted
        .spi_data_rdy(txcancel_rdy_4p5)            
    );
    
    rxchain    rxchain_i(
        // Inputs
        .in(in_i_pin),
        .blank(rx_block),
        .clk_4p5(clk_4p5),
        .clk_4p5_stretch_en(clk_4p5_stretch_en),
        .clk_36(clk_36),
        .rst_n(rst_n_4p5),
        // Outputs
        .in_posedge(in_posedge_i),
        .chfilt_out(chfilt_i),
        .dc_out(dc_i),
        .dc_ready(dc_ready_i)
    );
    
    rxchain    rxchain_q(
        // Inputs
        .in(in_q_pin),
        .blank(rx_block),
        .clk_4p5(clk_4p5),
        .clk_4p5_stretch_en(clk_4p5_stretch_en),
        .clk_36(clk_36),
        .rst_n(rst_n_4p5),
        // Outputs
        .in_posedge(in_posedge_q),
        .chfilt_out(chfilt_q),
        .dc_out(dc_q),
        .dc_ready(dc_ready_q)
    );
    
    cdr_top    cdr_top0(
        // Inputs
        .in_i(chfilt_i),
        .in_q(chfilt_q),
        .use_i(use_i_4p5),
        .clk(clk_4p5),
        .rst_n(rst_n_4p5),
        .radio_state(radio_state),
        .go(rx_go),                                //    From full handshake 48MHz to 4p5MHz block
        .sram_fromdata_in(radio_sram_rdata_4p5),   // This is data *from* the SRAM
        .kill_first_pkt(kill_first_pkt),
        // Outputs
        .bit_decision(bit_decision_from_dr),
        .done(rx_done),
        .timeout(rx_timeout),
        .fail_crc(rx_fail_crc),
        .shift_rn16(shift_rn16_from_dr),
        .shift_handle(shift_handle_from_dr),
        .sram_address(radio_sram_address_rx),
        .sram_wren(radio_sram_wren),
        .sram_todata_out(radio_sram_wdata_4p5)     // This is data *to* the SRAM
    );
    
    //wave_storage    wave_storage0(
    //    // Inputs
    //    .in_i(in_posedge_i),                     
    //    .in_q(in_posedge_q),
    //    .clk_27p5(clk_27p5),
    //    .clk_36(clk_36),
    //    .rst_n(rst_n_4p5),
    //    .go(wvfm_go),                                      //Need to actually make this signal
    //    .wait_offset({wvfm_offset_27p5,16'b0}),            //This should in general be clock crossed but we need to minimize extraneous free registers
    //    .clk_27p5_en(1'b1),
    //    .address(wvfm_sram_addr),            
    //    // Outputs
    //    .out(wvfm_sram_rdata_27p5),
    //    .done(wave_storage_done_4p5),
    //    .running(wave_storage_running_4p5)
    //);
    
    radio_sram_with_mux        radio_sram_with_mux0(
        //Inputs
        .address_a_rx({1'b1,radio_sram_address_rx}),
        .address_a_tx({1'b0,radio_sram_address_tx}),
        .address_b(radio_sram_addr_27p5),
        .clock_a(clk_4p5),
        .clock_b(clk_27p5),
        .data_a(radio_sram_wdata_4p5),
        .data_b(radio_sram_wdata_27p5),
        .txrxaccess(radio_sram_txrxaccess),
        .wren_a(radio_sram_wren),
        .wren_b(radio_sram_we_data_27p5),
        //Outputs
        .q_a(radio_sram_rdata_4p5),
        .q_b(radio_sram_rdata_27p5)
    );
    
    rn16_and_handle_shift_regs    rn16_and_handle_shift_regs0
    (
        // Inputs
        .in_rn16(bit_decision_from_dr),
        .in_handle(bit_decision_from_dr),
        .shift_rn16_from_dr(shift_rn16_from_dr),
        .shift_rn16_to_txgen(shift_rn16_to_txgen),
        .shift_handle_from_dr(shift_handle_from_dr),
        .shift_handle_to_txgen(shift_handle_to_txgen),
        .rst_n(rst_n_4p5),
        .clk(clk_4p5),
        //Outputs
        .out_rn16(rn16_to_txgen),
        .out_handle(handle_to_txgen)
    );
    
    tx_gen    tx_gen0(
        // Inputs
        .sram_in_data(radio_sram_rdata_4p5),
        .current_rn16(rn16_to_txgen),
        .current_handle(handle_to_txgen),
        .radio_state(radio_state),
        .go(tx_go),
        .en(tx_en),
        .clk(clk_4p5),
        .rst_n(rst_n_4p5),
        .dtc_test_mode(dtc_test_mode),
        .write_cntr(write_cntr_4p5),
        // Outputs
        .shift_rn16_bits(shift_rn16_to_txgen),
        .shift_handle_bits(shift_handle_to_txgen),
        .sram_address(radio_sram_address_tx),
        .out(out_i_baseband_4p5),
        .done(tx_done),
        .last_write(last_tx_write),
        .error_outer(tx_error_4p5)                //Error in the outer loop of the FSM - must report thru SPI
    );
    
    tx_sdm_c8g    tx_sdm0(
        // Inputs
        .in(out_i_baseband_4p5),
        .clk(clk_36),
        .rst_n(rst_n_4p5),
        .clk_out(clk_36_in_pin),
        .rst_n_out(rst_n_36_in),                  //Use async reset for now
        .offset(sdm_offset_4p5),
        // Outputs
        .out(out_i_pin)
    );

    tx_zero_pattern_gen_c8g    tx_zero0(
        // Inputs
        .clk(clk_36_in_pin),
        .rst_n(rst_n_36_in),
        .offset(zgn_offset_4p5),
        // Outputs
        .out(out_q_pin)
    );
// {ALTERA_MODULE_END} DO NOT REMOVE THIS LINE!
endmodule





