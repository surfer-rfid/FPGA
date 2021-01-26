////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module: Channel filter for RX'ed backscatter data - biquad section             //
//                                                                                //
// Filename: chnl_filt_dfii.v                                                     //
// Creation Date: 12/13/2015                                                      //
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
// Description: This is a discrete-time analog of two tuned LC                    //
// tanks in series which span the range of frequencies realizable                 //
// by the tag backscatter signal.                                                 //
// This file is actually a sub-function which realizes one of the                 //
// two direct-form-II structures                                                  //
//                                                                                //
// Note that register widths are 3 bits less than in Octave                       //
// because input is not actually 16b but 13b                                      //
//                                                                                //
// Revisions:                                                                     //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module chnl_filt_dfii
    (
        // Inputs
        input        wire    signed    [19:0]    in,
        input        wire                        clk,
        input        wire                        blank,
        input        wire                        rst_n,
        // Outputs
        output       wire    signed    [15:0]    out
    );
         
    // Register and wire declarations
    
    reg     signed                     [17:0]    stg1_reg;
    reg     signed                     [17:0]    stg2_reg;
    
    
    wire    signed                    [17:0]    stg1_reg_next;
    wire    signed                    [17:0]    stg2_reg_next;
    wire    signed                    [21:0]    adder1_out;
    wire    signed                    [20:0]    adder2_out;
    wire    signed                    [18:0]    adder3_out;
    wire    signed                    [25:0]    multr1_out;
    wire    signed                    [25:0]    multr2_out;
    wire    signed                    [17:0]    adder1_out_sat;
    wire    signed                    [17:0]    adder1_out_sat_blank;

    
    // Module declarations
    
    lpm_mult_const
        #(
            .WIDTH_IN(18),
            .WIDTH_OUT(26),
            .MULT_CONST(7'd118)
        )
    mult_1
        (
            .a_in(stg1_reg),
            .y_out(multr1_out)
        );
        
    lpm_mult_const
        #(
            .WIDTH_IN(18),
            .WIDTH_OUT(26),
            .MULT_CONST(7'd60)
        )
    mult_2
        (
            .a_in(stg2_reg),
            .y_out(multr2_out)
        );    
    
    signed_saturate
        #(
            .WIDTH_IN(20),
            .WIDTH_OUT(17)
        )
    sat1
        (
            .in(adder1_out[21:1]),
            .out(adder1_out_sat)
        );
            
    // Combinational logic - assign statements, now always @(*) since we must support the if statement
    
    assign        adder1_out              =    {{2{in[19]}},in} + {adder2_out[20],adder2_out};
    assign        adder1_out_sat_blank    =    blank ? 18'sb0 : adder1_out_sat;    //061920 - This actually doesn't come for free. Maybe look into why.
    //assign        adder1_out_sat_blank    =    adder1_out_sat; //Since this is the second of two IIR filters, it's likely that we don't need the blanker here.
    assign        adder2_out              =    {multr1_out[25],multr1_out[24:5]} - {multr2_out[25],multr2_out[24:5]};
    assign        adder3_out              =    {adder1_out_sat_blank[17],adder1_out_sat_blank} - {stg2_reg[17],stg2_reg};
    assign        out                     =    adder3_out[17:2];
    assign        stg1_reg_next           =    adder1_out_sat_blank;
    assign        stg2_reg_next           =    stg1_reg;
    
    // Flops inference
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg1_reg        <=    18'sb0;
            stg2_reg        <=    18'sb0;
        end else begin 
            stg1_reg        <=    stg1_reg_next;
            stg2_reg        <=    stg2_reg_next;
        end
    end
        
    endmodule
    