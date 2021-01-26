/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Radio SRAM with Mux                                                    //
//                                                                                 //
// Filename: radio_sram_with_mux.v                                                 //
// Creation Date: 1/13/2016                                                        //
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
//    This is a simple wrapper which wraps the user memory along with a mux to     //
//    dertermine whether tx_gen or data_rcvy sets the address of the RAM on the    //
// 4.5 MHz side                                                                    //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////


module radio_sram_with_mux (
    input        wire    [9:0]    address_a_rx,
    input        wire    [9:0]    address_a_tx,
    input        wire    [9:0]    address_b,
    input        wire             clock_a,
    input        wire             clock_b,
    input        wire    [7:0]    data_a,
    input        wire    [7:0]    data_b,
    input        wire             txrxaccess,
    input        wire             wren_a,
    input        wire             wren_b,
    output       wire    [7:0]    q_a,
    output       wire    [7:0]    q_b
    );
    
    localparam    TX_RAM_ACCESS        =    1'b0;        //These need to be global parameters
    localparam    RX_RAM_ACCESS        =    1'b1;
    
    wire    [9:0]    address_a;
    
    assign    address_a    = (txrxaccess == RX_RAM_ACCESS) ? address_a_rx : address_a_tx;
    
    radio_sram ram0 (
        .address_a(address_a),
        .address_b(address_b),
        .clock_a(clock_a),
        .clock_b(clock_b),
        .data_a(data_a),
        .data_b(data_b),
        .wren_a(wren_a && txrxaccess),    //Protect against some unanticipated mistake whereby DR can write over TX data. Maybe also later protect key RX data from being overwritten.
        .wren_b(wren_b),
        .q_a(q_a),
        .q_b(q_b)
    );
    
endmodule
    