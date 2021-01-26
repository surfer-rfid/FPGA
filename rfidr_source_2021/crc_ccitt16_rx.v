///////////////////////////////////////////////////////////////////////////////////////
//                                                                                   //
// Module : Streaming RX CRC Checker for RFIDr Data Recovery block                   //
//                                                                                   //
// Filename: crc_ccitt16_rx.v                                                        //
// Creation Date: 12/7/2015                                                          //
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
//        This is the CRC checker that computes whether the CRC checksum is valid    //
//        on a bit by bit basis. At the last bit of the packet, the higher level     //
//        module checks the 'valid' output. If it is 1, then the CRC is valid.       //
//                                                                                   //
//    Revisions:                                                                     //
//                                                                                   //
//    090716 - Finally get around to fixing this to comply with Appendix F of the    //
//    UHF RFID specification.                                                        //
//                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////

module    crc_ccitt16_rx
    (
        // Inputs
        input        wire    bit_in,
        input        wire    shift,
        input        wire    clk,
        input        wire    rst_n_global,
        input        wire    rst_n_local,
        // Outputs
        output       reg     crc_out
    );
    
    // Parameter and localparam declarations
    
    //localparam    CRC_POLY    =    16'd4129;
    localparam    CRC_POLY    =    16'b0001_0000_0010_0000;
    
    // wire and reg declarations
    
    reg    [15:0]        shift_reg;
    reg    [15:0]        shift_reg_next;
    reg                  crc_out_next;
    
    // Combinational logic - always @(*)
    
    always @(*) begin
        shift_reg_next    =    shift_reg;
        crc_out_next      =     crc_out;
        
        if(shift) begin
            shift_reg_next    =    ({16{shift_reg[15] ^ bit_in}} & CRC_POLY) ^ {shift_reg[14:0],shift_reg[15] ^ bit_in};
            crc_out_next      =    (shift_reg_next == 16'h1D0F);
        end
    end
    
    // Flops inference
    
    always @(posedge clk or negedge rst_n_global) begin
        if(!rst_n_global) begin
            shift_reg    <=    16'hFFFF;
            crc_out      <=    0;
        end else if(!rst_n_local) begin
            shift_reg    <=    16'hFFFF;
            crc_out      <=    0;
        end else begin
            shift_reg    <=    shift_reg_next;
            crc_out      <=    crc_out_next;
        end
    end
endmodule
