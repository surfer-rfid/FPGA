//////////////////////////////////////////////////////////////////////////////////////////
//                                                                                      //
// Module : Clock and Reset Management                                                  //
//                                                                                      //
// Filename: clk_and_reset_mgmt.v                                                       //
// Creation Date: 8/05/2016                                                             //
// Author: Edward Keehr                                                                 //
//                                                                                      //
// Copyright Superlative Semiconductor LLC 2021                                         //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2          //
// You may redistribute and modify this documentation and make products                 //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).             //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                     //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                         //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2                   //
// for applicable conditions.                                                           //
//                                                                                      //
// Description:                                                                         //
//                                                                                      //
// This file just agglomerates the clock and reset management functions together since  //
// verification will be performed on both of them at once. And of course, we want this  //
// verification to remain valid at the top level.                                       //
//                                                                                      //
//////////////////////////////////////////////////////////////////////////////////////////

module clk_and_reset_mgmt(
      //Clk Mgmt Inputs
    input         wire        clk_36_in,
    input         wire        clk_36_start,            //Needs to come from spi.v
    //Reset Mgmt Inputs
    input         wire        rst_n_ext,               //Active low reset from external pin
    input         wire        rst_4p5_sw,
    //Clk Mgmt Outputs
    output        wire        clk_36,
    output        wire        clk_4p5,
    output        wire        clk_4p5_stretch_en,
    output        wire        clk_36_valid_reg,        //Needs to go to spi.v. This signal means that we have a valid clock from the SX1257.
    output        wire        clk_36_running_reg,      //Needs to go to spi.v. This signal means that the internal 36MHz clock is running. It is delayed somewhat from the actual state machine.
    output        wire        clk_36_irq,              //Needs to go to rfdir_fsm.v. This signal informs 
    output        wire        clk_27p5,
    //Reset Mgmt Outputs
    output        wire        rst_n_27p5,
    output        wire        rst_n_4p5,
    output        wire        rst_n_36_in,
    output        wire        rst_n_36
);

// Wire declarations

wire    clk_55, rst_n_55;

//Module declarations

clk_mgmt    clk_mgmt0(
    //Inputs
    .clk_36_in(clk_36_in),
    .clk_36_start(clk_36_start),                //Needs to come from spi.v
    .rst_n_4p5(rst_n_4p5),
    .rst_n_27p5(rst_n_27p5),
    .rst_n_36_in(rst_n_36_in),
    .rst_n_36(rst_n_36),
    .rst_n_55(rst_n_55),
    //Outputs
    .clk_36(clk_36),
    .clk_4p5(clk_4p5),
    .clk_4p5_stretch_en(clk_4p5_stretch_en),
    .clk_36_valid_reg(clk_36_valid_reg),        //Needs to go to spi.v. This signal means that we have a valid clock from the SX1257.
    .clk_36_running_reg(clk_36_running_reg),    //Needs to go to spi.v. This signal means that the internal 36MHz clock is running. It is delayed somewhat from the actual state machine.
    .clk_36_irq(clk_36_irq),                    //Needs to go to rfdir_fsm.v. This signal informs 
    .clk_27p5(clk_27p5),
    .clk_55(clk_55)
);

reset_mgmt    reset_mgmt0(
    //Inputs
    .rst_n_ext(rst_n_ext),                      //Active low reset from external pin
    .rst_4p5_sw(rst_4p5_sw),
    .clk_27p5(clk_27p5),
    .clk_55(clk_55),
    .clk_4p5(clk_4p5),
    .clk_36_in(clk_36_in),
    .clk_36(clk_36),
    //Outputs
    .rst_n_27p5(rst_n_27p5),
    .rst_n_55(rst_n_55),
    .rst_n_4p5(rst_n_4p5),
    .rst_n_36_in(rst_n_36_in),
    .rst_n_36(rst_n_36)
);

endmodule
