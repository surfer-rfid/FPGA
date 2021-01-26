////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module : RX Clock and Data Recovery Top Level Unit                             //
//                                                                                //
// Filename: cdr_top.v                                                            //
// Creation Date: 12/7/2015                                                       //
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
//    time.                                                                       //
//                                                                                //
//    Revisions:                                                                  //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module    cdr_top
    (
        // Inputs
        input        wire    signed    [15:0]    in_i,
        input        wire    signed    [15:0]    in_q,
        input        wire                        use_i,
        input        wire                        clk,
        input        wire                        rst_n,
        input        wire               [4:0]    radio_state,
        input        wire                        go,                  //    From full handshake 55MHz to 4p5MHz block
        input        wire               [7:0]    sram_fromdata_in,    // This is data *from* the SRAM
        input        wire                        kill_first_pkt,
        // Outputs
        output       wire                        bit_decision,
        output       wire                        done,
        output       wire                        timeout,
        output       wire                        fail_crc,
        output       wire                        shift_rn16,
        output       wire                        shift_handle,
        output       wire               [8:0]    sram_address,
        output       wire                        sram_wren,
        output       wire               [7:0]    sram_todata_out    // This is data *to* the SRAM
    );
    
    // Parameter and localparam declarations
    // Wire and reg declarations
    
    wire            sample;
    wire            in_cr;
    
    // Module declarations
    
    clk_rcvy    cr_main
        (
            //Inputs
            .data(in_cr),
            .clk(clk),
            .rst_n(rst_n),
            //Outputs
            .clk_zero_xing(sample)
        );
            
    data_rcvy    dr
        (
            // Inputs
            .in_i(in_i),
            .in_q(in_q),
            .clk(clk),
            .sample(sample),
            .rst_n(rst_n),
            .use_i(use_i),
            .radio_state(radio_state),
            .go(go),
            .sram_fromdata_in(sram_fromdata_in),    // This is data *from* the SRAM
            .kill_first_pkt(kill_first_pkt),
            // Outputs
            .bit_decision(bit_decision),
            .done(done),
            .timeout(timeout),
            .fail_crc(fail_crc),
            .shift_rn16(shift_rn16),
            .shift_handle(shift_handle),
            .sram_address(sram_address),
            .sram_wren(sram_wren),
            .sram_todata_out(sram_todata_out)        // This is data *to* the SRAM        
        );

    assign in_cr    =    use_i    ?    in_i >= 0 : in_q >= 0;    
        
endmodule
    