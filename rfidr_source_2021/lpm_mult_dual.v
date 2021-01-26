/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Variable width subtractor using Altera/Intel FPGA IP                   //
//                                                                                 //
// Filename: lpm_mult_dual.v                                                       //
// Creation Date: 1/14/2021                                                        //
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
//    This code instantiates the Altera/Intel FPGA IP for a multiplier with        //
//    dual inputs, with parameterizable widths for each input.                     //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module lpm_mult_dual #(parameter WIDTH_A=18, WIDTH_B=9)
    (
       input     wire    signed    [WIDTH_A-1:0]            a_in,
       input     wire    signed    [WIDTH_B-1:0]            b_in,
       output    wire    signed    [WIDTH_A+WIDTH_B-1:0]    y_out
    );

    lpm_mult   mult_dual_core (
            .dataa (a_in),
            .datab (b_in),
            .result (y_out),
            .aclr (1'b0),
            .clken (1'b1),
            .clock (1'b0),
            .sum (1'b0));
    defparam
        mult_dual_core.lpm_hint = "DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=1",
        mult_dual_core.lpm_representation = "SIGNED",
        mult_dual_core.lpm_type = "LPM_MULT",
        mult_dual_core.lpm_widtha = WIDTH_A,
        mult_dual_core.lpm_widthb = WIDTH_B,
        mult_dual_core.lpm_widthp = WIDTH_A+WIDTH_B;

endmodule
