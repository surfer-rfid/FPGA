////////////////////////////////////////////////////////////////////////////////////////
//                                                                                    //
// Module : SPI Peripheral and Controller Pass-Through                                //
//                                                                                    //
// Filename: spi.v                                                                    //
// Creation Date: 1/10/2016                                                           //
// Author: Edward Keehr                                                               //
//                                                                                    //
// Copyright Superlative Semiconductor LLC 2021                                       //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2        //
// You may redistribute and modify this documentation and make products               //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).           //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                   //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                       //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2                 //
// for applicable conditions.                                                         //
//                                                                                    //
// Description:                                                                       //
//                                                                                    //
//    This SPI block performs both peripheral and controller functions.               //
// Functionally, it supports 4 modes of operation while not in the radio              //
// state:                                                                             //
// Mode:                                                                              //
//    1: Read/write control registers                                                 //
//    2: Read waveform memory                                                         //
//    3: Read/write radio/txcancel memory                                             //
//    4: Access pass-through controller adapter.                                      //
//                                                                                    //
//    These modes used to be addressed individually, but in order to save LUT, the    //
//    interface format has changed somewhat.                                          //
//                                                                                    //
// Synchronizing blocks will be kept out of here for the sake of keeping              //
// them in one place to facilitate false-path demarcation.                            //
//                                                                                    //
// While in the radio state, the SPI Peripheral is prevented from making writes,      //
// and is prevented from accessing the pass-through controller adapter.               //
// While in the radio state, the SPI Controller uses a full-handshake to obtain       //
// data from tx_cancel.v. The full handshake is ACKed after the packet is sent.       //
// Also while in the radio state, the SPI Controller sends out a pre-programmed       //
// register address to the SX1257 when chip select 100 is utilized.                   //
//                                                                                    //
// This block will be run at 27p5MHz, approximately 4x the 6MHz rate of               //
// SPI traffic. The reason for doing this is to catch rising and falling              //
//    edges of PCLK.                                                                  //
//                                                                                    //
// This block will also contain a divide-by-4 block in order to generate a            //
//    controller PCLK < 10MHz when in Radio Controller mode.                          //
//                                                                                    //
// Peripheral CIPO is non-high impedance only while playing back data                 //
// Controller COPI is always low impedance, driving to logic low when not in use      //
//                                                                                    //
//                                                                                    //
//    The register map for the control registers is as follows:                       //
//    000:    Radio Exit (3b R)|Radio Mode (3b RW)|IRQ Ack(1b RWO)|Go Radio(1bRWO)    //
//    001:    Clk 36 start (1b RW) | TX Error (3b R)                                  //
//            Wave Storage running (1b R)| Wave Storage done(1b R)|                   //
//        ...    Radio running (1b R) | Radio done (1b R)                             //
//    010:    Nothing (6b) |Use Ch I (1b) | SW Reset (1bRWO)                          //
//    011:    Waveform offset value [7:0]                                             //
//    100:    SPI bridge return data [7:0]                                            //
//                                                                                    //
//                                                                                    //
// To do as of 2:11PM 1/11/2016:                                                      //
//    - Make peripheral output lines high Z when not in use (DONE)                    //
// - What to do if NPS goes down in the middle of a transaction?                      //
//        Look for NPS level and terminate the transaction, returning to IDLE         //
//    (DONE)                                                                          //
//    Revisions:                                                                      //
//                                                                                    //
//    030116 - Revised in light of timing requirements, namely:                       //
//    1. Launched all outputs from registers.                                         //
//    2. Used an internal buffer for bridge transfers.                                //
//    3. Allow only byte-length words to be sent into design.                         //
//    4. Focus on fast turn around for reads.                                         //
//    5. Need to deal with fact that registers are register files now and require a   //
//    clock delay in order to retrieve data. (dealt with using turnaround registers). //
//    6. DTC SPI Select lines require inverted polarity than usual.                   //
//                                                                                    //
//                                                                                    //
//    032416 - Moved back to Altera/Quartus environment. Added provision for TX       //
//    cancel RAM access.                                                              //
//    081416 - Moved the separate spi_cntrlr and spi_prphrl modules into this module  //
//    for concurrent verification.                                                    //
//    Also updated comments to show proper operation of the NRF51822 SPI controller.  //
//    111016 - Added signals to permit true inventorying.                             //
//    082817 - Improved DTC testing override code for automated TMN test.             //
//    021518 - Added support for kill command.                                        //
//    122320 - Add support for SPI control of TX offset.                              //
//                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////

module spi(
    //Inouts
    inout    wire                cntrlr_cipo,            //A bidirectional pin that is ordinarily tristated and used as input only when cntrlr_nps[4] is low
    
    //Inputs
    input    wire                prphrl_copi,            //Needs double flop synchronizer external to this block
    input    wire                prphrl_nps,             //Needs double flop synchronizer external to this block
    input    wire                prphrl_pclk,            //Needs double flop synchronizer external to this block
    
    input    wire    [7:0]       radio_sram_rdata,
    input    wire    [7:0]       wvfm_sram_rdata,
    input    wire    [7:0]       txcancel_sram_rdata,
    
    input    wire                clk,                    //27p5MHz clock 
    input    wire                rst_n,
    
    input    wire    [7:0]       txcancel_data,          //Needs double flop synchronizer external to this block
    input    wire    [14:0]      txcancel_data_aux,      //Needs double flop synchronizer external to this block
    input    wire                txcancel_csel,          //Needs double flop synchronizer external to this block
    input    wire                txcancel_rdy,           //Needs double flop synchronizer external to this block
    input    wire                radio_running,          //Needs double flop synchronizer external to this block
    
    //Inputs related to control registers
    
    input    wire                wave_storage_running,   //Needs double flop synchronizer external to this block
    input    wire                wave_storage_done,      //Needs double flop synchronizer external to this block
    input    wire    [1:0]       radio_exit_code,        //Needs double flop synchronizer external to this block
    input    wire                radio_done,             //Needs double flop synchronizer external to this block
    input    wire                tx_error,               //Needs double flop synchronizer external to this block
    input    wire    [2:0]       write_cntr,
    input    wire                clk_36_valid,
    input    wire                clk_36_running,

    //Outputs
    output    wire               prphrl_cipo,
    
    output    wire    [9:0]      radio_sram_addr,
    output    wire    [7:0]      radio_sram_wdata,
    output    wire               radio_sram_we_data,
    output    wire    [9:0]      txcancel_sram_addr,
    output    wire    [7:0]      txcancel_sram_wdata,
    output    wire               txcancel_sram_we_data,
    output    wire    [12:0]     wvfm_sram_addr,
    output    wire               cntrlr_nps_rdio,         //One-hot encoded since this maps to pins 4:Radio, 3-0: DTCs
    output    wire               cntrlr_nps_dtc,
    output    wire               cntrlr_pclk,
    
    output    wire               cntrlr_copi_cap3,
    output    wire               cntrlr_copi_cap2,
    output    wire               cntrlr_copi_cap1,
    output    wire               cntrlr_copi_cap0_rdio,
    
    output    wire               radio_ack,              //Assert this when txcancel_rdy is high and packet has been processed
    output    wire               irq_spi,
    
    //Outputs related to control registers
    
    output    wire               go_radio,
    output    wire               irq_ack,
    output    wire    [1:0]      radio_mode,
    output    wire               alt_radio_fsm_loop,
    output    wire               end_radio_fsm_loop,
    output    wire               use_select_pkt,
    output    wire               kill_write_pkt,
    output    wire               sw_reset,
    output    wire    [7:0]      wvfm_offset,
    output    wire               clk_36_start,
    output    wire               use_i,
    output    wire               dtc_test_mode,
    output    wire    [3:0]      sdm_offset,
    output    wire    [3:0]      zgn_offset
);
    
    //Declare the wires connecting the peripheral and controller modules
    
    wire             cntrlr_spi_rdy, cntrlr_spi_pending, cntrlr_spi_done;
    wire    [7:0]    cntrlr_addr_buf, cntrlr_data_buf, cntrlr_rx_buf;
    wire    [9:0]    spi_cap_val_1, spi_cap_val_2;
    //wire            dtc_test_mode;
    wire             dtc_test_go;

    //Instantiate the peripheral and controller modules
    
    spi_prphrl    spi_prphrl0(
    //Inputs
        .prphrl_copi(prphrl_copi),                        //Needs double flop synchronizer external to this block
        .prphrl_nps(prphrl_nps),                          //Needs double flop synchronizer external to this block
        .prphrl_pclk(prphrl_pclk),                        //Needs double flop synchronizer external to this block
    
        .radio_sram_rdata(radio_sram_rdata),
        .wvfm_sram_rdata(wvfm_sram_rdata),
        .txcancel_sram_rdata(txcancel_sram_rdata),
    
        .clk(clk),                                       //27p5MHz clock 
        .rst_n(rst_n),
    
    //Inputs related to control registers
    
        .wave_storage_running(wave_storage_running),     //Needs double flop synchronizer external to this block
        .wave_storage_done(wave_storage_done),           //Needs double flop synchronizer external to this block
        .radio_exit_code(radio_exit_code),               //Needs double flop synchronizer external to this block
        .radio_done(radio_done),                         //Needs double flop synchronizer external to this block
        .radio_running(radio_running),                   //Needs double flop synchronizer external to this block
        .tx_error(tx_error),                             //Needs double flop synchronizer external to this block
        .write_cntr(write_cntr),                         //Needs double flop synchronizer external to this block
        .clk_36_valid(clk_36_valid),
        .clk_36_running(clk_36_running),
        .cntrlr_rx_buf(cntrlr_rx_buf),                   //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_spi_pending(cntrlr_spi_pending),         //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_spi_done(cntrlr_spi_done),               //No need to retime, runs on 27.5 MHZ domain
    
    //Outputs
        .prphrl_cipo(prphrl_cipo),
        .radio_sram_addr(radio_sram_addr),
        .radio_sram_wdata(radio_sram_wdata),
        .radio_sram_we_data(radio_sram_we_data),
        .txcancel_sram_addr(txcancel_sram_addr),
        .txcancel_sram_wdata(txcancel_sram_wdata),
        .txcancel_sram_we_data(txcancel_sram_we_data),
        .wvfm_sram_addr(wvfm_sram_addr),
    
    //Outputs related to control registers
    
        .go_radio(go_radio),
        .irq_ack(irq_ack),
        .radio_mode(radio_mode),
        .alt_radio_fsm_loop(alt_radio_fsm_loop),
        .end_radio_fsm_loop(end_radio_fsm_loop),
        .use_select_pkt(use_select_pkt),
        .kill_write_pkt(kill_write_pkt),
        .sw_reset(sw_reset),
        .wvfm_offset(wvfm_offset),
        .clk_36_start(clk_36_start),
        .use_i(use_i),
        .cntrlr_addr_buf(cntrlr_addr_buf),                //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_data_buf(cntrlr_data_buf),                //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_spi_rdy(cntrlr_spi_rdy),                  //No need to retime, runs on 27.5 MHZ domain
        .spi_cap_val_1(spi_cap_val_1),
        .spi_cap_val_2(spi_cap_val_2),
        .dtc_test_mode(dtc_test_mode),
        .dtc_test_go(dtc_test_go),
        .sdm_offset(sdm_offset),
        .zgn_offset(zgn_offset)
    );
    
    spi_cntrlr spi_cntrlr0(
    //Inputs
        .cntrlr_cipo(cntrlr_cipo),                          //A bidirectional pin that is ordinarily tristated and used as input only when cntrlr_nps[4] is low
    
        .txcancel_data(dtc_test_mode ? {{3{1'b0}},spi_cap_val_1[9:5]} : txcancel_data),                          //Needs double flop synchronizer external to this block
        .txcancel_data_aux(dtc_test_mode ? {spi_cap_val_1[4:0], spi_cap_val_2[9:0]} : txcancel_data_aux),        //Needs double flop synchronizer external to this block
        .txcancel_csel(dtc_test_mode ? 1'b0 : txcancel_csel),                                                    //Needs double flop synchronizer external to this block
        .txcancel_rdy(dtc_test_mode ? dtc_test_go : txcancel_rdy),                                               //Needs double flop synchronizer external to this block
    
        .cntrlr_addr_buf(cntrlr_addr_buf),                  //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_data_buf(cntrlr_data_buf),                  //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_spi_rdy(cntrlr_spi_rdy),                    //No need to retime, runs on 27.5 MHZ domain
    
        .clk(clk),                                          //27p5MHz clock 
        .rst_n(rst_n),
    
        .radio_running(dtc_test_mode ? 1'b1 : radio_running),                //Needs double flop synchronizer external to this block
    
    //Outputs
        .cntrlr_nps_rdio(cntrlr_nps_rdio),                  //One-hot encoded since this maps to pins 4:Radio, 3-0: DTCs
        .cntrlr_nps_dtc(cntrlr_nps_dtc),
        .cntrlr_pclk(cntrlr_pclk),
        
        .cntrlr_copi_cap3(cntrlr_copi_cap3),
        .cntrlr_copi_cap2(cntrlr_copi_cap2),
        .cntrlr_copi_cap1(cntrlr_copi_cap1),
        .cntrlr_copi_cap0_rdio(cntrlr_copi_cap0_rdio),
    
        .radio_ack(radio_ack),                          //Assert this when txcancel_rdy is high and packet has been processed
        .cntrlr_rx_buf(cntrlr_rx_buf),                  //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_spi_pending(cntrlr_spi_pending),        //No need to retime, runs on 27.5 MHZ domain
        .cntrlr_spi_done(cntrlr_spi_done),              //No need to retime, runs on 27.5 MHZ domain
        .irq_spi(irq_spi)
    );
    
endmodule
