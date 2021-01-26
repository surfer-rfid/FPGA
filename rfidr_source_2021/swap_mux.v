////////////////////////////////////////////////////////////////////////////////////////
//                                                                                    //
// Module : RX Data Recovery Initial Swap and Flip Mux                                //
//                                                                                    //
// Filename: swap_mux.v                                                               //
// Creation Date: 3/24/2015                                                           //
// Author: Edward Keehr                                                               //
//                                                                                    //
// Copyright Superlative Semiconductor LLC 2021                                       //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2        //
// You may redistribute and modify this documentation and make products               //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).           //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                   //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                       //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2                 //
// for applicable conditions.                                                         //
//                                                                                    //
// Description:                                                                       //
//        This combinational circuit (should be 1 LUT per bit) performs muxing and    //
//     bit swapping prior to the integration cominbational logic.                     //
//                                                                                    //
//    Revisions:                                                                      //
//                                                                                    //
//                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////

module    swap_mux
    (
        // Inputs
        input     wire    signed    [15:0]    in_0,
        input     wire    signed    [15:0]    in_1,
        input     wire                        use_0,
        input     wire                        flip,
        // Outputs
        output    wire    signed    [15:0]    out
    );

assign    out    =    use_0 ? (flip ? ~in_0 : in_0) : (flip ? ~in_1 : in_1);

endmodule
