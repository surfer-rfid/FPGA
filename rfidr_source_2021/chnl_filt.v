////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module: Channel filter for RX'ed backscatter data                              //
//                                                                                //
// Filename: chnl_filt.v                                                          //
// Creation Date: 11/27/2015                                                      //
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
// Description: This is a discrete-time analog of two tuned LC                    //
// tanks in series which span the range of frequencies realizable                 //
// by the tag backscatter signal.                                                 //
//                                                                                //
// Revisions:                                                                     //
// 121315 - Changed over to DFII implementation to save LUT                       //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module chnl_filt
    (
        // Inputs
        input    wire    signed    [12:0]    in,
        input    wire                        blank,            // To blank out the TX signal when TX is not just DC
        input    wire                        clk_4p5,
        input    wire                        rst_n,
        // Outputs
        output    wire    signed    [15:0]    out
    );
    
    // Parameter and localparam declarations
    // Register and wire declarations

    wire    signed    [15:0]    in_bq0;
    wire    signed    [19:0]    out_bq0;
    
    // Module declarations
        
    chnl_filt_dfii_onemult chnl_filt_dfii_onemult_0
        (
            .in        (in_bq0),
            .clk       (clk_4p5),
            .blank     (blank),
            .rst_n     (rst_n),
            .out       (out_bq0)
        );
        
    chnl_filt_dfii chnl_filt_dfii_0
        (
            .in        (out_bq0),
            .clk       (clk_4p5),
            .blank     (blank),
            .rst_n     (rst_n),
            .out       (out)
        );
        
        
    // Combinational logic assignments
    
    assign    in_bq0        =    in <<< 3;

    
endmodule
    