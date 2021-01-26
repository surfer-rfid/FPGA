//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
// Module : RX Data Recovery Swap Mux                                               //
//                                                                                  //
// Filename: flip_mux.v                                                             //
// Creation Date: 12/17/2015                                                        //
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

module    swap_mux
    (
        // Inputs
        input    wire    signed    [15:0]    in,
        input    wire                        swap,
        // Outputs
        output   wire    signed    [31:0]    in_swapd
    );

    wire    signed    [31:0]    in_extend;
    
    assign    in_extend    =    {{16{in[15]}},in};
    assign    in_swapd     =    !swap    ?    in_extend    : (~in_extend) + 1;
    
endmodule
