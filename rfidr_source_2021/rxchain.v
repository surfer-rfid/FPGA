/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module: Dec-by-8 and Channel Filter for RFID digital back end                   //
//                                                                                 //
// Filename: rxchain.v                                                             //
// Creation Date: 11/28/2015                                                       //
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
// Description: This file is the bulk of the RX filtering in the                   //
// RFIDr digital back end. It's name is a bit of a misnomer since                  //
//    it is not the entire RX chain. The name is carried over from                 //
// system level development when it was thought that these might                   //
// be the only filters required.                                                   //
//                                                                                 //
// Revisions:                                                                      //
// 121315 - Use structures with lower LUT usage.                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module rxchain
    (
        // Inputs
        input     wire                        in,
        input     wire                        blank,
        input     wire                        clk_4p5,
        input     wire                        clk_4p5_stretch_en,
        input     wire                        clk_36,
        input     wire                        rst_n,
        // Outputs
        output    wire                        in_posedge,
        output    wire    signed    [15:0]    chfilt_out,
        output    wire    signed    [15:0]    dc_out,
        output    wire                        dc_ready
    );
    
    // Parameter and localparam declarations
    // Register and wire declarations
    
    wire    signed    [12:0]    cic8_out;
    
    // Module declarations
    
    cic_8    cic_8_0
        (
            .in                    (in),
            .clk_4p5               (clk_4p5),
            .clk_4p5_stretch_en    (clk_4p5_stretch_en),
            .clk_36                (clk_36),
            .rst_n                 (rst_n),
            .out                   (cic8_out),
            .in_posedge            (in_posedge)
        );
        
    dec_128    dec_128_0
        (
            .in                    (cic8_out),
            .clk_4p5               (clk_4p5),
            .rst_n                 (rst_n),
            .regout                (dc_out),
            .ready                 (dc_ready)
        );
        
    chnl_filt    chnl_filt_0
        (
            .in                    (cic8_out),
            .blank                 (blank),
            .clk_4p5               (clk_4p5),
            .rst_n                 (rst_n),
            .out                   (chfilt_out)
        );

endmodule
