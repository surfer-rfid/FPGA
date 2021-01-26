/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Signed saturator for integer arithemtic                                //
//                                                                                 //
// Filename: signed_saturate.v                                                     //
// Creation Date: 6/23/2015                                                        //
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
//    This code performs a parameterizable signed saturation                       //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module signed_saturate #(parameter WIDTH_IN=16, WIDTH_OUT=15)
    (
        input     wire     signed    [WIDTH_IN:0]     in,
        output    wire     signed    [WIDTH_OUT:0]    out
    );
    
    wire   saturate, is_input_neg;
    wire   signed [WIDTH_OUT:0]   max_out, min_out;
    
    assign is_input_neg = in[WIDTH_IN];
    //If all of the bits in the part to be thrown away plus the MSB of the output
    //are the same, then there is no need to saturate, otherwise, there is.

    assign saturate     = ~(&(~in[WIDTH_IN:WIDTH_OUT]) || &in[WIDTH_IN:WIDTH_OUT]);

    assign max_out  = {1'b0,{(WIDTH_OUT){1'b1}}};
    assign min_out  = {1'b1,{(WIDTH_OUT){1'b0}}};
    assign out = !saturate ? in[WIDTH_OUT:0] : (is_input_neg ? min_out : max_out);
    
endmodule