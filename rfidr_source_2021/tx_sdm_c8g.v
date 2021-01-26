/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Sigma-delta modulator for TX data                                      //
//                                                                                 //
// Filename: tx_sdm.v                                                              //
// Creation Date: 11/24/2015                                                       //
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
//    This sigma delta modulator is designed to convert a 1-bit low-frequency      //
//     input representing the RFID TX signl into a 1-bit sigma-delta stream        //
//    compatible with the SX1257 software defined radio front-end.                 //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
//    030116 - Add provision to retime output with input clock.                    //
//    030316 - Moved delays around to close timing at 36MHz.                       //
//    031316 - Move saturations around to improve timing and reduce extra LUT.     //
//    091416 - {1,0} pattern in should produce {1,0} out.                          //
//    122320 - Add offset programmable from SPI                                    //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module tx_sdm_c8g
    (
        // Inputs
        input wire in,
        input wire clk,
        input wire rst_n,
        input wire clk_out,
        input wire rst_n_out,
        input wire [3:0] offset,
        // Outputs
        output reg out
    );
    
    // Parameter and localparam declarations
    // Register and wire declarations
    
    reg                            in_reg;
    reg        signed    [9:0]     stg1_reg;
    reg        signed    [16:0]    stg2_reg;
    reg        signed    [9:0]     stg3_reg;
    reg        signed    [11:0]    stg4_reg;
    reg        signed    [11:0]    stg5_reg;
    reg                  [17:0]    lfsr;
    
    reg                            in_reg2;
    reg                            out_reg_pre;
    
    wire                           lfsr_new;
    wire                           out_next;
    
    wire       signed    [5:0]     adder1_int;
    wire       signed    [9:0]     adder1_out;
    wire       signed    [10:0]    adder2_out;
    wire       signed    [16:0]    adder3_out;
    wire       signed    [17:0]    adder4_out;
    wire       signed    [10:0]    adder5_out;
    wire       signed    [11:0]    adder6_int1;
    wire       signed    [11:0]    adder6_int2;
    wire       signed    [11:0]    adder6_out;
    wire       signed    [11:0]    adder7_int1;
    wire       signed    [11:0]    adder7_out;
    wire       signed    [13:0]    adder8_out;
    
    wire       signed    [9:0]     adder2_out_sat;
    wire       signed    [16:0]    adder4_out_sat;
    wire       signed    [9:0]     adder5_out_sat;
    
    // Module declarations
    
    signed_saturate
        #(
            .WIDTH_IN(10),
            .WIDTH_OUT(9)
        )
    sat1
        (
            .in     (adder2_out),
            .out    (adder2_out_sat)
        );
    
    signed_saturate
        #(
            .WIDTH_IN(17),
            .WIDTH_OUT(16)
        )
    sat2
        (
            .in     (adder4_out),
            .out    (adder4_out_sat)
        );
        
    signed_saturate
        #(
            .WIDTH_IN(10),
            .WIDTH_OUT(9)
        )
    sat3
        (
            .in     (adder5_out),
            .out    (adder5_out_sat)
        );

    //assign adder1_out         =     {5'b0,in_reg2} - {3'b0,out_next,2'b0} + 6'sd2;
    //Turn 1,0 patterns into 1, -1 patterns, multiply "out" by 3 - 091416 - Actually we do need 1,0 patterns in (not 2,0)
    lpm_sub 
        #(
            .WIDTH_IN_OUT(6)
        )
    adder1a
        (
            .a_in      ({5'b0,in_reg2}),
            .b_in      ({3'b0,out_next,2'b0}),
            .y_out     (adder1_int)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(10)
        )
    adder1b
        (
            .c_in      (1'b0),
            .a_in      ({adder1_int,4'b0}),
            .b_in      ({4'b0,1'b1,1'b0,offset}), //Add offset so that the modulation depth of the reader meets spec.
            .y_out     (adder1_out)
        );
    //assign adder2_out         =     {adder1_out[5],adder1_out} + {stg1_reg[5],stg1_reg};
    //Integrator 1 addition
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(11)
        )
    adder2
        (
            .c_in      (1'b0),
            .a_in      ({adder1_out[9],adder1_out}),    
            .b_in      ({stg1_reg[9],stg1_reg}),
            .y_out     (adder2_out)
        );

    //assign adder6_out        =    {{2{stg3_reg[9]}},stg3_reg} + {adder2_out_sat[5],adder2_out_sat,5'b0} + {{3{adder2_out_sat[5]}},adder2_out_sat,3'b0}  + {8'b0,lfsr_new,3'b0};
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(12)
        )
    adder6a
        (
            .c_in      (1'b0),
            .a_in      ({8'b0,lfsr_new,3'b0}),    
            .b_in      ({{3{adder2_out_sat[9]}},adder2_out_sat[9:1]}),
            .y_out     (adder6_int1)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(12)
        )
    adder6b
        (
            .c_in      (1'b0),
            .a_in      (adder6_int1),
            .b_in      ({{2{stg3_reg[9]}},stg3_reg}),
            .y_out     (adder6_int2)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(12)
        )
    adder6c
        (
            .c_in       (1'b0),
            .a_in       (adder6_int2),
            .b_in       ({adder2_out_sat[9],adder2_out_sat[9:0],1'b0}),
            .y_out      (adder6_out)
        );
    //assign adder7_out        =    {{2{adder4_out_sat[16]}},adder4_out_sat[16:7]} + {{4{adder4_out_sat[16]}},adder4_out_sat[16:9]} - 12'sd4;
    //Convert dither to signed value, add in front of quantizer
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(12)
        )
    adder7a
        (
            .c_in       (1'b0),
            .a_in       ({{4{adder4_out_sat[16]}},adder4_out_sat[16:9]}),    
            .b_in       (-12'sd4),
            .y_out      (adder7_int1)
        );    
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(12)
        )
    adder7b
        (
            .c_in        (1'b0),
            .a_in        (adder7_int1),
            .b_in        ({{2{adder4_out_sat[16]}},adder4_out_sat[16:7]}),
            .y_out       (adder7_out)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(14)
        )
    adder8    //assign adder8_out        =    {stg4_reg[11],stg4_reg} + {stg5_reg[11],stg5_reg};
        (
            .c_in        (1'b0),
            .a_in        ({{2{stg4_reg[11]}},stg4_reg}),    
            .b_in        ({{2{stg5_reg[11]}},stg5_reg}),
            .y_out       (adder8_out)
        );
    
    // Combinational logic - assign statements
    
    assign lfsr_new         =    lfsr[10] ^ lfsr[17];                                                        // Generate new bit to be fed into LFSR
    assign out_next         =    (adder8_out >= 0) ? 1'b1 : 1'b0;
    assign adder3_out       =    {adder2_out_sat[9],adder2_out_sat[9:0],6'b0} - {{7{stg3_reg[9]}},stg3_reg}; //    c2*reg1-g1*reg3
    assign adder4_out       =    {adder3_out[16],adder3_out} + {stg2_reg[16],stg2_reg};                      //    Integrator 2 addition
    assign adder5_out       =    {{4{adder4_out_sat[16]}},adder4_out_sat[16:10]} + {stg3_reg[9],stg3_reg};
    
    // Flops inference
    
    always @(posedge clk or negedge rst_n)
        begin
            if (!rst_n)    begin
                in_reg      <=    1'b0;
                in_reg2     <=    1'b0;
                stg1_reg    <=    6'sb0;
                stg2_reg    <=    17'sb0;
                stg3_reg    <=    10'sb0;
                stg4_reg    <=    12'sb0;
                stg5_reg    <=    12'sb0;
            end    else    begin
                in_reg      <=    in;
                in_reg2     <=    in_reg;
                stg1_reg    <=    adder2_out_sat;
                stg2_reg    <=    adder4_out_sat;
                stg3_reg    <=    adder5_out_sat;
                stg4_reg    <=    adder6_out;
                stg5_reg    <=    adder7_out;
            end
       end
    
    always @(posedge clk or negedge rst_n)
        begin
            if (!rst_n)    begin
                lfsr        <= {18{1'b1}};
            end    else    begin
                lfsr        <= {lfsr[16:0],lfsr_new};
            end
        end
        
    always @(posedge clk_out or negedge rst_n_out)
        begin
            if (!rst_n_out)    begin
                out         <=    1'b0;
                out_reg_pre <=    1'b0;
            end    else    begin
                out_reg_pre <=    out_next;
                out         <=    out_reg_pre;
            end
        end
        
endmodule
    