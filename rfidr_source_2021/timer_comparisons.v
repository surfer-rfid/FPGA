/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : RX Data Recovery Sym counter distance computer                         //
//                                                                                 //
// Filename: timer_comparisons.v                                                   //
// Creation Date: 12/17/2015                                                       //
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
// Perform timer comparisons for the data recovery block.                          //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module    timer_comparisons
    (
        // Inputs
        input    wire            is_delayed_reply,
        input    wire    [17:0]    wd_timer,
        input    wire    [8:0]    locked_timer,    
        // Outputs
        output    reg                wd_over_limit,
        output    wire            locked_limit_1,
        output    wire            locked_limit_2
    );

    //Thresholds
    
    //We need to set this to 20ms and change. The value below will hopefully minimize LUT.
    localparam    WD_TIMER_LIMIT_DELAYED_REPLY    =    18'd98304;
    //We need to set this to 305 sample (min turnaround time) plus (1/187500)*1.12*(16+6)*(4.5e6) = (1/BLF)*(TrF)*(Pilot+Preamble)*Clock rate, plus margin
    localparam    WD_TIMER_LIMIT_REGULAR_REPLY    =    18'd8192;
    localparam    LOCKED_TIMER_LIMIT_1            =    9'd192;
    localparam    LOCKED_TIMER_LIMIT_2            =    9'd384;
    
    assign     locked_limit_1                     =    locked_timer    ==    LOCKED_TIMER_LIMIT_1;
    assign    locked_limit_2                      =    locked_timer    >=    LOCKED_TIMER_LIMIT_2;
    
    always @(*)    begin
        if(is_delayed_reply)
            wd_over_limit                         =    wd_timer        >=    WD_TIMER_LIMIT_DELAYED_REPLY;
        else
            wd_over_limit                         =    wd_timer        >=    WD_TIMER_LIMIT_REGULAR_REPLY;
    end
    
endmodule
