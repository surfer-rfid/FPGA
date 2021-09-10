////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module : RX Clock and Data Recovery Top Level Unit w SRAM - test only          //
//                                                                                //
// Filename: cdr_top_w_sram_test_only.v                                           //
// Creation Date: 12/20/2015                                                      //
// Author: Edward Keehr                                                           //
//                                                                                //
// Copyright Superlative Semiconductor LLC 2021                                   //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2    //
// You may redistribute and modify this documentation and make products           //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).       //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED               //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                   //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2             //
// for applicable conditions.                                                     //
//                                                                                //
// Description:                                                                   //
//        This is the top level of the clock and data recovery circuit.           //
//        It contains two clock recovery circuits, one each for I and Q channels, //
//        and one data recovery circuit which processes both I and Q at the same  //
//        time.                                                                   //
//                                                                                //
//    Revisions:                                                                  //
//    072416 - Adjust to accomodate no more rn16, handle register outputs.        //
//    Also change the user_sram (poorly named) to radio_sram.                     //
//    Also, only one clock recoevery circuit, not 2.                              //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module    cdr_top_w_sram_test_only (
    // Inputs
    input    wire    signed    [15:0]    in_i,
    input    wire    signed    [15:0]    in_q,
    input    wire                        use_i,
    input    wire                        clk_cdr,
    input    wire                        clk_spi,
    input    wire                        rst_n,
    input    wire            [4:0]       radio_state,
    input    wire                        go,                        //    From full handshake 24MHz to 4p5MHz block
    input    wire            [9:0]       sram_address_fromspi,
    input    wire            [7:0]       sram_data_fromspi,
    input    wire                        sram_wren_fromspi,
    // Outputs
    output    wire                       bit_decision,
    output    wire                       done,
    output    wire                       shift_rn16,
    output    wire                       shift_handle,
    output    wire           [7:0]       sram_data_tospi
);
    
    wire                     [7:0]       sram_data_tocdr;
    wire                                 sram_wren_fromcdr;
    wire                     [8:0]       sram_address_fromcdr;
    wire                     [7:0]       sram_data_fromcdr;
    
cdr_top    dut_cdr(
    // Inputs
    .in_i(in_i),
    .in_q(in_q),
    .use_i(use_i),
    .clk(clk_cdr),
    .rst_n(rst_n),
    .radio_state(radio_state),
    .go(go),                                   // From full handshake 24MHz to 4p5MHz block
    .sram_fromdata_in(sram_data_tocdr),        // This is data *from* the SRAM
    // Outputs
    .bit_decision(bit_decision),
    .done(done),
    .shift_rn16(shift_rn16),
    .shift_handle(shift_handle),
    .sram_address(sram_address_fromcdr),
    .sram_wren(sram_wren_fromcdr),
    .sram_todata_out(sram_data_fromcdr)        // This is data *to* the SRAM
);

radio_sram_with_mux    radio_sram_with_mux0(
    //Inputs
    .address_a_rx({1'b1,sram_address_fromcdr}),
    .address_a_tx({1'b0,9'b0}),
    .address_b(sram_address_fromspi),
    .clock_a(clk_cdr),
    .clock_b(clk_spi),
    .data_a(sram_data_fromcdr),
    .data_b(sram_data_fromspi),
    .txrxaccess(1'b1),
    .wren_a(sram_wren_fromcdr),
    .wren_b(sram_wren_fromspi),
    //Outputs
    .q_a(sram_data_tocdr),
    .q_b(sram_data_tospi)
);    
    
endmodule
