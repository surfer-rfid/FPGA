///////////////////////////////////////////////////////////////////////////////////////
//                                                                                   //
// Module : Reset Management                                                         //
//                                                                                   //
// Filename: reset_mgmt.v                                                            //
// Creation Date: 1/13/2016                                                          //
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
//    This block contains all of the reset management circuitry. In this file,       //
//    we try to do things the 'right' way first, then may try to reduce LUT count    //
//    if we really need to.                                                          //
//                                                                                   //
//    This block uses an async-sync architecture with the global async pin           //
//    coming from the user-IO-enabled DEV_CLRn.    DEV_CLRn is not used because it   //
//    it strictly an asynchronous reset and non-repeatable events could occur        //
//    from its use, complicating debug and interaction with MCU SW.                  //
//                                                                                   //
//    Revisions:                                                                     //
//                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////

module reset_mgmt(
    //Inputs
    input        wire    rst_n_ext,        //Active low reset from external pin
    input        wire    rst_4p5_sw,
    input        wire    clk_27p5,
    input        wire    clk_55,
    input        wire    clk_4p5,
    input        wire    clk_36_in,
    input        wire    clk_36,
    //Outputs
    output       wire    rst_n_27p5,
    output       wire    rst_n_4p5,
    output       wire    rst_n_55,
    output       wire    rst_n_36_in,
    output       wire    rst_n_36
);

// Internal wires

wire    rst_n_4p5_int;

// Internal regs

reg    rst_4p5_reg0, rst_4p5_reg1;
reg    rst_27p5_reg0, rst_27p5_reg1;
reg    rst_36_in_reg0, rst_36_in_reg1;
reg    rst_36_reg0, rst_36_reg1;
reg    rst_55_reg0, rst_55_reg1;

// Instantiated modules

clk_gate_buf rst_buf_4p5 (
    .inclk(rst_4p5_reg1),
    .ena(1'b1),
    .outclk(rst_n_4p5)
);

//assign rst_n_4p5    =    rst_4p5_reg1;

clk_gate_buf rst_buf_27p5 (
    .inclk(rst_27p5_reg1),
    .ena(1'b1),
    .outclk(rst_n_27p5)
);

assign rst_n_36            =    rst_36_reg1;
assign rst_n_36_in         =    rst_36_in_reg1;
assign rst_n_55            =    rst_55_reg1;

// Combinational assignments (think about designing these with low level primitives)

assign    rst_n_4p5_int    =    !rst_4p5_sw && rst_n_ext;

// Reset for 4p5/36MHz domain

always @(posedge clk_4p5 or negedge rst_n_ext) begin
    if(!rst_n_ext)    begin
        rst_4p5_reg0    <=    1'b0;
        rst_4p5_reg1    <=    1'b0;
    end  else    begin
        rst_4p5_reg0    <=    1'b1;
        rst_4p5_reg1    <=    rst_4p5_reg0;
    end
end

// Reset for 27p5/55MHz domain

always @(posedge clk_27p5 or negedge rst_n_ext) begin
    if(!rst_n_ext)    begin
        rst_27p5_reg0    <=    1'b0;
        rst_27p5_reg1    <=    1'b0;
    end  else    begin
        rst_27p5_reg0    <=    1'b1;
        rst_27p5_reg1    <=    rst_27p5_reg0;
    end
end

// Reset for clk_36_in domain

always @(posedge clk_36_in or negedge rst_n_ext) begin
    if(!rst_n_ext)    begin
        rst_36_in_reg0    <=    1'b0;
        rst_36_in_reg1    <=    1'b0;
    end  else    begin
        rst_36_in_reg0    <=    1'b1;
        rst_36_in_reg1    <=    rst_36_in_reg0;
    end
end

// Reset for clk_36 domain

always @(posedge clk_36 or negedge rst_n_ext) begin
    if(!rst_n_ext)    begin
        rst_36_reg0    <=    1'b0;
        rst_36_reg1    <=    1'b0;
    end  else    begin
        rst_36_reg0    <=    1'b1;
        rst_36_reg1    <=    rst_36_reg0;
    end
end

// Reset for clk_55 domain

always @(posedge clk_55 or negedge rst_n_ext) begin
    if(!rst_n_ext)    begin
        rst_55_reg0    <=    1'b0;
        rst_55_reg1    <=    1'b0;
    end  else    begin
        rst_55_reg0    <=    1'b1;
        rst_55_reg1    <=    rst_55_reg0;
    end
end

endmodule
