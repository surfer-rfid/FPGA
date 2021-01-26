/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Variable width subtractor using Altera/Intel FPGA IP                   //
//                                                                                 //
// Filename: lpm_mult_const.v                                                      //
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
//    This code instantiates the Altera/Intel FPGA IP for a multiplier with a      //
//    constant input, with parameterizable input and output widths, and also       //
//    parameterizable multiplication constant.                                     //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module lpm_mult_const #(parameter WIDTH_IN=18, WIDTH_OUT=26, MULT_CONST=1)
    (
       input     wire    signed    [WIDTH_IN-1:0]     a_in,
       output    wire    signed    [WIDTH_OUT-1:0]    y_out
    );

    wire signed [WIDTH_OUT-WIDTH_IN-1:0] mult_const_local = MULT_CONST;

    lpm_mult   mult_const_core (
            .dataa (a_in),
            .datab (mult_const_local),
            .result (y_out),
            .aclr (1'b0),
            .clken (1'b1),
            .clock (1'b0),
            .sum (1'b0));
    defparam
        mult_const_core.lpm_hint = "INPUT_B_IS_CONSTANT=YES,DEDICATED_MULTIPLIER_CIRCUITRY=YES,MAXIMIZE_SPEED=1",
        mult_const_core.lpm_representation = "SIGNED",
        mult_const_core.lpm_type = "LPM_MULT",
        mult_const_core.lpm_widtha = WIDTH_IN,
        mult_const_core.lpm_widthb = WIDTH_OUT-WIDTH_IN,
        mult_const_core.lpm_widthp = WIDTH_OUT;

endmodule