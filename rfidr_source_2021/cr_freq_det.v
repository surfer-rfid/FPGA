//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
// Module : Edge detector for RX CDR                                            //
//                                                                              //
// Filename: cr_freq_det.v                                                      //
// Creation Date: 12/1/2015                                                     //
// Author: Edward Keehr                                                         //
//                                                                              //
// Copyright Superlative Semiconductor LLC 2021                                 //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2  //
// You may redistribute and modify this documentation and make products         //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).     //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED             //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                 //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2           //
// for applicable conditions.                                                   //
//                                                                              //
// Description:                                                                 //
//        This is a rotational frequency detector with extra memory to stop     //
//        chattering during lock.                                               //
//                                                                              //
//    Revisions:                                                                //
//                                                                              //
//    031216 - Update to an edge-based design                                   //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////

module    cr_freq_det
    (
        // Inputs
        input    wire         data_edge,
        input    wire         clk,
        input    wire         rst_n,
        input    wire         phI_edge,
        input    wire         phQ_edge,
        input    wire         phIb_edge,
        input    wire         phQb_edge,
        // Outputs
        output    wire        signed    [1:0]        out
    );
    
    // Parameter and localparam declarations
    //    Register and wire declarations
    
    reg                       phb_reg0;
    reg                       phb_reg1;
    reg                       phb_reg2;
    reg                       phb_gen_reg;
    reg                       phc_reg0;
    reg                       phc_reg1;
    reg                       phc_reg2;
    reg                       phc_gen_reg;
    
    assign    out            =    {1'b0,(phc_reg1 && phb_reg2)} - {1'b0,(phb_reg1 && phc_reg2)};
                
// Flops inference
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)    begin
            phb_reg0       <=    1'b0;
            phb_reg1       <=    1'b0;
            phb_reg2       <=    1'b0;
            phb_gen_reg    <=    1'b0;
            phc_reg0       <=    1'b0;
            phc_reg1       <=    1'b0;
            phc_reg2       <=    1'b0;
            phc_gen_reg    <=    1'b0;
        end else begin
            
            if(phI_edge) begin
                phb_reg1    <=    phb_reg0;
                phb_reg2    <=    phb_reg1;
                phc_reg1    <=    phc_reg0;
                phc_reg2    <=    phc_reg1;
            end
            if(phQ_edge) begin
                phb_gen_reg    <=    1'b1;
                if(data_edge) begin
                    phb_reg0   <=    1'b1;
                    phc_reg0   <=    1'b0;
                end
            end
            if(phIb_edge) begin
                phb_gen_reg    <=    1'b0;
                phc_gen_reg    <=    1'b1;
                if(data_edge) begin
                    phb_reg0   <=    1'b0;
                    phc_reg0   <=    1'b1;
                end
            end
            if(phQb_edge) begin
                phc_gen_reg    <=    1'b0;
                if(data_edge) begin
                    phb_reg0   <=    1'b0;
                    phc_reg0   <=    1'b0;
                end
            end
            if(data_edge && !phQ_edge && !phIb_edge && !phQb_edge) begin
                phb_reg0    <=    phb_gen_reg;
                phc_reg0    <=    phc_gen_reg;
            end
        end
    end
endmodule
