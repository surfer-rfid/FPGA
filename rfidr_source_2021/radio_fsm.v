//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
// Module : Radio Finite State Machine                                              //
//                                                                                  //
// Filename: radio_fsm.v                                                            //
// Creation Date: 1/4/2016                                                          //
// Author: Edward Keehr                                                             //
//                                                                                  //
// Copyright Superlative Semiconductor LLC 2021                                     //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2      //
// You may redistribute and modify this documentation and make products             //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).         //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                 //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                     //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2               //
// for applicable conditions.                                                       //
//                                                                                  //
// Description:                                                                     //
//                                                                                  //
//    This finite state machine controls operation of the FPGA radio sub-blocks.    //
// It accepts argument inputs from the SPI as part of a very limited                //
// memory mapping and is ultimately controlled by the top level SPI.                //
// Perhaps the control registers should be kept in a separate module??              //
//                                                                                  //
// Since this state machine is only operational while the radio is operational      //
// , we run it from the 4.5MHz clock. We will probably be required to reset         //
// this circuitry once the SX1257 has been enabled.                                 //
//                                                                                  //
// 011116 - We still need to figure out how to specify which packet will            //
// trigger the waveform capture (I'm guessing we don't, and we trigger it on        //
// the first packet of a series.                                                    //
//                                                                                  //
//    Revisions:                                                                    //
//    082816 - Added break mechanism to break out of programming check query rep    //
//    loop when we have found 16 tags (or 15, it doesn't matter, more than 1 is     //
//    enough to be a problem).                                                      //
//                                                                                  //
//    092016 - Removed bad mode checks to save 48 much needed LUT. All these        //
//    things really checked for was a SEU. If we actually get one of these we will  //
//    need to rely on error handling in higher level software.                      //
//                                                                                  //
//    111016 - Add support for a legitimate inventory. This may require             //
//    dismantling MODE_PROG_CHK.                                                    //
//                                                                                  //
//    112616 - Fix inventory so that failed tag accesses report back to MCU.        //
//    With appropriate codes so that we know what is going on.                      //
//                                                                                  //
//    021518 - Add provisions for kill packet send pulse when a write is complete.  //
//                                                                                  //
//    120520 - Add provisions for more robust programming.                          //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

module    radio_fsm
    (
        // *** Note that wires marked with stars "***" must undergo clock domain crossings.
        // Output signals so denoted must be launched from flops, obviously
        // ??? denotes signals that we haven't determined whether we need them or not.
        
        // Inputs
        input    wire                go,                    // *** From top-level FSM
        input    wire                use_select_pkt,        // From spi prphrl, synced.
        input    wire                alt_radio_fsm_loop,    // From spi prphrl, synced.
        input    wire                end_radio_fsm_loop,    //    From spi_prphrl, synced.
        input    wire                kill_write_pkt,        //    Write packet is to be treated as a kill
        input    wire    [1:0]       mode,                  //    *** From memory-mapped registers interfacing with SPI
        input    wire                rx_done,               //    The RX has completed its reception, made valid its indicators, and stored its results in SRAM
        input    wire                rx_fail_crc,           //    The RX CRC reception has failed
        input    wire                rx_timeout,            //    The RX has timed out while waiting for a packet
        input    wire                rx_dlyd_err,           //    The RX has received an error in a delayed response packet (e.g. write)
        input    wire                rx_hndl_mmtch,         // The RX has received a packet with the wrong handle
        input    wire                rx_collision,          // The RX has detected a RN16 packet with a high probability of collision
        input    wire                tx_done,               // The TX has completed transmitting its packet
        input    wire                last_tx_write,         //    From TX_Gen - reading SRAM will tell when we are at the last word to be written
        input    wire                rst_n,                 //    4.5MHz domain reset signal.
        input    wire                clk,                   //    4.5MHz clock            
    
        // Outputs
        output    reg    [4:0]       state,                 // Tell DR / TX Gen which operation to do and which RX/TX address to place the data
        output    reg                txrxaccess,            //    Permits either TX or RX to access the shared variable packet data RAM
        output    reg                rx_block,              //    Block the RX from seeing crazy TX signal
        output    reg                rx_go,                 //    Kick off the RX DR state machine
        output    reg                tx_go,                 //    Kick off the TX Gen state machine
        output    reg                tx_en,                 //    ??? Enable SX1257 TX, TX PA ??? - Use this to enable TX Gen CW at least
        output    reg                wvfm_go,               // Kick off waveform recording at beginning of packet sequence
        output    reg                busy,                  //    *** Tell top-level FSM and memory-mapped register that radio is busy.
        output    reg    [1:0]       exit_code,             //    *** Pass (0) or fail (1)
        output    reg                kill_first_pkt,        //    Make sure DR uses immediate reply on first packet of a kill
        output    reg    [2:0]       write_cntr,            //  Count where we are going through write packets.
        output    reg                done                   //    *** Tell top-level FSM that the radio FSM is done
    );
    
    // Parameter and localparam definitions
    
    // State machine designations
    // We may need to move these to global parameters so that they don't get mismatched between modules.
    
    `include "./radio_states_include_file.v"

    localparam    EXIT_OK              =    2'd0;
    localparam    EXIT_ERROR           =    2'd1;
    
    localparam    TX_RAM_ACCESS        =    1'b0;        // These need to be global parameters
    localparam    RX_RAM_ACCESS        =    1'b1;
    
    localparam    MODE_SEARCH          =    2'd0;        //    Execute a search for a specific RFID tag. SW will set Q=0;
    localparam    MODE_INVENTORY       =    2'd1;        //    Do a real inventory with the help of the MCU and FW(Also check to see that there is only 1 tag within radio range of the reader).
    localparam    MODE_UNDEFINED       =    2'd2;        //    Currently, we have one mode open. This was for program confirm but we decided that mode wasn't needed.
    localparam    MODE_PROGRAM         =    2'd3;        //    Actually execute the programming
    
    // Wire-reg declarations
    
    reg    [4:0]   state_next;
    reg    [1:0]   exit_code_next;
    reg            busy_next;
    reg            done_next;
    //reg          reg_params;
    reg    [1:0]   mode_reg_next;
    reg            num_tags_clr;
    reg            txrxaccess_next;
    reg            kill_first_pkt_next;
    reg            write_cntr_clr;
    reg            write_cntr_incr;
    
    reg            rx_block_next;
    reg            rx_go_next;
    reg            tx_go_next;
    reg            tx_en_next;
    reg            wvfm_go_next;
    reg            txcw0_sstate_clr, txcw0_sstate_incr, txcw0_sstate;
    
    // Reg-reg declarations
    
    reg    [1:0]    mode_reg;      //    Update this when reg_params is set
    
    
    // Combinational logic for state machine
    
    always @(*) begin
    //    Defaults
        txrxaccess_next        =    txrxaccess;
        state_next             =    state;
        exit_code_next         =    exit_code;
        busy_next              =    busy;
        kill_first_pkt_next    =    kill_first_pkt;
        //done_next            =    done;
        done_next              =    1'b0;    //Pulse the done - otherwise causes problems for inventorying
        rx_block_next          =    1'b1;    //Block RX from seeing TX
        rx_go_next             =    1'b0;    //Don't kick off RX
        tx_go_next             =    1'b0;    //Don't kick off TX
        tx_en_next             =    1'b1; //In most states, we will keep TX on            
        //reg_params           =    1'b0;    //Lock parameters when moving out of the DONE state
        mode_reg_next          =    mode_reg;
        wvfm_go_next           =    1'b0;
        txcw0_sstate_clr       =    1'b0;
        txcw0_sstate_incr      =    1'b0;
        write_cntr_clr         =    1'b0;
        write_cntr_incr        =    1'b0;
        
        case(state)
            STATE_DONE: begin
            
                tx_en_next        =    1'b0;
                done_next        =    1'b0;
            
                if(go) begin
                    busy_next    =    1'b1;
                    state_next    =    STATE_RESET;
                    //reg_params    =    1'b1;
                    mode_reg_next        =    mode;    //Latch in the mode so that software can't change it later in the middle of the packet.
                    kill_first_pkt_next    =    kill_write_pkt;
                end
                    
            end    // end STATE_DONE
            
            STATE_RESET: begin
            
                //    Not sure what we really have to reset at the moment
                //num_tags_clr    =    1'b1;
                tx_en_next        =    1'b0;
                tx_go_next        =    1'b1;
                wvfm_go_next      =    1'b1;
                txcw0_sstate_clr  =    1'b1;
                write_cntr_clr    =    1'b1;
                state_next        =    STATE_TX_TXCW0;
                txrxaccess_next   =    TX_RAM_ACCESS;
                exit_code_next    =    EXIT_ERROR;        //If we don't exit good, we exit bad. Rely on this to relay error to MCU.
                
            end    // end STATE_RESET
            
            // TX_CW0 will take length argument (16b) from TX SRAM
            // We will let software load this
            // But what if RAM is all zero?
            // Maybe hard code a value is this really is the case
            
            STATE_TX_TXCW0: begin    
            
                if(tx_done && !txcw0_sstate) begin
                    tx_go_next           =    1'b1;
                    txcw0_sstate_incr    =    1'b1;
                    state_next           =    STATE_TX_TXCW0;
                    txrxaccess_next      =    TX_RAM_ACCESS;
                end else if (tx_done && txcw0_sstate) begin
                    tx_go_next           =    1'b1;
                    txrxaccess_next      =    TX_RAM_ACCESS;

                    if(use_select_pkt)
                        state_next       =    STATE_TX_SELECT;
                    else
                        state_next       =    STATE_TX_QUERY;
                end
            end    // end STATE_TX_TXCW0
                
            STATE_TX_SELECT: begin
                if(tx_done) begin
                    tx_go_next           =    1'b1;
                    txrxaccess_next      =    TX_RAM_ACCESS;
                    if(mode_reg    ==    MODE_SEARCH || mode_reg    == MODE_PROGRAM)
                        state_next       =    STATE_TX_QUERY;
                    else
                        state_next       =    STATE_TX_SEL_2;    //This is required because we need to issue selects on SL tag and inventory tag during inventory
                end
            end    // end STATE_TX_SELECT
            
            STATE_TX_SEL_2: begin
                if(tx_done) begin
                    tx_go_next            =    1'b1;
                    state_next            =    STATE_TX_QUERY;
                    txrxaccess_next       =    TX_RAM_ACCESS;
                end
            end    // end STATE_TX_SELECT
        
            STATE_TX_QUERY: begin
                if(tx_done) begin
                    rx_go_next            =    1'b1;
                    state_next            =    STATE_RX_RN16_I;
                    txrxaccess_next       =    RX_RAM_ACCESS;
                end
            end    // end STATE_TX_QUERY
            
            // This is where things get interesting, as we need to account for what happens when we don't receive a packet
            // Here, we worry about whether we see a collision or a timeout
            
            STATE_RX_RN16_I: begin
                rx_block_next                =    1'b0;
            
                if(rx_done) begin
                    if(rx_timeout) begin    //    If we don't hear anything, we should do a query rep unless we have set Q=0;
                        if(mode_reg    ==    MODE_SEARCH || mode_reg    == MODE_PROGRAM) begin    //If we are searching, we expected to get the RN16 back right away
                            tx_go_next         =    1'b1;
                            //exit_code_next   =    EXIT_ERROR;             //SW can examine RX RAM to figure out exact error mechanism. Rely on initial EXIT_ERROR as of 120520.
                            state_next         =    STATE_TX_NAK_EXIT;      //We didn't, so we need to flag an error
                            txrxaccess_next    =    TX_RAM_ACCESS;
                        end else begin //else if(mode_reg    ==    MODE_INVENTORY)            //Otherwise it is time to do a query rep
                            //No tx_go_next - just keep TX spitting out a CW while the MCU does its thing.
                            //exit_code_next   =    EXIT_ERROR;             //Tell the MCU we missed a packet. Rely on initial EXIT_ERROR as of 120520.
                            state_next         =    STATE_INV_HOLD;         //Wait for MCU to respond
                            busy_next          =    1'b0;                   //This code is vital to increment the query Q counter.
                            done_next          =    1'b1;                   //Pass control back to MCU
                        end
                    end else if(rx_collision) begin                         // If there has been a collision, don't ack it
                        tx_go_next         =    1'b1;
                        state_next         =    STATE_TX_QRY_REP;
                        txrxaccess_next    =    TX_RAM_ACCESS;
                    end else begin
                        tx_go_next         =    1'b1;
                        state_next         =    STATE_TX_ACK_RN16;
                        txrxaccess_next    =    TX_RAM_ACCESS;
                    end
                end
            end        // end STATE_RX_RN16_I
            
            STATE_TX_QRY_REP: begin
                if(tx_done) begin
                    rx_go_next        =    1'b1;
                    state_next        =    STATE_RX_RN16_I;                 //Query rep returns an initial RN16 which is treated as a handle
                    txrxaccess_next    =    RX_RAM_ACCESS;
                end
            end    // end STATE_TX_QRY_REP

            STATE_TX_QRY_REP_B: begin
                if(tx_done)    begin
                    //No tx_go_next - just keep TX spitting out a CW while the MCU does its thing.
                    //No RX go next - we will let a tag with counter = 0 burn itself here because we need to flip the inventory tag
                    //We assume that the offline processing done here far exceeds the time required to have the tag issue its RN16 and timeout
                    //Since we will not do rx_go, there is no need to suppress writes to RX_RAM in data_rcvy.v
                    state_next       =    STATE_INV_HOLD;    //Wait for MCU to respond
                    busy_next        =    1'b0;
                    done_next        =    1'b1;            //Pass control back to MCU
                end
            end
            
            STATE_TX_ACK_RN16: begin
                if(tx_done) begin
                    rx_go_next         =    1'b1;
                    state_next         =    STATE_RX_PCEPC;
                    txrxaccess_next    =    RX_RAM_ACCESS;
                end
            end    // end STATE_TX_ACK_RN16
            
            // For STATE_RX_PCEPC, it's worth wondering what do we do if we get a bad CRC?
            // Do we try again?
            //    Well, for ranging, we should kick it back to software for examination. Perhaps the result is still good.
            //    For modes in which we need to perform a full inventory round, we need to TX a NAK afterwards
            
            STATE_RX_PCEPC: begin
                rx_block_next            =    1'b0;
                
                if(rx_done)    begin //Potential errors include: timeout or bad crc 
                    if(rx_fail_crc || rx_timeout) begin
                        if(mode_reg    ==    MODE_SEARCH || mode_reg == MODE_PROGRAM) begin
                            tx_go_next         =    1'b1;
                            //exit_code_next    =    EXIT_ERROR; //Rely on initial EXIT_ERROR as of 120520.
                            state_next         =    STATE_TX_NAK_EXIT;
                            txrxaccess_next    =    TX_RAM_ACCESS;
                        end else begin //else if(mode_reg    ==    MODE_INVENTORY)            //    Here we are performing an inventory, sort of.
                                        // So we assume something screwed up with this tag or we got a collision.
                            tx_go_next         =    1'b1;                // We need to NAK to kick back all noninventoried tags to arbitrate
                            state_next         =    STATE_TX_NAK_CNTE;    //In principle we only need to do a query rep for a timeout (collision) but this saves logic (for now)
                            txrxaccess_next    =    TX_RAM_ACCESS;        //In principle we should also notify the MCU that we think a collision happened.
                        end
                    end else begin                    
                        if(mode_reg    ==    MODE_SEARCH) begin // We were only looking for magI and magQ
                            exit_code_next    =    EXIT_OK;
                            busy_next         =    1'b0;            //112616 - Do not NAK a good result, it results in tag flag not being flipped
                            done_next         =    1'b1;
                            state_next        =    STATE_DONE;
                        end else if(mode_reg    ==    MODE_INVENTORY)    begin          //Here we perform a real inventory
                            exit_code_next    =    EXIT_OK;                             //Yes, we got a good packet - have the MCU process it
                            //But wait - in order to flip the tag we need to issue a dummy query rep before going into offline processing
                            //This may 'burn' a tag, but we'll just have to issue more queries later to mop up tags lost this way
                            tx_go_next        =    1'b1;
                            state_next        =    STATE_TX_QRY_REP_B;
                            txrxaccess_next   =    TX_RAM_ACCESS;
                        end else begin //else if(mode_reg    ==    MODE_PROGRAM)        // We've found the tag we are looking to program
                            tx_go_next        =    1'b1;                                //    Now we need to get its handle
                            state_next        =    STATE_TX_REQHDL;
                            txrxaccess_next   =    TX_RAM_ACCESS;
                        end
                    end
                end
            end // end STATE_RX_PCEPC
            
            STATE_INV_HOLD: begin
                if(go && !alt_radio_fsm_loop && !end_radio_fsm_loop)    begin
                    exit_code_next     =    EXIT_ERROR; //In case we exited with EXIT_OK before, we need to set this back to the default.
                    tx_go_next         =    1'b1;
                    busy_next          =    1'b1;
                    state_next         =    STATE_TX_QRY_REP;
                    txrxaccess_next    =    TX_RAM_ACCESS;
                end else if (go && alt_radio_fsm_loop) begin
                    exit_code_next    =    EXIT_ERROR; //In case we exited with EXIT_OK before, we need to set this back to the default.
                    tx_go_next         =    1'b1;
                    busy_next          =    1'b1;
                    state_next         =    STATE_TX_QUERY;
                    txrxaccess_next    =    TX_RAM_ACCESS;
                end else if (go && !alt_radio_fsm_loop && end_radio_fsm_loop) begin
                    busy_next          =    1'b1;
                    state_next         =    STATE_INV_END;
                    txrxaccess_next    =    TX_RAM_ACCESS;
                    //Another problem here - done does not go low then high to force the irq
                    //Actually the IRQ will happen - see rfidr_fsm.v
                end
            end

            STATE_INV_END: begin                       //At least two of these states are required to transition rfidr_fsm.v state machine properly.
                state_next    =    STATE_INV_END_2;    //Still not sure why this is.
            end

            STATE_INV_END_2: begin
                busy_next    =    1'b0;
                done_next    =    1'b1;
                state_next   =    STATE_DONE;
            end
            
            STATE_TX_NAK_CNTE: begin

                if(tx_done)    begin
                    //No tx_go_next - just keep TX spitting out a CW while the MCU does its thing.
                    //exit_code_next    =    EXIT_ERROR;           //Tell MCU we got a bad packet. //Rely on initial EXIT_ERROR as of 120520.
                    state_next       =    STATE_INV_HOLD;          //Wait for MCU to respond
                    busy_next        =    1'b0;                    //This is important since we need to increment the query Q counter.
                    done_next        =    1'b1;                    //Pass control back to MCU
                end
            end    //    end STATE_TX_NAK_CNTE
        
            STATE_TX_NAK_EXIT: begin        
                if(tx_done) begin
                    busy_next    =    1'b0;
                    done_next    =    1'b1;
                    state_next   =    STATE_DONE;
                end
            end    //    end STATE_TX_NAK_EXIT
        
            STATE_TX_REQHDL: begin

                if(tx_done)    begin                               // The only things that can happen are timeout and bad crc here
                    rx_go_next         =    1'b1;
                    state_next         =    STATE_RX_HANDLE;
                    txrxaccess_next    =    RX_RAM_ACCESS;
                end
            end    //    end STATE_TX_REQHDL
        
            STATE_RX_HANDLE: begin        
                    
                rx_block_next    =    1'b0;
                        
                if(rx_done) begin
                    if(rx_fail_crc || rx_timeout) begin
                        tx_go_next         =    1'b1;
                        //exit_code_next   =    EXIT_ERROR; //Rely on initial EXIT_ERROR as of 120520.
                        state_next         =    STATE_TX_NAK_EXIT;
                        txrxaccess_next    =    TX_RAM_ACCESS;
                    end else begin
                        tx_go_next         =    1'b1;
                        state_next         =    STATE_TX_REQRN16;
                        txrxaccess_next    =    TX_RAM_ACCESS;
                    end
                end
            end    //    end STATE_RX_HANDLE
        
            STATE_PRG_HOLD: begin
                if(go && !end_radio_fsm_loop)    begin //Assume we only got here due to an error, so no need to get exit_code to EXIT_ERROR again.
                    tx_go_next             =    1'b1;
                    busy_next              =    1'b1;
                    state_next             =    STATE_TX_REQRN16;
                    txrxaccess_next = TX_RAM_ACCESS;
                end else if (go && end_radio_fsm_loop) begin
                    tx_go_next             =    1'b1;
                    busy_next              =    1'b1;
                    state_next             =    STATE_TX_NAK_EXIT;
                    txrxaccess_next        =    TX_RAM_ACCESS;
                end
            end
        
            STATE_TX_REQRN16: begin    

                if(tx_done)    begin
                    rx_go_next             =    1'b1;
                    state_next             =    STATE_RX_RN16;
                    txrxaccess_next        =    RX_RAM_ACCESS;
                end
            end    //    end STATE_TX_REQRN16
                
            STATE_RX_RN16: begin        
                    
                rx_block_next    =    1'b0;
                        
                if(rx_done) begin
                    if(rx_fail_crc || rx_timeout) begin
                        //exit_code_next   =    EXIT_ERROR;           //Tell MCU we got a bad packet. //Rely on initial EXIT_ERROR as of 120520.
                        state_next         =    STATE_PRG_HOLD;         //Wait for MCU to respond
                        busy_next          =    1'b0;                    //Tell higher level FSM we are not longer busy.
                        done_next          =    1'b1;                    //Pass control back to MCU
                    end else begin
                        tx_go_next         =    1'b1;
                        state_next         =    STATE_TX_WRITE;
                        txrxaccess_next    =    TX_RAM_ACCESS;
                    end
                end
            end    //    end STATE_RX_RN16
                    
            STATE_TX_WRITE: begin

                if(tx_done) begin
                    rx_go_next             =    1'b1;
                    state_next             =    STATE_RX_WRITE;
                    txrxaccess_next        =    RX_RAM_ACCESS;
                end
            end    //    end STATE_TX_WRITE
        
            STATE_RX_WRITE: begin
                        
                rx_block_next              =    1'b0;
                        
                if(rx_done)    begin//Potential errors are: timeout, crc, delayed reply error, mismatched handle
                                    //Do they need to be handled differently? I don't think so - for now at least.
                    
                    if(rx_fail_crc || rx_timeout || rx_dlyd_err || rx_hndl_mmtch) begin
                        //exit_code_next  =    EXIT_ERROR;                //Tell MCU we got a bad packet. //Rely on initial EXIT_ERROR as of 120520.
                        state_next        =    STATE_PRG_HOLD;            //Wait for MCU to respond
                        busy_next         =    1'b0;                    //Tell higher level FSM we are not longer busy.
                        done_next         =    1'b1;                    //Pass control back to MCU
                    end else begin
                        if(last_tx_write && !kill_write_pkt) begin
                            tx_go_next             =    1'b1;
                            state_next             =    STATE_TX_READ;
                            txrxaccess_next        =    TX_RAM_ACCESS;
                        end else if(last_tx_write && kill_write_pkt) begin
                            tx_go_next             =    1'b1;
                            exit_code_next         =    EXIT_OK;
                            state_next             =    STATE_TX_NAK_EXIT;
                            txrxaccess_next        =    TX_RAM_ACCESS;
                        end else begin
                            kill_first_pkt_next    =    1'b0;    //We just did a successful write - now permit delayed packets.
                            tx_go_next             =    1'b1;
                            write_cntr_incr        =    1'b1;
                            state_next             =    STATE_TX_REQRN16;
                            txrxaccess_next        =    TX_RAM_ACCESS;
                        end
                    end
                end
            end // end STATE_RX_WRITE
                                        
            STATE_TX_READ: begin

                if(tx_done) begin
                    rx_go_next         =    1'b1;
                    state_next         =    STATE_RX_READ;
                    txrxaccess_next    =    RX_RAM_ACCESS;
                end
            end    //    end STATE_TX_READ
                                
            STATE_RX_READ: begin
                    
                rx_block_next    =    1'b0;
                    
                if(rx_done)    begin //Potential errors are: timeout, crc, delayed reply error, mismatched handle
                                    //Do they need to be handled differently? I don't think so - for now at least.
                    if(rx_fail_crc || rx_timeout || rx_hndl_mmtch) begin
                        //exit_code_next    =    EXIT_ERROR;                //Tell MCU we got a bad packet. //Rely on initial EXIT_ERROR as of 120520.
                        state_next         =    STATE_PRG_HOLD;            //Wait for MCU to respond
                        busy_next          =    1'b0;                    //Tell higher level FSM we are not longer busy.
                        done_next          =    1'b1;                    //Pass control back to MCU
                    end else begin
                        tx_go_next         =    1'b1;
                        state_next         =    STATE_TX_LOCK;
                        txrxaccess_next    =    TX_RAM_ACCESS;
                    end
                end
            end // end STATE_RX_READ
                                
            STATE_TX_LOCK: begin

                if(tx_done) begin
                    rx_go_next             =    1'b1;
                    state_next             =    STATE_RX_LOCK;
                    txrxaccess_next        =    RX_RAM_ACCESS;
                end
            end    //    end STATE_TX_LOCK
        
            STATE_RX_LOCK: begin
                    
                rx_block_next    =    1'b0;
                    
                if(rx_done)    begin //Potential errors are: timeout, crc, delayed reply error, mismatched handle
                                    //Do they need to be handled differently? I don't think so - for now at least.
                    if(rx_fail_crc || rx_timeout || rx_dlyd_err || rx_hndl_mmtch) begin
                        //exit_code_next    =    EXIT_ERROR;                //Tell MCU we got a bad packet. //Rely on initial EXIT_ERROR as of 120520.
                        state_next        =    STATE_PRG_HOLD;            //Wait for MCU to respond
                        busy_next         =    1'b0;                    //Tell higher level FSM we are not longer busy.
                        done_next         =    1'b1;                    //Pass control back to MCU
                    end else begin
                        tx_go_next        =    1'b1;
                        exit_code_next    =    EXIT_OK;
                        state_next        =    STATE_TX_NAK_EXIT;
                        txrxaccess_next   =    TX_RAM_ACCESS;
                    end
                end
            end // end STATE_RX_LOCK
            
            STATE_TX_ACK_HDL: begin
                busy_next     =    1'b0;
                done_next     =    1'b1;
                state_next    =    STATE_DONE;
            end
        
            STATE_DUMMY_28: begin
                busy_next     =    1'b0;
                done_next     =    1'b1;
                state_next    =    STATE_DONE;
            end
        
            STATE_DUMMY_29: begin
                busy_next     =    1'b0;
                done_next     =    1'b1;
                state_next    =    STATE_DONE;
            end
        
            STATE_DUMMY_30: begin
                busy_next     =    1'b0;
                done_next     =    1'b1;
                state_next    =    STATE_DONE;
            end

            STATE_DUMMY_31: begin
                busy_next     =    1'b0;
                done_next     =    1'b1;
                state_next    =    STATE_DONE;
            end
            
            default: begin
                busy_next     =    1'b0;
                done_next     =    1'b1;
                state_next    =    STATE_DONE;
            end
            
        endcase
    end
    
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mode_reg            <=    MODE_SEARCH;
            busy                <=    1'b0;
            exit_code           <=    EXIT_ERROR;
            done                <=    1'b0;
            state               <=    STATE_DONE;
            txrxaccess          <=    TX_RAM_ACCESS;
            rx_block            <=    1'b1;
            rx_go               <=    1'b0;
            tx_go               <=    1'b0;
            tx_en               <=    1'b0;
            wvfm_go             <=    1'b0;
            txcw0_sstate        <=    1'b0;
            kill_first_pkt      <=    1'b0;
            write_cntr          <=    3'b0;
        end else begin

            if(txcw0_sstate_clr) begin
                txcw0_sstate    <=    1'b0;
            end else if(txcw0_sstate_incr) begin
                txcw0_sstate    <=    1'b1;
            end
            
            if(write_cntr_clr)
                write_cntr    <=    3'b0;
            else if(write_cntr_incr)
                write_cntr    <=    write_cntr+3'b1;
            
            mode_reg            <=    mode_reg_next;        
            txrxaccess          <=    txrxaccess_next;
            busy                <=    busy_next;
            exit_code           <=    exit_code_next;
            done                <=    done_next;
            state               <=    state_next;
            rx_block            <=    rx_block_next;
            rx_go               <=    rx_go_next;
            tx_go               <=    tx_go_next;
            tx_en               <=    tx_en_next;
            wvfm_go             <=    wvfm_go_next;
            kill_first_pkt      <=    kill_first_pkt_next;
        end
    end
endmodule
