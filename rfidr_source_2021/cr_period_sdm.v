////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module : Period computing SDM for RX CDR                                       //
//                                                                                //
// Filename: cr_period_sdm.v                                                      //
// Creation Date: 12/1/2015                                                       //
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
//        This is the sigma delta modulator which computes the instantaneous      //
//        tag BLF period value in the clock recovery PLL.                         //
//                                                                                //
//    Revisions:                                                                  //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module cr_period_sdm
    (
        //Inputs
        input    wire    signed    [16:0]    tank_lsb,
        input    wire                        clk,
        input    wire                        clk_mask,
        input    wire                        rst_n,
        //Outputs
        output   reg               [3:0]     period
    );
    
    // Parameter and localparam declarations
    //    Register and wire declarations
    
    wire    signed    [17:0]    error; //17b plus 16 bit
    wire    signed    [18:0]    intg_pre; //17b plus 16 bit plus 16 bit
    wire    signed    [15:0]    intg_next;
    
    reg               [3:0]     period_next;
    reg     signed    [15:0]    fb_next;
    reg     signed    [15:0]    fb;
    reg     signed    [15:0]    intg;
    
    // Module Instantiations
    
    signed_saturate
        #(
            .WIDTH_IN(18),
            .WIDTH_OUT(15)
        )
    sat1
        (
            .in     (intg_pre),
            .out    (intg_next)
        );
        
    // Combinational assignments
    
    assign    error       =    {tank_lsb[16],tank_lsb}-{{2{fb[15]}},fb};
    assign    intg_pre    =    {error[17],error}+{{3{intg[15]}},intg};
    
    // Conditional combinational assignments
    
    always @(*) begin
        if(intg_next    > 16'sd18431) begin
            period_next    =    4'd14;
            fb_next        =    16'sd24576;
        end else if (intg_next > 16'sd6143) begin
            period_next    =    4'd13;
            fb_next        =    16'sd12288;
        end else if (intg_next > -16'sd6145) begin
            period_next    =    4'd12;
            fb_next        =    16'sd0;
        end else if (intg_next    > -16'sd18433) begin
            period_next    =    4'd11;
            fb_next        =    -16'sd12288;
        end else begin
            period_next    =    4'd10;
            fb_next        =    -16'sd24576;
        end
    end
        
    // Flops inference

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            period    <=    4'd12;
            fb        <=    16'sd0;
            intg      <=    16'sd0;
        end else if(clk_mask) begin //Note that this result in period being updated on the counter=1
            period    <=    period_next;
            fb        <=    fb_next;
            intg      <=    intg_next;
        end
    end
endmodule
