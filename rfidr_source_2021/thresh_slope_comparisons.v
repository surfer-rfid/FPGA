//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
// Module : RX Data Recovery Sym counter distance computer                      //
//                                                                              //
// Filename: thresh_slope_comparisons.v                                         //
// Creation Date: 12/17/2015                                                    //
// Author: Edward Keehr                                                         //
//                                                                              //
// Copyright Superlative Semiconductor LLC 2021                                 //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2  //
// You may redistribute and modify this documentation and make products         //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).     //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED             //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                 //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2           //
// for applicable conditions.                                                   //
//                                                                              //
// Description:                                                                 //
// Perform threshold slope comparisons for the data recovery circuit.           //
//                                                                              //
//    Revisions:                                                                //
//                                                                              //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////

module    thresh_slope_comparisons
    (
        // Inputs
        input     wire    signed    [31:0]    integ_main_0,
        input     wire    signed    [31:0]    integ_main_0_abs,
        input     wire    signed    [31:0]    integ_main_store,
        // Outputs
        output    wire                        over_idle_thresh,
        output    wire                        over_locked_thresh,
        output    wire                        prev_slope_next_val
    );

    localparam    IDLE_THRESH              =    16'd4095;
    localparam    LOCKED_THRESH            =    16'd2047;
    
    assign    over_idle_thresh             =    integ_main_0_abs > IDLE_THRESH;
    assign    over_locked_thresh           =    integ_main_0_abs > LOCKED_THRESH;
    assign    prev_slope_next_val          =    (integ_main_store-integ_main_0) < 0;
    
endmodule
