///////////////////////////////////////////////////////////////////////////////////////
//                                                                                   //
// Module : RN16 and Handle Shift Registers                                          //
//                                                                                   //
// Filename: rn16_and_handle_shift_regs.v                                            //
// Creation Date: 6/24/2016                                                          //
// Author: Edward Keehr                                                              //
//                                                                                   //
// Copyright Superlative Semiconductor LLC 2021                                      //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2       //
// You may redistribute and modify this documentation and make products              //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).          //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                  //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                      //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2                //
// for applicable conditions.                                                        //
//                                                                                   //
// Description:                                                                      //
//                                                                                   //
//    This module provides a storage intermediary between the data_rcvy and tx_gen   //
//    modules for the rn16 and handle values so that we can save 32 registers and    //
//    nearly 32 LUTs. It's not a lot of LUTs but every LUT counts at this point.     //
//                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////

module rn16_and_handle_shift_regs
    (
        // Inputs
        input    wire    in_rn16,
        input    wire    in_handle,
        input    wire    shift_rn16_from_dr,
        input    wire    shift_rn16_to_txgen,
        input    wire    shift_handle_from_dr,
        input    wire    shift_handle_to_txgen,
        input    wire    rst_n,
        input    wire    clk,
        
        //Outputs
        output    wire    out_rn16,
        output    wire    out_handle
    );
    
    wire                shift_rn16, shift_handle, in_reg_rn16, in_reg_handle;
    reg       [15:0]    reg_rn16, reg_handle;
    
    assign    shift_rn16      =    shift_rn16_from_dr      ||     shift_rn16_to_txgen;
    assign    shift_handle    =    shift_handle_from_dr    ||     shift_handle_to_txgen;
    assign    in_reg_rn16     =    shift_rn16_from_dr      ?      in_rn16     :    out_rn16;
    assign    in_reg_handle   =    shift_handle_from_dr    ?      in_handle   :    out_handle;
    assign    out_rn16        =    reg_rn16[15];
    assign    out_handle      =    reg_handle[15];
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            reg_rn16          <=    16'b0000_0000_0000_0000;
            reg_handle        <=    16'b0000_0000_0000_0000;
        end else begin
            if(shift_rn16)
                reg_rn16      <=    {reg_rn16[14:0], in_reg_rn16};
            else
                reg_rn16      <=    reg_rn16;
            if(shift_handle)
                reg_handle    <=    {reg_handle[14:0], in_reg_handle};
            else
                reg_handle    <=    reg_handle;
        end
    end
endmodule
        
            
            