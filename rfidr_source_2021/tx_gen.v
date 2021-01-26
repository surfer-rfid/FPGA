//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
// Module : TX Generation                                                           //
//                                                                                  //
// Filename: tx_gen.v                                                               //
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
//    This module generates the TX waveform at 4.5MHz to be sent to the SDM         //
// based on the inputs from:                                                        //
//                                                                                  //
//    1. Radio FSM                                                                  //
//    2. Current RN16 register                                                      //
// 3. Current Handle register                                                       //
// 4. TX SRAM                                                                       //
//                                                                                  //
// Currently, the RAM format to be expected is:                                     //
//                                                                                  //
// 1. The 9th bit denotes a special TX character, such as RTCal, etc.               //
//    Said special characters are enumerated in this file. The reason for           //
// doing this is to reduce LUT usage in this block while still preventing           //
// software from doing anything that would be a problem from a regulatory           //
// perspective.                                                                     //
// It may be that this architectural choice does not reduce LUT usage enough        //
// to outweigh the risk of problematic software.                                    //
//                                                                                  //
// 2. Special TX characters include                                                 //
//        - start a segment of N bits (next byte denotes N)                         //
//        - insert running CRC16                                                    //
//        - insert current RN16                                                     //
//        - insert current handle                                                   //
//        - XOR next two bytes with current RN16                                    //
//        - end packet                                                              //
//        - TXCw0                                                                   //
//        - TXCW1 / begin Select                                                    //
//        - Begin Query (includes CW spacing)                                       //
//        - RTCal                                                                   //
//        - TRCal                                                                   //
//        - Last TX Write                                                           //
//                                                                                  //
//    By default, when tx_en is asserted, this block will output a '1',             //
//    indicating to transmit CW. Information from special characters will           //
//    result in '0' being asserted.                                                 //
//                                                                                  //
//    We need to handle errors that arise due to invalid programming sequence.      //
//    The current strategy to deal with this is to set the "error" output           //
//    register and set a trap for the outer state machine in the DONE state.        //
//    The MCU firmware should detect the error via IRQ and issue a global reset.    //
//    Update 122620 - We need to disabled this. Firmware needs to be written right. //
//                                                                                  //
//                                                                                  //
//    Revisions:                                                                    //
//                                                                                  //
//    022216 - Porting to Lattice ice40 Ultra. The problem here is that the RAM     //
//    does not have a 9th bit. Therefore, all codes are "special". Bytes that       //
//    follow codes START_BITSEG and XOR_NEXT_16B will need to be treated as bits    //
//    to be played out of the RAM. We will need to develop a mechanism that         //
//    carefully counts the number of non-special bytes before reverting back to     //
//    treating read bytes as 'special'.                                             //
//                                                                                  //
//    033016 - Flattening state hierarchy. Making individual bits as special        //
//    nibble codes.                                                                 //
//                                                                                  //
//    082416 - Treat REQRN16 and REGHDL differently. Same with ACK_RN16 and         //
//    ACK_HDL.                                                                      //
//                                                                                  //
//    082616 - Realized that our write routine was messed up. We actually need a    //
//    counter to increment memory offsets throughout the write offset memory space  //
//    between each write operation. This counter would be reset whenever the        //
//    LAST_WRITE command was seen. This is needed because we will be doing up to    //
//    8 writes but the writes are interspersed with other TX and RX commands as     //
//    dictated by the state machine. Also, the counter needs to be here, not the    //
//    state machine, since the state machine doesn't know when the writes end       //
//    (only the RAM knows that).                                                    //
//                                                                                  //
//    091416 - Added an interspace time to be read at the end of a NAK so that      //
//    there is no short blip at the end of a NAK when the radio_fsm shuts the       //
//    radio down.                                                                   //
//                                                                                  //
//    120520 - Moved write state counter from this module to radio_fsm.v. Also      //
//    moved write state control to radio_fsm.v. This is to improve on error         //
//    handling during programming.                                                  //
//                                                                                  //
//    122620 - Remove error handling associated with a wrong opcode after an        //
//    XOR_NEXT_16B. In this case the wrong opcode will be inserted and an illegal   //
//    packet will be made. There are other ways to make illegal packets and we will //
//    require the developer to self-enforce proper packet construction on the       //
//    MCU/firmware side of the design as opposed to within valuable FPGA resources  //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

module tx_gen
    (
        // Inputs
        input        wire    [7:0]       sram_in_data,
        input        wire                current_rn16,
        input        wire                current_handle,
        input        wire    [4:0]       radio_state,
        input        wire                go,
        input        wire                en,
        input        wire                clk,
        input        wire                rst_n,
        input        wire                dtc_test_mode,
        input        wire    [2:0]       write_cntr, //Registered at radio_fsm.v
        // Outputs
        output        reg                shift_rn16_bits,
        output        reg                shift_handle_bits,
        output        reg    [8:0]       sram_address,
        output        reg                out,
        output        reg                done,
        output        reg                last_write,
        output        reg                error_outer
    );

    //    Parameter and localparam definitions
    
    // Radio FSM state designations. These will need to be moved to some other file
    // to avoid mismatch between localparam defintions in different modules
    
    `include "./radio_states_include_file.v"

    // State machine state designations
    
    localparam    OUTER_STATE_DONE          =    3'd0;
    localparam    OUTER_STATE               =    3'd1;
    localparam    MIDDLE_STATE_BUF          =    3'd2;
    localparam    INNER_STATE_HI            =    3'd3;
    localparam    INNER_STATE_LO            =    3'd4;
    
    // 4.5 MHz periods for low signaling intervals
    
    localparam    LO_COUNT_REGULAR          =    6'd42;        //As per UHF RFID Specification
    localparam    LO_COUNT_DELIMITER        =    6'd56;        //As per UHF RFID Specification
    localparam    LO_COUNT_CW0              =    6'd0;         //As per UHF RFID Specification

    // 4.5 MHz periods for high signaling intervals
    
    localparam    HI_COUNT_ZERO             =    13'd54;       //As per UHF RFID Specification
    localparam    HI_COUNT_ONE              =    13'd126;      //As per UHF RFID Specification
    localparam    HI_COUNT_RTCAL            =    13'd222;      //As per UHF RFID Specification
    localparam    HI_COUNT_TRCAL            =    13'd468;      //As per UHF RFID Specification
    localparam    HI_COUNT_CW0              =    13'd8190;
    localparam    HI_COUNT_BEGIN_SELECT     =    13'd8190;
    localparam    HI_COUNT_BEGIN_REGULAR    =    13'd576;      //Standard minimum interpacket spacing 
    // We always use NAK to end transactions. To avoid blip at end of transaction, just finish with a dedicated high time of 576
        
    // Special codes for packet formatting
    
    localparam    PRIM_CODE_TXCW0           =    4'd0;
    localparam    PRIM_CODE_BEGIN_SELECT    =    4'd1;
    localparam    PRIM_CODE_BEGIN_REGULAR   =    4'd2;
    localparam    PRIM_CODE_DUMMY_ZERO      =    4'd3;
    localparam    PRIM_CODE_SINGLE_ZERO     =    4'd4;
    localparam    PRIM_CODE_SINGLE_ONE      =    4'd5;
    localparam    PRIM_CODE_RTCAL           =    4'd6;
    localparam    PRIM_CODE_TRCAL           =    4'd7;
    localparam    PRIM_CODE_NAK_END         =    4'd8;
    localparam    PRIM_CODE_XOR_NEXT_16B    =    4'd9;
    localparam    PRIM_CODE_INSERT_CRC16    =    4'd10;
    localparam    PRIM_CODE_INSERT_RN16     =    4'd11;
    localparam    PRIM_CODE_INSERT_HANDLE   =    4'd12;
    localparam    PRIM_CODE_LAST_WRITE      =    4'd13;
    localparam    PRIM_CODE_END_PACKET      =    4'd14;
    localparam    PRIM_CODE_BEGIN_IMMED     =    4'd15;
    
    // Secondary packet format codes
    
    localparam    SEC_CODE_NONE             =    2'd0;
    localparam    SEC_CODE_CRC16            =    2'd1;
    localparam    SEC_CODE_RN16             =    2'd2;
    localparam    SEC_CODE_HANDLE           =    2'd3;

    // TX SRAM Address Offsets for data deposited by microcontroller via SPI
    
    localparam    TX_RAM_ADDR_OFFSET_TXCW0      =    5'd0;    //These offsets are in number of 16-address (16-byte) chunks
    localparam    TX_RAM_ADDR_OFFSET_QUERY      =    5'd1;
    localparam    TX_RAM_ADDR_OFFSET_QRY_REP    =    5'd2;
    localparam    TX_RAM_ADDR_OFFSET_ACK_RN16   =    5'd3;
    localparam    TX_RAM_ADDR_OFFSET_ACK_HDL    =    5'd4;
    localparam    TX_RAM_ADDR_OFFSET_NAK        =    5'd5;
    localparam    TX_RAM_ADDR_OFFSET_REQHDL     =    5'd6;
    localparam    TX_RAM_ADDR_OFFSET_REQRN16    =    5'd7;
    localparam    TX_RAM_ADDR_OFFSET_LOCK       =    5'd8;
    localparam    TX_RAM_ADDR_OFFSET_READ       =    5'd10;
    localparam    TX_RAM_ADDR_OFFSET_WRITE0     =    5'd13;    //We allot 24 bytes per write. It takes 6 writes to write a 96b EPC. We allot 6 writes in memory, requiring 144 bytes
    //Our write address counter will be 3 bits, so it will roll around once it gets to the last valid write RAM slot.
    localparam    TX_RAM_ADDR_OFFSET_SELECT     =    5'd22;     // There are 160 bytes left. We may use up to 73 bytes per select command if we use a 16b EBV and 96b condition field. 
    localparam    TX_RAM_ADDR_OFFSET_SEL_2      =    5'd27;    //Therefore, we must allot 80 addresses under this current addresing scheme.
    
    // Wires

    wire    [15:0]       rn16_bits_out;
    wire                 next_rn16_bit;
    wire    [15:0]       handle_bits_out;
    wire                 next_handle_bit;
    wire                 crc_out_bit;
    wire                 out_next;
    
    // Wire-like reg's

    reg                  init_crc;
    reg                  calc_crc;
    reg                  bit_val, bit_val_next;
    reg                  sram_flag, sram_flag_next;
    reg                  xor_flag, xor_flag_next;
    reg                  shift_crc_bits;
    //reg                sram_address_load;
    //reg                sram_address_incr;
    reg                  xor_bit_cntr_clr;
    reg                  xor_bit_cntr_incr;
    reg                  shift_bit_cntr_clr;
    reg                  shift_bit_cntr_incr;
    reg        [3:0]     sram_mux;
    
    // Flop reg's
    
    reg                  hi;
    reg        [12:0]    hi_cntr_thresh;
    reg        [12:0]    hi_cntr_load_val, hi_cntr;
    reg        [5:0]     lo_cntr_load_val, lo_cntr;
    reg                  hi_cntr_decr, lo_cntr_decr;
    reg                  hi_cntr_load, lo_cntr_load;
    reg        [3:0]     shift_bit_cntr;
    reg        [3:0]     xor_bit_cntr;
    reg        [3:0]     write_cntr_offset;
    reg        [2:0]     state_next, state;
    reg        [1:0]     secondary_code_next, secondary_code;
    //reg        [8:0]   sram_address_decode;
    reg        [8:0]     sram_address_reg;    //On 090316
    reg                  done_next;
    reg                  last_write_next;
        
    
    // Modules
    
    crc_ccitt16_tx    crc_tx(
        .bit_in(bit_val_next),
        .shift(shift_crc_bits),
        .clk(clk),
        .rst_n(rst_n),
        .initialize(init_crc),
        .calculate(calc_crc),
        
        .crc_out(crc_out_bit)
    );
    
    // Merge old rn16/handle interface with new one on 6/26
    
    assign    next_rn16_bit      =    current_rn16;
    assign    next_handle_bit    =    current_handle;
    
    // Combinational assignments
    
    assign    out_next           =    (en && hi) || dtc_test_mode;
    
    // Decode mode into SRAM address
    // One question, however, is how to derive the proper write address
    // The Radio FSM is depending on *this* (tx_gen) module to tell when the writing is all done
    
    //always @(*)    begin
        
    //Default
            
    //    sram_address_decode        =    TX_RAM_ADDR_OFFSET_TXCW0     << 4;
        
    //    case(radio_state)

    //        STATE_TX_TXCW0:         begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_TXCW0       <<    4;    end
    //        STATE_TX_SELECT:        begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_SELECT      <<    4;    end
    //        STATE_TX_SEL_2:         begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_SEL_2       <<    4;    end
    //        STATE_TX_QUERY:         begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_QUERY       <<    4;    end
    //        STATE_TX_QRY_REP:       begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_QRY_REP     <<    4;    end
    //        STATE_TX_ACK_RN16:      begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_ACK_RN16    <<    4;    end
    //        STATE_TX_ACK_HDL:       begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_ACK_HDL     <<    4;    end
    //        STATE_TX_NAK_CNTE:      begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_NAK         <<    4;    end
    //        STATE_TX_NAK_EXIT:      begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_NAK         <<    4;    end
    //        STATE_TX_REQHDL:        begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_REQHDL      <<    4;    end
    //        STATE_TX_REQRN16:       begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_REQRN16     <<    4;    end
    //        STATE_TX_WRITE:         begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_WRITE0+{1'b0,write_cntr,1'b0}    <<    4;     end
    //        STATE_TX_READ:          begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_READ        <<    4;    end
    //        STATE_TX_LOCK:          begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_LOCK        <<    4;    end
    //        default:                begin    sram_address_decode    =    TX_RAM_ADDR_OFFSET_TXCW0       <<    4;    end    //This covers all of the RX states
            
    //    endcase
    //end
    
    always @(*)    begin
        state_next              =    state;
        last_write_next         =    last_write;
        init_crc                =    1'b0;
        done_next               =    1'b0;
        secondary_code_next     =    secondary_code;
        
        calc_crc                =    1'b0;
        shift_bit_cntr_clr      =    1'b0;
        shift_bit_cntr_incr     =    1'b0;
        xor_bit_cntr_clr        =    1'b0;
        xor_bit_cntr_incr       =    1'b0;
        bit_val_next            =    bit_val;
        shift_crc_bits          =    1'b0;
        shift_rn16_bits         =    1'b0;
        shift_handle_bits       =    1'b0;
        hi_cntr_thresh          =    13'd1;
        
        hi_cntr_load_val        =    HI_COUNT_CW0;
        lo_cntr_load_val        =    LO_COUNT_CW0;
        hi_cntr_load            =    1'b0;
        lo_cntr_load            =    1'b0;
        hi_cntr_decr            =    1'b0;
        lo_cntr_decr            =    1'b0;
        hi                      =    1'b1;
        
        sram_flag_next          =    sram_flag;
        xor_flag_next           =    xor_flag;
        
        sram_address            =    sram_address_reg;    //Added 090316
        sram_mux                =    sram_flag ? sram_in_data[7:4] : sram_in_data[3:0];
        
        //sram_address_load     =    1'b0;
        //sram_address_incr     =    1'b0;
        
        case(write_cntr)
            3'd0       :    begin    write_cntr_offset    =    4'b0000;    end
            3'd1       :    begin    write_cntr_offset    =    4'b0011;    end
            3'd2       :    begin    write_cntr_offset    =    4'b0110;    end
            3'd3       :    begin    write_cntr_offset    =    4'b1001;    end
            3'd4       :    begin    write_cntr_offset    =    4'b1100;    end
            3'd5       :    begin    write_cntr_offset    =    4'b1111;    end
            default    :    begin    write_cntr_offset    =    4'b0000;    end
        endcase    
        
        case(state)
            
            OUTER_STATE_DONE: begin
                
                if(go)    begin
                    sram_flag_next          =    1'b0;
                    last_write_next         =    1'b0;
                    state_next              =    OUTER_STATE;
                    //sram_address_load     =     1'b1;
                    init_crc                =    1'b1;
                    secondary_code_next     =    SEC_CODE_NONE;
                    xor_bit_cntr_clr        =    1'b1;

//Original position of this on 091916                    
//                    case(write_cntr)
//                        3'd0    :    begin    write_cntr_offset    =    4'b0000;    end
//                        3'd1    :    begin    write_cntr_offset    =    4'b0011;    end
//                        3'd2    :    begin    write_cntr_offset    =    4'b0110;    end
//                        3'd3    :    begin    write_cntr_offset    =    4'b1001;    end
//                        3'd4    :    begin    write_cntr_offset    =    4'b1100;    end
//                        3'd5    :    begin    write_cntr_offset    =    4'b1111;    end
//                        default    :    begin    write_cntr_offset    =    4'b0000;    end
//                    endcase    
                    
                    case(radio_state)
                        STATE_TX_TXCW0:         begin    sram_address    =    TX_RAM_ADDR_OFFSET_TXCW0       <<     4;    end
                        STATE_TX_SELECT:        begin    sram_address    =    TX_RAM_ADDR_OFFSET_SELECT      <<     4;    end
                        STATE_TX_SEL_2:         begin    sram_address    =    TX_RAM_ADDR_OFFSET_SEL_2       <<     4;    end
                        STATE_TX_QUERY:         begin    sram_address    =    TX_RAM_ADDR_OFFSET_QUERY       <<     4;    end
                        STATE_TX_QRY_REP:       begin    sram_address    =    TX_RAM_ADDR_OFFSET_QRY_REP     <<     4;    end
                        STATE_TX_QRY_REP_B:     begin    sram_address    =    TX_RAM_ADDR_OFFSET_QRY_REP     <<     4;    end
                        //111317 - B is for Burn - we need to burn a query rep to flip the tag before offline processing
                        STATE_TX_ACK_RN16:      begin    sram_address    =    TX_RAM_ADDR_OFFSET_ACK_RN16    <<    4;     end
                        STATE_TX_ACK_HDL:       begin    sram_address    =    TX_RAM_ADDR_OFFSET_ACK_HDL     <<    4;     end
                        STATE_TX_NAK_CNTE:      begin    sram_address    =    TX_RAM_ADDR_OFFSET_NAK         <<    4;     end
                        STATE_TX_NAK_EXIT:      begin    sram_address    =    TX_RAM_ADDR_OFFSET_NAK         <<    4;     end
                        STATE_TX_REQHDL:        begin    sram_address    =    TX_RAM_ADDR_OFFSET_REQHDL      <<    4;     end
                        STATE_TX_REQRN16:       begin    sram_address    =    TX_RAM_ADDR_OFFSET_REQRN16     <<    4;     end
                        STATE_TX_WRITE:         begin    sram_address    =    (TX_RAM_ADDR_OFFSET_WRITE0     <<    4) + {2'b00,write_cntr_offset,3'b000};     end
                        STATE_TX_READ:          begin    sram_address    =    TX_RAM_ADDR_OFFSET_READ        <<    4;     end
                        STATE_TX_LOCK:          begin    sram_address    =    TX_RAM_ADDR_OFFSET_LOCK        <<    4;     end
                        default:                begin    sram_address    =    TX_RAM_ADDR_OFFSET_TXCW0       <<     4;    end    //This covers all of the RX states
                    endcase
                end
            end
            
            OUTER_STATE: begin
                    
                //Check to make sure that the bit counter has been depleted - 
                //If the bit counter is active while a special code packet it seen,
                //It means that there has been a programming error
                        
                //Also, make sure that if we are coming in from OUTER_STATE_DONE with the initialize flag high,
                //that only one of 3 special codes can be used (and no nonspecial codes can be used)
                //TXCW0, BEGIN_SELECT, BEGIN_REGULAR. Anything else should flag a programming error.
                
                shift_bit_cntr_clr        =    1'b1;
                
                if(sram_flag == 1'b0) begin
                    sram_flag_next        =    1'b1;
                end else begin
                    //sram_address_incr    =    1'b1;
                    sram_address          =    sram_address_reg+9'b1;
                    sram_flag_next        =    1'b0;
                end
                
                if(xor_flag) begin
                    if(xor_bit_cntr    ==    4'd15) begin      //This means we have had 15 bits xored so far. xor_flag will be active to determine xoring in outer state but will be done after that.
                        xor_flag_next        =    1'b0;
                        xor_bit_cntr_clr     =    1'b1;
                    end else
                        xor_bit_cntr_incr    =    1'b1;        //This will be a '1' on the next cycle
                end
                
                case(sram_mux)
                    
                    PRIM_CODE_TXCW0: begin
                            
                    //In an ideal world, we don't use flags
                    //However, to repeat basically the same state setup
                    //for the initialize state would add a lot of code which risks
                    //conflicting with the rest of the code.
                                
                    //What we want to have happen is that this state gets entered and then we wait for the
                    //inner state machine to finish
                                
                        hi_cntr_load_val        =    HI_COUNT_CW0;
                        lo_cntr_load_val        =    LO_COUNT_CW0;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;        //We don't wait for inner FSM to be done
                    end
                    
                    PRIM_CODE_NAK_END: begin
                            
                        //This code gives a guaranteed high time after we use a NAK at any time, but especially for shutting down transmissions so we don't get a short high blip.
                                
                        hi_cntr_load_val        =    HI_COUNT_BEGIN_REGULAR;
                        lo_cntr_load_val        =    LO_COUNT_CW0;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;                    //is that we don't wait for inner FSM to be done
                    end
                            
                    PRIM_CODE_BEGIN_SELECT: begin
                        hi_cntr_load_val        =    HI_COUNT_BEGIN_SELECT;
                        lo_cntr_load_val        =    LO_COUNT_DELIMITER;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;                    //is that we don't wait for inner FSM to be done
                    end
                            
                    PRIM_CODE_BEGIN_REGULAR: begin
                        hi_cntr_load_val        =    HI_COUNT_BEGIN_REGULAR;
                        lo_cntr_load_val        =    LO_COUNT_DELIMITER;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;
                    end
                    
                    PRIM_CODE_BEGIN_IMMED: begin
                        hi_cntr_load_val        =    HI_COUNT_RTCAL;
                        lo_cntr_load_val        =    LO_COUNT_DELIMITER;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;
                    end
                    
                    PRIM_CODE_DUMMY_ZERO: begin                                //Needed for signaling zero that doesn't count towards CRC
                        hi_cntr_load_val        =    HI_COUNT_ZERO;
                        lo_cntr_load_val        =    LO_COUNT_REGULAR;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;
                    end
                    
                    PRIM_CODE_SINGLE_ZERO: begin
                        calc_crc                =    1'b1;
                        state_next              =    INNER_STATE_HI;
                        secondary_code_next     =    SEC_CODE_NONE;
                        lo_cntr_load_val        =    LO_COUNT_REGULAR;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        
                        if(xor_flag)    begin
                            bit_val_next        =    1'b0 ^ next_rn16_bit;
                            shift_rn16_bits     =    1'b1;
                            if(bit_val_next == 1'b1)
                                hi_cntr_load_val    =    HI_COUNT_ONE;
                            else
                                hi_cntr_load_val    =    HI_COUNT_ZERO;
                        end else begin
                            bit_val_next        =    1'b0;
                            hi_cntr_load_val    =    HI_COUNT_ZERO;
                        end
                    end    

                    PRIM_CODE_SINGLE_ONE: begin
                        calc_crc                =    1'b1;
                        state_next              =    INNER_STATE_HI;
                        secondary_code_next     =    SEC_CODE_NONE;
                        lo_cntr_load_val        =    LO_COUNT_REGULAR;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        
                        if(xor_flag)    begin
                            bit_val_next        =    1'b1 ^ next_rn16_bit;
                            shift_rn16_bits        =    1'b1;
                            if(bit_val_next == 1'b1)
                                hi_cntr_load_val    =    HI_COUNT_ONE;
                            else
                                hi_cntr_load_val    =    HI_COUNT_ZERO;
                        end else begin
                            bit_val_next        =    1'b1;
                            hi_cntr_load_val        =    HI_COUNT_ONE;
                        end
                    end    
                                
                    PRIM_CODE_RTCAL: begin
                        hi_cntr_load_val        =    HI_COUNT_RTCAL;
                        lo_cntr_load_val        =    LO_COUNT_REGULAR;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;
                    end

                    PRIM_CODE_TRCAL: begin
                        hi_cntr_load_val        =    HI_COUNT_TRCAL;
                        lo_cntr_load_val        =    LO_COUNT_REGULAR;
                        hi_cntr_load            =    1'b1;
                        lo_cntr_load            =    1'b1;
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    INNER_STATE_HI;
                    end
                            
                    PRIM_CODE_INSERT_CRC16: begin
                        //inner done must be asserted comb'lly on last bit so that we are ready to load in the next bit    
                        secondary_code_next     =    SEC_CODE_CRC16;
                        state_next              =    MIDDLE_STATE_BUF;
                    end
                            
                    PRIM_CODE_INSERT_RN16: begin                        
                        secondary_code_next     =    SEC_CODE_RN16;
                        state_next              =    MIDDLE_STATE_BUF;
                    end
                            
                    PRIM_CODE_INSERT_HANDLE: begin                    
                        secondary_code_next     =    SEC_CODE_HANDLE;
                        state_next              =    MIDDLE_STATE_BUF;
                    end
                            
                    //In this case we need to grab another byte before we can play anything back
                    //This unique case is shared with XOR_NEXT_16 and LAST_WRITE

                    //This should be fine, as long as each high cycle > 3 samples
                            
                    // In above case, the next byte is the number of bits to be played back
                    // So we need to parse that byte as well
                            
                    PRIM_CODE_XOR_NEXT_16B: begin
                        secondary_code_next     =    SEC_CODE_NONE;
                        state_next              =    OUTER_STATE;
                        xor_flag_next           =    1'b1;
                    end
                            
                        // In above case, the next two bytes are data, so we can start loading it in
                            
                    PRIM_CODE_LAST_WRITE: begin
                        done_next               =    1'b1;
                        state_next              =    OUTER_STATE_DONE;  // This is a type of end packet, except we assert
                        last_write_next         =    1'b1;              // last write until the next packet or we get a reset
                                                                        //Note that this is the only point where the FPGA learns
                    end                                                 //that a write is the last one.
                            
                    PRIM_CODE_END_PACKET: begin
                        done_next                =    1'b1;
                        state_next               =    OUTER_STATE_DONE;
                    end
                            
                    //default:    begin - No need - there's a defined state for all 16 state types
                    //    done_next                =    1'b1;
                    //    state_next               =    OUTER_STATE_DONE;
                    //end
                endcase
            end // end OUTER_STATE_0
            
            MIDDLE_STATE_BUF:    begin
                //Load bit into CRC16
                //Figure out where stream should come from (5 choices - should be enumerated)
                
                //calc_crc        =    1'b1;
                
                case(secondary_code) //Should be locked into the case forthe duration of the middle state
                    SEC_CODE_CRC16: begin
                        bit_val_next        =    crc_out_bit;
                        hi_cntr_load_val    =    crc_out_bit ? HI_COUNT_ONE : HI_COUNT_ZERO;
                        lo_cntr_load_val    =    LO_COUNT_REGULAR;
                        hi_cntr_load        =    1'b1;
                        lo_cntr_load        =    1'b1;
                        shift_crc_bits      =    1'b1;                    //Be careful - we need this to pulse b/c there are ~100 samples per bit    
                    end                                                    //We pulse with the extra wait state
                    SEC_CODE_RN16: begin
                        calc_crc            =    1'b1;
                        bit_val_next        =    next_rn16_bit;
                        hi_cntr_load_val    =    next_rn16_bit ? HI_COUNT_ONE : HI_COUNT_ZERO;
                        lo_cntr_load_val    =    LO_COUNT_REGULAR;
                        hi_cntr_load        =    1'b1;
                        lo_cntr_load        =    1'b1;
                        shift_rn16_bits     =    1'b1;
                    end
                    SEC_CODE_HANDLE: begin
                        calc_crc            =    1'b1;
                        bit_val_next        =    next_handle_bit;
                        hi_cntr_load_val    =    next_handle_bit ? HI_COUNT_ONE : HI_COUNT_ZERO;
                        lo_cntr_load_val    =    LO_COUNT_REGULAR;
                        hi_cntr_load        =    1'b1;
                        lo_cntr_load        =    1'b1;
                        shift_handle_bits   =    1'b1;
                    end
                    default: begin
                        //Error!!!!!. This would be strictly an RTL error, however.
                        //To make it easy, set the error flag here, but merely return to the MIDDLE_STATE_DONE
                        //We don't have any extra states, so we can't set up a holding state.
                        //122620 - Remove error handling, we need the LUT back.
                        //122620 - To save LUT, use CRC16
                        bit_val_next        =    crc_out_bit;
                        hi_cntr_load_val    =    crc_out_bit ? HI_COUNT_ONE : HI_COUNT_ZERO;
                        lo_cntr_load_val    =    LO_COUNT_REGULAR;
                        hi_cntr_load        =    1'b1;
                        lo_cntr_load        =    1'b1;
                        shift_crc_bits      =    1'b1;  
                    end
                endcase
                    
                shift_bit_cntr_incr         =    1'b1;
                state_next                  =    INNER_STATE_HI;
                
            end
                            
            INNER_STATE_HI: begin
                    
                hi                        =    1'b1;
                hi_cntr_decr              =    1'b1;
                
                if(((secondary_code != SEC_CODE_NONE) && (shift_bit_cntr    ==    4'b1)) || xor_bit_cntr == 4'd1)
                    hi_cntr_thresh    =    13'd2;
                else
                    hi_cntr_thresh    =    13'd1;
                    
                if(hi_cntr    ==    hi_cntr_thresh)    begin             //Cut of high signaling one clock cycle early to have the correct high level length.
                    if(lo_cntr    ==    6'b0)                            //This is a TXCW0. Make this fix on 090216
                        state_next    =    OUTER_STATE;
                    else
                        state_next    =    INNER_STATE_LO;
                end
            end
                
            INNER_STATE_LO: begin
                
                hi                        =    1'b0;
                lo_cntr_decr              =    1'b1;
                    
                if(lo_cntr    ==    6'b0) begin
                    if(secondary_code == SEC_CODE_NONE)
                        state_next    =    OUTER_STATE;
                    else    begin
                        if(shift_bit_cntr == 4'd0)                //This should be 4'd0, it needs to roll over to indicate that we have processed 16 shift register bits.
                            state_next    =    OUTER_STATE;
                        else
                            state_next    =    MIDDLE_STATE_BUF;
                    end    
                end
            end
            
            default: begin
                done_next                 =    1'b1;
                state_next                =    OUTER_STATE_DONE;
            end
        endcase
    end

//////////////////////////////////////////////////////////////
//
// Flops inference
//
//////////////////////////////////////////////////////////////    
    
    always @(posedge clk or negedge rst_n)    begin
        if(!rst_n) begin
            done                <=    1'b0;
            state               <=    OUTER_STATE_DONE;
            sram_address_reg    <=    TX_RAM_ADDR_OFFSET_TXCW0     << 4;
            shift_bit_cntr      <=    4'd0;
            xor_bit_cntr        <=    4'd0;
            lo_cntr             <=    6'd0;
            hi_cntr             <=    13'd0;
            secondary_code      <=    SEC_CODE_NONE;
            last_write          <=    1'b0;
            error_outer         <=    1'b0;
            out                 <=    1'b0;
            bit_val             <=    1'b0;
            sram_flag           <=    1'b0;
            xor_flag            <=    1'b0;
        end    else begin
            done                <=    done_next;
            state               <=    state_next;
            secondary_code      <=    secondary_code_next;
            last_write          <=    last_write_next;
            error_outer         <=    1'b0;
            out                 <=    out_next;
            bit_val             <=    bit_val_next;
            sram_flag           <=    sram_flag_next;
            xor_flag            <=    xor_flag_next;
            
            if(xor_bit_cntr_clr)
                xor_bit_cntr    <=    4'b0;
            else if(xor_bit_cntr_incr)
                xor_bit_cntr    <=    xor_bit_cntr+4'b1;
            
            if(shift_bit_cntr_clr)
                shift_bit_cntr  <=    4'b0;
            else if(shift_bit_cntr_incr)
                shift_bit_cntr  <=    shift_bit_cntr+4'b1;
            
            if(hi_cntr_load)
                hi_cntr         <=    hi_cntr_load_val;
            else if(hi_cntr_decr)
                hi_cntr         <=    hi_cntr-13'd1;
                
            if(lo_cntr_load)
                lo_cntr         <=    lo_cntr_load_val;
            else if(lo_cntr_decr)
                lo_cntr         <=    lo_cntr-6'd1;
            
            sram_address_reg    <=    sram_address;
            
        end
    end
endmodule
            
            
        
                            