/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module: Main decimate-by-128 CIC for RFID digital back end                      //
//                                                                                 //
// Filename: dec_128.v                                                             //
// Creation Date: 12/13/2015                                                       //
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
// Description: This is a simple low pass filter intended to be                    //
// more LUT efficient than the CIC-128 filter                                      //
//                                                                                 //
// Revisions:                                                                      //
//                                                                                 //
// 032516 - Replace the second stage with an integrate-and-dump                    //
// filter, which saves multipliers and LUT. Multipliers can be                     //
//    used elsewhere to save even more LUT.                                        //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module dec_128
    (
        // Inputs
        input     wire    signed    [12:0]    in,
        input     wire                        clk_4p5,
        input     wire                        rst_n,
        // Outputs
        output    reg     signed    [15:0]    regout,
        output    reg                         ready
    );
    
    // Parameter and localparam declarations
    
    // Skip the state declarations, there will be too many
    // Just use a counter - synthesis should be the same anyway
    
    // Register and wire declarations
    
    wire    signed    [21:0]    adder_out1;
    wire    signed    [17:0]    adder_out1_sat;
    wire    signed    [24:0]    multr_out1;
    wire    signed    [17:0]    regi1_next;
    
    reg     signed    [17:0]    regi1;
    reg     signed    [20:0]    regi2, regi2_next;
    
    reg     signed    [15:0]    next_regout;    //Rename this someday????
    reg                         ready_next;

    
    reg                [7:0]    curr_state, next_state;    // 256 states
    
    reg                         sclr_regi2;
    
    // Module declarations
    
    lpm_mult_const
        #(
            .WIDTH_IN(18),
            .WIDTH_OUT(25),
            .MULT_CONST(7'd63)
        )
    mult_1
        (
            .a_in(regi1),
            .y_out(multr_out1)
        );
        
    signed_saturate
        #(
            .WIDTH_IN(19),
            .WIDTH_OUT(17)
        )
    sat1
        (
            .in(adder_out1[21:2]),
            .out(adder_out1_sat)
        );
    
    // Combinational logic assignments
    
    assign    adder_out1    =    {{8{in[12]}},in,1'b1}+{multr_out1[24],multr_out1[24:5],1'b1}; // Force addition of 1 by explicitly generating a carry in signal to the LSB
    assign    regi1_next    =    adder_out1_sat;
    
    // Combinational logic block for the state machine
    // Implement a state machine for clock handover to ensure data at clock crossing boundary is stretched
    // This will ease timing requirements in the new clock domain
    
    always @(*)
        begin
            // Assign all default values here
            
            next_state        =    curr_state+8'd1;
            next_regout       =    regout;
            ready_next        =    1'b0;
            //regi2_next      =    {{7{regi1[17]}},regi1[17:4]}+regi2;
            regi2_next        =    {{7{in[12]}},in,1'b0}+regi2;
            sclr_regi2        =    1'b0;
            
            if(curr_state[6:0] == 7'd127)
                begin
                    //ready_next    =    1'b1;
                    sclr_regi2      =    1'b1;
                    //next_regout   =    regi2_next[20:5];
                end
            if(curr_state[7:0] == 8'd255)
                begin
                    ready_next    =    1'b1;
                    //sclr_regi2  =    1'b1;
                    next_regout   =    regi2_next[20:5];
                end    
        end
    
    // Flops inference
    
    always @(posedge clk_4p5 or negedge rst_n)
        begin
            if (!rst_n)
                begin
                    curr_state    <=    8'b0;
                    regi1         <=    18'b0;
                    regout        <=    16'b0;
                    ready         <=    1'b0;
                end
            else
                begin
                    curr_state    <=    next_state;
                    regi1         <=    regi1_next;
                    regout        <=    next_regout;
                    ready         <=    ready_next;
                end
        end
        
    always @(posedge clk_4p5 or negedge rst_n) begin
        if(!rst_n)
            regi2    <=    21'b0;
        else if (sclr_regi2)
            regi2    <=    21'b0;
        else
            regi2    <=    regi2_next;
    end
        
endmodule