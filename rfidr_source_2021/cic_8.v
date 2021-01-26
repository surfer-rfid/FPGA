////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module: Main decimate-by-8 CIC for RFID digital back end                       //
//                                                                                //
// Filename: cic_8.v                                                              //
// Creation Date: 11/27/2015                                                      //
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
// Description: This is a simple decimate-by-8 CIC filter which                   //
// expands the 1-bit SDM input into a 13-bit decimated output.                    //
//                                                                                //
// Revisions:                                                                     //
//    011316                                                                      //
//    input needs to be flopped on negedge of clk_36 then posedge                 //
//                                                                                //
//    032816 - Swap one order of CIC with a literal boxcar filter.                //
//    This saves LUT b/c of first order nature of input. Only issue               //
//    is that it should be reset to 10101010 to avoid any wacky                   //
//    startup transient.                                                          //
//                                                                                //
//    The clk_4p5_stretch_en ensures that the                                     //
//    clock stretching works out so that (at least) regd0 is changed              //
//    at a fixed position relative to the rising edge of clk_4p5.                 //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module cic_8
    (
        // Inputs
        input     wire                       in,
        input     wire                       clk_4p5,
        input     wire                       clk_4p5_stretch_en,
        input     wire                       clk_36,
        input     wire                       rst_n,
        // Outputs
        output    reg    signed    [12:0]    out,
        output    reg                        in_posedge
    );
    
    // Register and wire declarations
    
    wire    signed    [3:0]     adder_out1;
    wire    signed    [12:0]    adder_out2;
    wire    signed    [12:0]    adder_out3;
    wire    signed    [12:0]    adder_out4;
    wire    signed    [12:0]    adder_out5;
    wire    signed    [12:0]    adder_out6;
    wire    signed    [12:0]    adder_out7;
    
    reg     signed    [3:0]     adder_out1a;
    reg     signed    [3:0]     adder_out1b;
    reg                         regi1a;
    reg                         regi1b;
    reg                         regi1c;
    reg                         regi1d;
    reg                         regi1e;
    reg                         regi1f;
    reg                         regi1g;
    reg    signed    [12:0]     regi2;
    reg    signed    [12:0]     regi3;
    reg    signed    [12:0]     regi4;
    
    reg    signed    [12:0]     regd0;
    reg    signed    [12:0]     regd1;
    reg    signed    [12:0]     regd2;
    reg    signed    [12:0]     regd3;
    
    reg                         in_negedge;
    
    // Combinational logic assignments
    
    assign    adder_out1    =    adder_out1a+adder_out1b;
    assign    adder_out2    =    {{8{adder_out1[3]}},adder_out1,1'b0}+regi2;
    assign    adder_out3    =    regi2+regi3;
    assign    adder_out4    =    regi3+regi4;
    assign    adder_out5    =    regd0-regd1;
    assign    adder_out6    =    adder_out5-regd2;
    assign    adder_out7    =    adder_out6-regd3;
    
    // Combinational logic block for the state machine
    // Implement a state machine for clock handover to ensure data at clock crossing boundary is stretched
    // This will ease timing requirements in the new clock domain
    
    
    always @(*)    begin
        case({in_posedge,regi1a,regi1b,regi1c})
            4'b0000:    begin    adder_out1a    =    -4'sd2;    end
            4'b0001:    begin    adder_out1a    =    -4'sd1;    end
            4'b0010:    begin    adder_out1a    =    -4'sd1;    end
            4'b0011:    begin    adder_out1a    =     4'sd0;    end
            4'b0100:    begin    adder_out1a    =    -4'sd1;    end
            4'b0101:    begin    adder_out1a    =     4'sd0;    end
            4'b0110:    begin    adder_out1a    =     4'sd0;    end
            4'b0111:    begin    adder_out1a    =     4'sd1;    end
            4'b1000:    begin    adder_out1a    =    -4'sd1;    end
            4'b1001:    begin    adder_out1a    =     4'sd0;    end
            4'b1010:    begin    adder_out1a    =     4'sd0;    end
            4'b1011:    begin    adder_out1a    =     4'sd1;    end
            4'b1100:    begin    adder_out1a    =     4'sd0;    end
            4'b1101:    begin    adder_out1a    =     4'sd1;    end
            4'b1110:    begin    adder_out1a    =     4'sd1;    end
            4'b1111:    begin    adder_out1a    =     4'sd2;    end
        endcase
    end
    
    always @(*)    begin
        case({regi1d,regi1e,regi1f,regi1g})
            4'b0000:    begin    adder_out1b    =    -4'sd2;    end
            4'b0001:    begin    adder_out1b    =    -4'sd1;    end
            4'b0010:    begin    adder_out1b    =    -4'sd1;    end
            4'b0011:    begin    adder_out1b    =     4'sd0;    end
            4'b0100:    begin    adder_out1b    =    -4'sd1;    end
            4'b0101:    begin    adder_out1b    =     4'sd0;    end
            4'b0110:    begin    adder_out1b    =     4'sd0;    end
            4'b0111:    begin    adder_out1b    =     4'sd1;    end
            4'b1000:    begin    adder_out1b    =    -4'sd1;    end
            4'b1001:    begin    adder_out1b    =     4'sd0;    end
            4'b1010:    begin    adder_out1b    =     4'sd0;    end
            4'b1011:    begin    adder_out1b    =     4'sd1;    end
            4'b1100:    begin    adder_out1b    =     4'sd0;    end
            4'b1101:    begin    adder_out1b    =     4'sd1;    end
            4'b1110:    begin    adder_out1b    =     4'sd1;    end
            4'b1111:    begin    adder_out1b    =     4'sd2;    end
        endcase
    end
    
    always @(posedge clk_36 or negedge rst_n)    begin
        if (!rst_n) begin
            in_posedge   <=    1'b0;
            regi1a       <=    1'b1;
            regi1b       <=    1'b0;
            regi1c       <=    1'b1;
            regi1d       <=    1'b0;
            regi1e       <=    1'b1;
            regi1f       <=    1'b0;
            regi1g       <=    1'b1;
            regi2        <=    13'b0;
            regi3        <=    13'b0;
            regi4        <=    13'b0;
            regd0        <=    13'b0;
        end    else    begin
            in_posedge   <=    in_negedge;
            regi1a       <=    in_posedge;
            regi1b       <=    regi1a;
            regi1c       <=    regi1b;
            regi1d       <=    regi1c;
            regi1e       <=    regi1d;
            regi1f       <=    regi1e;
            regi1g       <=    regi1f;
            regi2        <=    adder_out2;
            regi3        <=    adder_out3;
            regi4        <=    adder_out4;

        //Here is the transition between clk_36 and clk_4p5 domains.
        //We needed to use a signal synced with the clk_4p5 edge on the clk_36 domain.

            if(clk_4p5_stretch_en)
                regd0    <=    regi4;
        end
    end
    
    always @(negedge clk_36 or negedge rst_n) begin
        if(!rst_n)
            in_negedge    <=    1'b1;
        else
            in_negedge    <=    in;
    end
    
    always @(posedge clk_4p5 or negedge rst_n) begin
        if (!rst_n) begin
            regd1        <=    13'b0;
            regd2        <=    13'b0;
            regd3        <=    13'b0;
            out          <=    13'b0;
        end    else    begin
            regd1        <=    regd0;
            regd2        <=    adder_out5;
            regd3        <=    adder_out6;
            out          <=    adder_out7;
        end
    end
        
endmodule