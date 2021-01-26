////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module : TX Zero pattern generator                                             //
//                                                                                //
// Filename: tx_zero_pattern_gen.v                                                //
// Creation Date: 1/8/2016                                                        //
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
//    In order to save LUT, we don't use a TX Q SDM. Rather, since we intend to   //
//    output zero signal on the Q channel, we play back a pattern whose harmonics //
//    end up on the nulls of the SX1257 TX DAC FIR filter. In order for this to   //
//    work as well as possible, we must choose a fundamental frequency low enough //
//    so that its harmonic energy is spread to higher frequencies, but high       //
//    enough to experience significant filtering from the analog TX filter (since //
//    the TX DAC FIR nulls will not be perfect.)                                  //
//                                                                                //
//    Revisions:                                                                  //
//    122320 Add SPI control of offset.                                           //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module tx_zero_pattern_gen_c8g
    (
        // Inputs
        input wire clk,
        input wire rst_n,
        input wire [3:0] offset,
        // Outputs
        output reg out
    );
    
    // Parameter and localparam declarations
    // Register and wire declarations
    wire            result;
    // Here we implement a trivial divide-by-16 clock
    reg    [3:0]    counter;
    
    // Combinational logic - assign statements
    assign    result    =    counter >= offset; 
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            counter    <=    4'b0;
            out        <=    1'b0;
        end else begin
            counter    <=    counter+4'b1;
            out        <=    result;
        end
    end
endmodule
            