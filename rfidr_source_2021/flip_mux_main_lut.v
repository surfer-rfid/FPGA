//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
// Module : RX Data Recovery Flip Mux for Main Path                                 //
//                                                                                  //
// Filename: flip_mux_main_lut.v                                                    //
// Creation Date: 03/25/2016                                                        //
// Author: Edward Keehr                                                             //
//                                                                                  //
// Copyright Superlative Semiconductor LLC 2021                                     //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2      //
// You may redistribute and modify this documentation and make products             //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).         //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                 //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                     //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2               //
// for applicable conditions.                                                       //
//                                                                                  //
// Description:                                                                     //
//        This combinational circuit (should be 1 LUT per bit) performs muxing and  //
//     bit swapping in the integration combinational logic.                         //
//                                                                                  //
//    Revisions:                                                                    //
//                                                                                  //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

module    flip_mux_main_lut
    (
        // Inputs
        input    wire    signed    [31:0]    in,
        input    wire                        flip,
        // Outputs
        output   wire    signed    [31:0]    out
    );
    
    assign    out            =    flip    ?    ~in    : in;
    
endmodule
