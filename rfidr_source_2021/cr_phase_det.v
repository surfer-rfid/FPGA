////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module : Phase detector for RX CDR                                             //
//                                                                                //
// Filename: cr_phase_det.v                                                       //
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
//        This is a combinational-logic-only linear phase detector in the digital //
//        domain.                                                                 //
//                                                                                //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module cr_phase_det
    (
        //Inputs
        input        wire                        data,
        input        wire                        clk,
        input        wire                        rst_n,
        input        wire                        clkIph,
        input        wire                        clkIbph,
        //Outputs
        output       wire    signed     [2:0]    phase_delta
    );
    
    // Parameter and localparam declarations
    //    Register and wire declarations
    
    reg     [1:0]    data_mem;
    // Combinational assignments
    
    assign    phase_delta        =  {2'b0,data_mem[0]^data_mem[1]} - {2'b0,data^data_mem[0]};
    
    // always @(*) block for conditional combinational logic
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            data_mem    <=    2'b0;
        end else begin
            if (clkIph) begin                    //Be careful, using this method results in data changing one cycle after we intended it to in Octave code
                data_mem[1]    <=    data_mem[0];
                               
            end
            if (clkIbph) begin
                data_mem[0]    <=    data;
                               
            end
        end
    end
        
endmodule
