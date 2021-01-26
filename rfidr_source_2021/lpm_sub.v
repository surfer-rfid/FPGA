/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Variable width subtractor using Altera/Intel FPGA IP                   //
//                                                                                 //
// Filename: lpm_sub.v                                                             //
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
//    This code instantiates the Altera/Intel FPGA IP for a subtractor so that we  //
//    can better control how it is synthesized. We make this parameterizable so    //
//    that we can keep our code base clean.                                        //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module lpm_sub #(parameter WIDTH_IN_OUT=16)
    (
        input     wire     signed    [WIDTH_IN_OUT-1:0]    a_in,
        input     wire     signed    [WIDTH_IN_OUT-1:0]    b_in,
        output    wire     signed    [WIDTH_IN_OUT-1:0]    y_out
    );

   lpm_add_sub   sub_core (
            .dataa (a_in),
            .datab (b_in),
            .result (y_out),
            .aclr (),
            .add_sub (),
            .cin (),
            .clken (),
            .clock (),
            .cout (),
            .overflow ()
            );
   defparam
      sub_core.lpm_direction = "SUB",
      sub_core.lpm_hint = "ONE_INPUT_IS_CONSTANT=NO,CIN_USED=NO",
      sub_core.lpm_representation = "SIGNED",
      sub_core.lpm_type = "LPM_ADD_SUB",
      sub_core.lpm_width = WIDTH_IN_OUT;

endmodule