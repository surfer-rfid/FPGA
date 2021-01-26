/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : RFIDr Finite State Machine                                             //
//                                                                                 //
// Filename: rfidr_fsm.v                                                           //
// Creation Date: 1/10/2016                                                        //
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
//                                                                                 //
//    This finite state machine controls operation of the RFIDr top level.         //
// It accepts argument inputs from the SPI as part of a very limited               //
// memory mapping and is ultimately controlled by the top level SPI.               //
// Perhaps the control registers should be kept in a separate module??             //
//                                                                                 //
// This state machine operates from the 55MHz clock (div'd down to 13.75MHz)       //
// This is a really simple state machine since the FPGA handles initialization     //
// on its own, and there is to be no manual loading of SRAM data from FLASH.       //
//    There will be no waveform playback state, since SPI access of the waveform   //
// storage RAM is plenty fast (enough to unload in 1/28 of a second even           //
// without any special burst modes). All we have is an IDLE_STATE,                 //
// RADIO_RUNNING state, and a RADIO_DONE state.                                    //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module    rfidr_fsm
    (
        input        wire    radio_go_in,        //This needs to be a one-shot signal from the SPI control registers
        input        wire    radio_busy_in,      //This needs to be a level-based signal from the radio
        input        wire    radio_done_in,      //This needs to be a one-shot signal from the radio
        input        wire    irq_acked,          //This needs to be a one-shot signal from the SPI control registers
        input        wire    clk,
        input        wire    rst_n,
        
        output       reg     radio_go_out,
        output       reg     radio_running,      //This signal is required in order to disable SPI slave writes and SPI slave feedthrough
        output       reg     radio_done_out,
        output       reg     mcu_irq
    );
    
    //    Parameter and localparam definitions
        
    // State machine designations
    // We may need to move these to global parameters so that they don't get mismatched between modules.
    
    localparam    STATE_IDLE               =    2'd0;
    localparam    STATE_GO_ACK_WAIT        =    2'd1;
    localparam    STATE_RADIO_RUNNING      =    2'd2;
    localparam    STATE_RADIO_DONE         =    2'd3;            //Here, we await acknowledgement from the MCU that the radio done signal has been received.
    
    //Local register definitions
    
    reg    [1:0]    state, state_next;
    reg    radio_go_out_next;                //This signal needs to be flopped since it it going to 4.5MHz domain
    reg    radio_running_next;
    reg    radio_done_out_next;
    
    always @(*)    begin
    
        // Defaults
        
        radio_go_out_next       =    1'b0;
        radio_running_next      =    1'b0;
        radio_done_out_next     =    1'b0;
        state_next              =    state;
        mcu_irq                 =    1'b0;
    
        case(state)
            STATE_IDLE: begin
                if(radio_go_in)    begin
                    state_next            =    STATE_GO_ACK_WAIT;
                end
            end
            STATE_GO_ACK_WAIT: begin
                radio_go_out_next         =    1'b1;                    //This delay actually helps radio_go happen after radio_mode is set.
                if(radio_busy_in)    begin                              //More importantly, radio_go_out_next is a pulse that needs to be handshook. The busy signal handshakes this.
                    state_next            =    STATE_RADIO_RUNNING;
                end
            end
            STATE_RADIO_RUNNING: begin
                radio_running_next        =    1'b1;
                if(radio_done_in)
                    state_next            =    STATE_RADIO_DONE;
            end
            STATE_RADIO_DONE: begin
                radio_done_out_next       =    1'b1;
                mcu_irq                   =    1'b1;
                if(irq_acked)
                    state_next            =    STATE_IDLE;
            end
        endcase
    end
    
    always @(posedge clk or negedge rst_n)    begin
        if(!rst_n)    begin
            radio_go_out     <=    1'b0;
            radio_done_out   <=    1'b0;
            radio_running    <=    1'b0;
            state            <=    STATE_IDLE;
        end  else    begin
            radio_go_out     <=    radio_go_out_next;
            radio_done_out   <=    radio_done_out_next;
            radio_running    <=    radio_running_next;
            state            <=    state_next;
        end
    end
endmodule
