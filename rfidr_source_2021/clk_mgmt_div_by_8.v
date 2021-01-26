////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module : Clock Management Divide by 8                                          //
//                                                                                //
// Filename: clk_mgmt_div_by_8.v                                                  //
// Creation Date: 2/29/2016                                                       //
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
// Description:                                                                   //
//                                                                                //
//    Explicitly instantiate the divide-by-8 in clock management to see if we     //
//    can get the timing tool to recognize the raw divider output.                //
//                                                                                //
//    The stretch_en signal is required to be sent back to the clk_36/clk_4p5     //
//    interface in cic_8.v to synchronize that clock domain crossing.             //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module clk_mgmt_div_by_8(
    //Inputs
    input        wire        clk_36_in,
    input        wire        rst_n_36_in,
    //Outputs
    output       reg         clk_4p5_unbuf_out,
    output       reg         clk_4p5_stretch_en
);

reg    [2:0]        clk_4p5_div_ctr;

always @(posedge clk_36_in or negedge rst_n_36_in) begin
    if(!rst_n_36_in)    begin
        clk_4p5_div_ctr       <=    3'b000;
        clk_4p5_unbuf_out     <=    1'b0;
        clk_4p5_stretch_en    <=    1'b0;
    end else begin
        clk_4p5_div_ctr       <=    clk_4p5_div_ctr+3'b001;
        clk_4p5_unbuf_out     <=    clk_4p5_div_ctr[2];
        clk_4p5_stretch_en    <=    (!clk_4p5_div_ctr[2]) && clk_4p5_div_ctr[1] && (!clk_4p5_div_ctr[0]);
    end
end

endmodule