/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : Radio States Include File                                              //
//                                                                                 //
// Filename: radio_sram_with_mux.v                                                 //
// Creation Date: 1/13/2016                                                        //
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
//    This file keeps the radio states for the FPGA portion of the RFID reader     //
//    consistent throught the entire design by referencing this file in various    //
//    Verilog hardware blocks.                                                     //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

    localparam    STATE_DONE            =    5'd0;     //    The idle state - wait here for top level FSM to kick this off again
    localparam    STATE_RESET           =    5'd1;     //    An optional state designed to reset everything for the next run.
    localparam    STATE_TX_TXCW0        =    5'd2;     //     Transmit a CW signal to allow the TX cancellation to converge (low RX gain)
    localparam    STATE_TX_SELECT       =    5'd3;     //    Read the select packet from the appropriate location in SRAM and TX it.
    localparam    STATE_TX_SEL_2        =    5'd4;     //    Reserve memory for a second select operation. This is needed to assert SL and inventory tags on the same query.
    localparam    STATE_TX_QUERY        =    5'd5;     //    Read the query packet from the appropriate location in SRAM and TX it.
    localparam    STATE_RX_RN16_I       =    5'd6;     //     Obtain the first RN16 in the transaction.
    localparam    STATE_TX_QRY_REP      =    5'd7;     //    Perform a query rep in order to check number of tags or otherwise
    localparam    STATE_TX_ACK_RN16     =    5'd8;     //    Acknowledge the first RN16 packet with {2'b01,RN16}.
    localparam    STATE_TX_ACK_HDL      =    5'd9;     //    Transmit an ACK with a handle
    localparam    STATE_RX_PCEPC        =    5'd10;    //     Receive the PC+EPC+CRC from the tag and store it in designated SRAM location.
    localparam    STATE_TX_NAK_CNTE     =    5'd11;    //     TX a NAK in response to bad PCEPC received, but continue inventorying
    localparam    STATE_TX_NAK_EXIT     =    5'd12;    //    TX a NAK in response to an error in order to allow tags to power down OK
    localparam    STATE_TX_REQHDL       =    5'd13;    //    Make a special case for requesting the handle
    localparam    STATE_RX_HANDLE       =    5'd14;    //    Receive the handle from the tag and store it in designated reg/SRAM locations.
    localparam    STATE_TX_REQRN16      =    5'd15;    //    Transmit the REQRN, assembled from register contents
    localparam    STATE_RX_RN16         =    5'd16;    //     Receive a RN16 from the tag for purposes of sending a write or lock or from Query rep
    localparam    STATE_TX_WRITE        =    5'd17;    //    Transmit a write from its SRAM location
    localparam    STATE_RX_WRITE        =    5'd18;    //    Receive a write delayed response, store result in designated SRAM location
    localparam    STATE_TX_READ         =    5'd19;    //    Transmit a read request from designated TX SRAM location.
    localparam    STATE_RX_READ         =    5'd20;    //    Receive a read response - store in designated SRAM location.
    localparam    STATE_TX_LOCK         =    5'd21;    //    Transmit a lock request from designated TX SRAM location.
    localparam    STATE_RX_LOCK         =    5'd22;    //    Receive lock response - delayed response - store in designated SRAM location
    localparam    STATE_INV_HOLD        =    5'd23;    //    Hold inventory while we wait for the MCU to process the EPC results.
    localparam    STATE_INV_END         =    5'd24;    //    Delay state to return to DONE after inventory. This is required to properly step through the rfidr_fsm.v state machine.
    localparam    STATE_INV_END_2       =    5'd25;    //    Another delay state to return to DONE after inventory. As of 111317 can't figure out why this is needed, but it is.
    localparam    STATE_PRG_HOLD        =    5'd26;    //    Hold programming while we wait for the MCU to process a failure.
    localparam    STATE_TX_QRY_REP_B    =    5'd27;    //    Dummy state - return to DONE
    localparam    STATE_DUMMY_28        =    5'd28;    //    Dummy state - return to DONE
    localparam    STATE_DUMMY_29        =    5'd29;    //    Dummy state - return to DONE
    localparam    STATE_DUMMY_30        =    5'd30;    //    Dummy state - return to DONE
    localparam    STATE_DUMMY_31        =    5'd31;    //    Dummy state    - return to DONE