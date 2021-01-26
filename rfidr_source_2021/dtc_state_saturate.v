/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Signed saturator for integer arithemtic                                //
//                                                                                 //
// Filename: dtc_state_saturate.v                                                  //
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
//    This code performs a signed saturation for the txcancel.v block dtc state.   //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module dtc_state_saturate
    (
        input     wire     signed    [17:0]    in,
        output    wire     signed    [15:0]    out
    );
    
    assign out = (in > 18'sd32767) ? 16'sd32767 : ((in >= 18'sd0) ? in[15:0] : 16'sb0);
    
endmodule