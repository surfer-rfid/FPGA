/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module : RX Data Recovery Top Level Unit                                        //
//                                                                                 //
// Filename: data_rcvy.v                                                           //
// Creation Date: 12/2/2015                                                        //
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
//        This is the top level of the data recovery circuit.                      //
//    In this case, we do not perform CORDIC, as this doesn't need to be           //
//        computed in real time. Rather, we export magI and magQ. Then either      //
//        the local MCU or the host processor can compute CORDIC values.           //
//                                                                                 //
//    Revisions:                                                                   //
//                                                                                 //
// 121515 - Introduce RAM-based techniques to reduce LUT count.                    //
// 010316 - A reminder - RN16 reply to Query is treated differently in that        //
// CRC is not checked. So we need an extra 1 bit input to denote this              //
// condition. Ideally, we can examine waveform to decide if a collision            //
// probably occurred, but this would need to be done in a trivial way.             //
// One idea is to look at the MSB position of the individual bit magnitudes        //
// coming from the bit decision into the magI and magQ integrators. If this        //
// position deviates beyond a certain threshold (say 1 or 2 bits), it can be       //
// assumed that a collision is occurring. But, we would need to check this out     //
// in lab carefully later.                                                         //
//                                                                                 //
// Also, for Write, Read, Lock, Kill commands, do we need to check that            //
// incoming handle is correct? This may be a job for software, but consider        //
// that software never really needs to know about the handle (it is a PHY          //
// thing)                                                                          //
//                                                                                 //
// Actually the plan for now is to expose bits to the Radio FSM indicating         //
// one of a number of errors.                                                      //
//                                                                                 //
// 1. Data rcvy FSM done.                                                          //
// 2. Packet failed CRC.                                                           //
//    3. Packet timed out.                                                         //
// 4. Packet bit 0 == 1 (for a delayed reply, this means an error in the tag.)     //
// 5. Packet handle mismatch.                                                      //
// 6. Possible RN16 collision.                                                     //
//                                                                                 //
// 010416 - We need to remove use_rx_address inputs and replace with input         //
//    of the radio state machine state. From this info, the DR can compute which   //
// RX address to place the data, which (handle, RN16) register to place the        //
// data, which packets to do a handle check on. This isn't done yet, but needs     //
// to be done.                                                                     //
//                                                                                 //
//    032416 - Strip out sym_ctr_dist, switch to half-period bit decision          //
//    033016 - Make counters loadable to save on LUT.    Every 10 LUT helps now.   //
//    June16 - Removed rn16, handle shift registers from this block and put them   //
//  at the top level in order to save on shift register LUT.                       //
//    072616 - Don't forget - the CRC16 is incorrect as of now.                    //
//    082716 - Updated radio states, changed TX_RAM nomenclature to RX_RAM         //
//    Just realized: if we specify a one-hot state machine, what happens if        //
//    the state register has two ones? Isn't it vital to have the default          //
//    statement in place? We put it in - hopefully LUT doesn't increase.           //
//    if LUT does increase, then we need to go back to non-one-hot state.          //
//    We also possibly need to look at this for other blocks.                      //
//    082716 - Just realized that we need different RAM spaces for the initial     //
//    RN16 (RN16_I) and subsequent RX16s                                           //
//    061920 - Copy over from 2017 version. Merge in manually the material from    //
//    original code set with the kill packet modifications.                        //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module    data_rcvy
    (
        // Inputs
        input        wire    signed    [15:0]    in_i,
        input        wire    signed    [15:0]    in_q,
        input        wire                        clk,
        input        wire                        sample,
        input        wire                        rst_n,
        input        wire                        use_i,               // Added on 032516
        input        wire              [4:0]     radio_state,
        input        wire                        go,                  //    From full handshake 55MHz to 4p5MHz block
        input        wire              [7:0]     sram_fromdata_in,    // This is data *from* the SRAM
        input        wire                        kill_first_pkt,      // Disable delayed response when using 'write' for a 'kill'
        // Outputs
        output        wire                       bit_decision,
        output        reg                        done,
        output        reg                        timeout,
        output        reg                        fail_crc,
        output        reg                        shift_rn16,
        output        reg                        shift_handle,
        output        reg              [8:0]     sram_address,
        output        reg                        sram_wren,
        output        reg              [7:0]     sram_todata_out    // This is data *to* the SRAM        
    );
    
    // Parameter and localparam declarations
    
    // Radio FSM state designations. These will need to be moved to some other file
    // to avoid mismatch between localparam defintions in different modules
    
    `include "./radio_states_include_file.v"

    // RX SRAM Address Offsets for data deposited by microcontroller via SPI
    
    localparam    RX_RAM_ADDR_OFFSET_RN16        =    5'd0;    //These offsets are in number of 16-address chunks
    localparam    RX_RAM_ADDR_OFFSET_RN16_I      =    5'd1;    //This is required because the number of received bits is less in RN16_I than in RN16,
    localparam    RX_RAM_ADDR_OFFSET_HANDLE      =    5'd2;    //Format of each slot is:
    localparam    RX_RAM_ADDR_OFFSET_WRITE       =    5'd3;    //Number of bits of valid data            (1 byte)
    localparam    RX_RAM_ADDR_OFFSET_LOCK        =    5'd4;    //Bits of data (with trailing zeros)    (6 bytes usually)
    localparam    RX_RAM_ADDR_OFFSET_READ        =    5'd5;    //Exit code                                        (1 byte)
    localparam    RX_RAM_ADDR_OFFSET_PCEPC       =    5'd7;    //Mag I                                            (4 bytes)
                                                        //Mag Q                                            (4 bytes)
                                                        //Total                                            (16 bytes usually)
    
    // State machine designations
    
    //localparam    DR_STATE_DONE               =    4'd0;
    //localparam    DR_STATE_RESET              =    4'd1;
    //localparam    DR_STATE_IDLE               =    4'd2;
    //localparam    DR_STATE_LOCKED             =    4'd3;
    //localparam    DR_STATE_SYNC               =    4'd4;
    //localparam    DR_STATE_BITS               =    4'd5;
    //localparam    DR_STATE_CHK_CRC            =    4'd6;
    //localparam    DR_STATE_RPT_EXIT_CODE      =    4'd7;
    //localparam    DR_STATE_RPT_MI_BYT0        =    4'd8;    
    //localparam    DR_STATE_RPT_MI_BYT1        =    4'd9;
    //localparam    DR_STATE_RPT_MI_BYT2        =    4'd10;    
    //localparam    DR_STATE_RPT_MI_BYT3        =    4'd11;
    //localparam    DR_STATE_RPT_MQ_BYT0        =    4'd12;    
    //localparam    DR_STATE_RPT_MQ_BYT1        =    4'd13;
    //localparam    DR_STATE_RPT_MQ_BYT2        =    4'd14;    
    //localparam    DR_STATE_RPT_MQ_BYT3        =    4'd15;
    
    localparam    DR_STATE_DONE           =    16'b0000_0000_0000_0001;
    localparam    DR_STATE_RESET          =    16'b0000_0000_0000_0010;
    localparam    DR_STATE_IDLE           =    16'b0000_0000_0000_0100;
    localparam    DR_STATE_LOCKED         =    16'b0000_0000_0000_1000;
    localparam    DR_STATE_SYNC           =    16'b0000_0000_0001_0000;
    localparam    DR_STATE_BITS           =    16'b0000_0000_0010_0000;
    localparam    DR_STATE_DELAY_RPTS     =    16'b0000_0000_0100_0000;
    localparam    DR_STATE_RPT_EXIT_CODE  =    16'b0000_0000_1000_0000;
    localparam    DR_STATE_RPT_MI_BYT0    =    16'b0000_0001_0000_0000;    
    localparam    DR_STATE_RPT_MI_BYT1    =    16'b0000_0010_0000_0000;
    localparam    DR_STATE_RPT_MI_BYT2    =    16'b0000_0100_0000_0000;    
    localparam    DR_STATE_RPT_MI_BYT3    =    16'b0000_1000_0000_0000;
    localparam    DR_STATE_RPT_MQ_BYT0    =    16'b0001_0000_0000_0000;    
    localparam    DR_STATE_RPT_MQ_BYT1    =    16'b0010_0000_0000_0000;
    localparam    DR_STATE_RPT_MQ_BYT2    =    16'b0100_0000_0000_0000;    
    localparam    DR_STATE_RPT_MQ_BYT3    =    16'b1000_0000_0000_0000;    
    
    //Exit codes
    
    localparam    PACKET_SUCCESS          =    3'd0;
    localparam    FAIL_IDLE_WD            =    3'd1;
    localparam    FAIL_LOCKED_WD          =    3'd2;
    localparam    FAIL_SYNC_WD            =    3'd3;
    localparam    FAIL_BITS_WD            =    3'd4;
    localparam    FAIL_CRC_CODE           =    3'd5;
    localparam    WACKY_STATE             =    3'd6;
    localparam    NOTHING_HAPPENED        =    3'd7;
    
    // Memory sizes
    
    localparam    PEAK_SPACE_VEC_SIZE     =    3;
    localparam    SYM_COUNTER_VEC_SIZE    =    3;
        
    // Wire declarations
    
    wire                        crc_ok;
    wire                        is_delayed_reply;
    
    reg              [15:0]     state_next;
    reg                         done_next, timeout_next, fail_crc_next;
    
    wire             [8:0]      sram_address_next;
    reg                         sram_wren_next;
    reg              [7:0]      sram_todata_out_next;
    
    wire             [17:0]     wd_timer_next;
    wire             [8:0]      locked_timer_next;
    
    reg                         bit_counter_dn_load;
    reg                         bit_counter_dn_dec9;
    reg                         bit_counter_dn_dec1;
    reg                         bit_counter_up_clr;
    reg                         bit_counter_up_incr;
    reg                         bit_8_counter_clr;
    reg                         bit_8_counter_incr;
    reg                         space_counter_clr;
    reg                         space_counter_incr;
    reg                         sym_counter_clr;
    reg                         sym_counter_incr;
    
    wire    signed    [31:0]    integ_main_next;
    wire    signed    [31:0]    integ_alt_next;
    wire    signed    [31:0]    integ_main_0_next;
    wire    signed    [23:0]    integ_alt_0_next;
    
    reg                         prev_slope_next;
    wire                        prev_slope_next_val;
    wire                        over_idle_thresh;
    wire                        over_locked_thresh;
    
    wire                        peak_detect_next;
    
    reg                         sqwv, sqwv_next;
    
    wire                        flip;
    
    wire    signed    [31:0]    integ_main_0_abs;
    wire    signed    [31:0]    integ_alt_0_flipd;
    wire    signed    [15:0]    in_main;
    wire    signed    [15:0]    in_alt;
    
    reg                [3:0]    align_val_next;
    reg                         burn_next;
    reg                         clr_n_crc_next;
    reg                         glue_next;
    
    reg                [3:0]    exit_code_next;
    
    reg                [5:0]    peak_space_vec_next[2:0];
    
    wire                        wd_over_limit;
    wire                        locked_limit_1;
    wire                        locked_limit_2;
    reg                         crc_shift;
    reg                         first_half_bit, first_half_bit_next;
    
    //    Reg declarations
    
    reg               [15:0]    state_curr;
    
    reg               [17:0]    wd_timer;
    reg                [8:0]    locked_timer;
    reg                [7:0]    bit_counter_dn;
    reg                [4:0]    bit_counter_up;
    reg                [2:0]    bit_8_counter;
    reg                [5:0]    space_counter;
    reg                [3:0]    sym_counter;
    
    reg    signed     [31:0]    integ_main;
    reg    signed     [31:0]    integ_alt;
    reg    signed     [31:0]    integ_main_0;
    reg    signed     [23:0]    integ_alt_0;
    reg    signed     [31:0]    integ_main_store;
    
    reg                         prev_slope;
    reg                         peak_detect;
        
    reg                [3:0]    align_val;
    reg                         burn;
    reg                         clr_n_crc;
    reg                         glue;
    
    reg                [3:0]    exit_code;
    
    reg                [5:0]    peak_space_vec[2:0];
    
    reg                         sclr_integs_mainalt_0;
    reg                         sclr_integs_mainalt;
    reg                         clkena_integs_mainalt;
    reg                         sclr_integs_store;
    reg                         clkena_integs_store;
    
    reg                         wd_timer_clr;
    reg                         locked_timer_clr;
    reg                         sram_address_load;
    reg                [8:0]    sram_address_loadval;
    
    //Readout to RAM array
    
    reg                         clr_readout_addr;
    reg                         incr_readout_addr;
    reg                         load_readout;
    reg                         en_readout;
    reg                [2:0]    readout_addr;
    wire               [7:0]    readout_vec;
    
    // Module declarations
    
    // Saturate all of the integrators so that we don't get a roll-around
    // NOT!!! - we really need to save the LUTS, plus range is well-bounded

        
    // Instantiate CRC checker

    crc_ccitt16_rx    crc16
        (
            .bit_in         (bit_decision),
            .shift          (crc_shift),
            .clk            (clk),
            .rst_n_global   (rst_n),
            .rst_n_local    (clr_n_crc),
            .crc_out        (crc_ok)
        );
        
    data_rcvy_readout_ram data_rcvy_readout_ram0
        (
            .clock(clk),
            .data({integ_alt,integ_main}),
            .enable(en_readout),
            .rdaddress({4'b0000,readout_addr}),
            .wraddress(4'b0000),
            .wren(load_readout),
            .q(readout_vec)
        );
        
    // Instantiate special adders for the final integrators with explicit carry in bits    
            
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(32)
        )
    integ_main_adder
        (
            .c_in           (flip),
            .a_in           (integ_main),
            .b_in           (integ_main_0_abs),
            .y_out          (integ_main_next)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(32)
        )
    integ_alt_adder
        (
            .c_in           (flip),
            .a_in           (integ_alt),
            .b_in           (integ_alt_0_flipd),
            .y_out          (integ_alt_next)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(32)
        )
    integ_main_0_adder
        (
            .c_in           (sqwv),
            .a_in           (integ_main_0),
            .b_in           ({{16{in_main[15]}},in_main}),
            .y_out          (integ_main_0_next)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(24)
        )
    integ_alt_0_adder
        (
            .c_in           (sqwv),
            .a_in           (integ_alt_0),
            .b_in           ({{8{in_alt[15]}},in_alt}),
            .y_out          (integ_alt_0_next)
        );
        
    flip_mux_main_lut flip_mux_main_lut_inst
        (
            .in(integ_main_0),
            .flip(flip),    //Multiply by positive 1 if positive, negative 1 if negative.
            .out(integ_main_0_abs)
        );
    
    flip_mux_alt flip_mux_alt_inst
        (
            .in(integ_alt_0),
            .flip(flip),
            .out(integ_alt_0_flipd)
        );
    
    swap_mux swap_mux_main
        (
            .in_0(in_i),
            .in_1(in_q),
            .use_0(use_i),
            .flip(sqwv),
            .out(in_main)
        );
    
    swap_mux swap_mux_alt
        (
            .in_0(in_q),
            .in_1(in_i),
            .use_0(use_i),
            .flip(sqwv),
            .out(in_alt)
        );
            
    thresh_slope_comparisons thrs_slp_cmpr_inst
        (
            .integ_main_0(integ_main_0),
            .integ_main_0_abs(integ_main_0_abs),
            .integ_main_store(integ_main_store),
            .over_idle_thresh(over_idle_thresh),
            .over_locked_thresh(over_locked_thresh),
            .prev_slope_next_val(prev_slope_next_val)
        );
        
    timer_comparisons    tmr_cmpr_inst
        (
            .is_delayed_reply(is_delayed_reply),
            .wd_timer(wd_timer),
            .locked_timer(locked_timer),    
            .wd_over_limit(wd_over_limit),
            .locked_limit_1(locked_limit_1),
            .locked_limit_2(locked_limit_2)
        );
    
    // Combinational logic - assign statements

    assign    is_delayed_reply        =    ((radio_state==STATE_RX_LOCK) || ((radio_state==STATE_RX_WRITE) && !kill_first_pkt));
    assign    flip                    =    integ_main_0 < 0;
    assign    peak_detect_next        =    prev_slope_next - prev_slope; //020318 - Should be an XOR? Maybe make results to bits to get sign also.
    assign    bit_decision            =    first_half_bit ^ (integ_main_0 >= 0);
    
    // Timers and counters
    
    assign    wd_timer_next           =    wd_timer+18'd1;
    assign    locked_timer_next       =    locked_timer+9'd1;
    assign    sram_address_next       =    sram_address+7'd1;
    
    //    State transition logic
    
    always @(*) begin

        //Defaults
            
        //Reset timers and counters
        wd_timer_clr                  =    1'b0;
        locked_timer_clr              =    1'b1;

        bit_counter_dn_load           =    1'b0;
        bit_counter_dn_dec9           =    1'b0;
        bit_counter_dn_dec1           =    1'b0;
        bit_counter_up_clr            =    1'b0;
        bit_counter_up_incr           =    1'b0;
        bit_8_counter_clr             =    1'b0;
        bit_8_counter_incr            =    1'b0;
        space_counter_clr             =    1'b0;
        space_counter_incr            =    1'b0;
        sym_counter_clr               =    1'b0;
        sym_counter_incr              =    1'b0;
            
        //Reset correlation waveforms
        sqwv_next                     =    sqwv;
        //Memory of integrator and slope for slope checking
        prev_slope_next               =    prev_slope;
        align_val_next                =    align_val;
        burn_next                     =    burn;
        //Send a pulse to reset the CRC
        clr_n_crc_next                =    1;
        crc_shift                     =    0;
        //Clear the glue flag
        glue_next                     =    glue;
        //Set the exit code to something odd
        exit_code_next                =    exit_code;            //Something bizarre happened if this stays in there
        //Clear sync state memory vecs
        peak_space_vec_next[2]        =    peak_space_vec[2];    //Also, we make sure that the new data coming in is zero
        peak_space_vec_next[1]        =    peak_space_vec[1];
        peak_space_vec_next[0]        =    peak_space_vec[0];
        //Next state
        state_next                    =    state_curr;
        done_next                     =    1'b0;
        timeout_next                  =    1'b0;
        fail_crc_next                 =    1'b0;
        //Addressing
        sram_address_load             =    1'b0;
        sram_address_loadval          =    9'b0;                 //Code 00 means don't load a new value
        sram_wren_next                =    1'b0;
        sram_todata_out_next          =    sram_todata_out;
        //Register resetting
        sclr_integs_mainalt_0         =    1'b0;
        sclr_integs_mainalt           =    1'b0;
        sclr_integs_store             =    1'b0;
        clkena_integs_mainalt         =    1'b0;
        clkena_integs_store           =    1'b1;
        shift_rn16                    =    1'b0; 
        shift_handle                  =    1'b0;
        first_half_bit_next           =    first_half_bit;
        //Data readout
        clr_readout_addr              =    1'b0;
        incr_readout_addr             =    1'b0;
        load_readout                  =    1'b0;
        en_readout                    =    1'b0;
    
        if(sample) begin
            sqwv_next                 =    ~sqwv;
            sym_counter_incr          =    1'b1; // Will automatically implement the modulo 16 function
            space_counter_incr        =    (space_counter <= 6'd63) ? 1'b1 : 1'b0; //020318 - This may be a bug which may be losing us some packets. Should be < 6'd63.
        end
            
        case(state_curr)
            
            DR_STATE_DONE:    begin
                    
                //Stop WD timer
                wd_timer_clr    =    1'b1;
                    
                //Go to next state when the global state machine says it's OK
                if(go)    begin
                    done_next    =    0;
                    state_next    =    DR_STATE_RESET;
                        
                    case(radio_state)
                        STATE_RX_RN16_I: begin
                            sram_address_load        =    1'b1;
                            sram_address_loadval     =    RX_RAM_ADDR_OFFSET_RN16_I << 4;    //We need to take from a different address here b/c a query-based RN16 (RN16_I)
                        end
                        STATE_RX_RN16: begin
                            sram_address_load        =    1'b1;
                            sram_address_loadval     =    RX_RAM_ADDR_OFFSET_RN16 << 4;
                        end
                        STATE_RX_PCEPC: begin
                            sram_address_load        =    1'b1;
                            sram_address_loadval     =    RX_RAM_ADDR_OFFSET_PCEPC << 4;
                        end
                        STATE_RX_HANDLE: begin
                            sram_address_load        =    1'b1;
                            sram_address_loadval     =    RX_RAM_ADDR_OFFSET_HANDLE << 4;
                        end
                        STATE_RX_WRITE: begin
                            sram_address_load        =    1'b1;
                            sram_address_loadval     =    RX_RAM_ADDR_OFFSET_WRITE << 4;
                        end
                        STATE_RX_READ: begin
                            sram_address_load        =    1'b1;
                            sram_address_loadval     =    RX_RAM_ADDR_OFFSET_READ << 4;
                        end
                        STATE_RX_LOCK: begin
                            sram_address_load        =    1'b1;
                            sram_address_loadval     =    RX_RAM_ADDR_OFFSET_LOCK << 4;
                        end
                        default        : begin
                            sram_address_load        =    1'b0;
                            sram_address_loadval     =    9'b0;    //Possibly flag an error here
                        end
                    endcase
                end
            end //end state done
                    
            DR_STATE_RESET: begin
                    
                //Reset integrators
                sclr_integs_mainalt_0     =    1'b1;
                sclr_integs_mainalt       =    1'b1;
                sclr_integs_store         =    1'b1;
                clkena_integs_mainalt     =    1'b0;
                //Reset timers and counters
                wd_timer_clr              =    1'b1;
                locked_timer_clr          =    1'b1;
                //bit_counter_dn_next=    sram_fromdata_in;            //This sets the number of bits to be received prior to checking CRC
                bit_8_counter_clr         =    1'b1;
                space_counter_clr         =    1'b1;
                sym_counter_clr           =    1'b1;
                //Reset correlation waveforms
                sqwv_next                 =    0;
                //Memory of integrator and slope for slope checking
                prev_slope_next           =    0;                       //0 indicates negative slope, 1 indicates positive slope
                align_val_next            =    1;
                burn_next                 =    1;                       //Burn the first integrator output in bits state
                //Send a pulse to reset the CRC
                clr_n_crc_next            =    0;
                //Clear the glue flag
                glue_next                 =    0;
                //Set the exit code to something odd
                exit_code_next            =    NOTHING_HAPPENED;        //Something bizarre happened if this stays in there
                //clear sync state memory vecs
                peak_space_vec_next[2]    =    0;                       //Also, we make sure that the new data coming in is zero
                peak_space_vec_next[1]    =    0;
                peak_space_vec_next[0]    =    0;
                //Next state
                state_next                =    DR_STATE_IDLE;
                done_next                 =    0;
                first_half_bit_next       =    0;
            end
                    
            DR_STATE_IDLE:    begin
                
                if(wd_over_limit)    begin                            //This is essentially our timeout catch. Currently it times out at 65536 or 14.5ms.                                         
                    done_next         =    1;                         //Actually we need it to time out at 20ms for delayed replies. So we must fix this later.
                    timeout_next      =    1;
                    state_next        =     DR_STATE_DONE;
                    exit_code_next    =    FAIL_IDLE_WD;
                end
                    
                if(over_idle_thresh)
                    state_next        =    DR_STATE_LOCKED;
                end
                    
            DR_STATE_LOCKED: begin
                
                locked_timer_clr      =    1'b0;
                
                if(wd_over_limit)    begin
                    done_next         =    1;
                    timeout_next      =    1;
                    state_next        =     DR_STATE_DONE;
                    exit_code_next    =    FAIL_LOCKED_WD;
                end
                        
                if(locked_limit_1)    begin
                    sclr_integs_mainalt_0    =    1'b1;
                end
                        
                if(locked_limit_2)    begin
                    prev_slope_next          =    integ_main_0 >= 0;                // This time we will set integI to zero at locked_timer_limit1 to save registers
                            
                    if(over_locked_thresh)    begin
                        state_next               =    DR_STATE_SYNC;
                        wd_timer_clr             =    1'b1;
                        sclr_integs_mainalt_0    =    1'b1;
                    end else begin
                        state_next               =    DR_STATE_RESET;
                            //    wd_timer_clr            =    1'b1;                            // Do not clear this - if we don't get the packet by the predefined time, it is over!
                    end
                end
            end
    
    //    Combinational logic - conditional assignments
            DR_STATE_SYNC: begin
                
                clkena_integs_store    =    1'b0;
                            
                if(wd_over_limit) begin
                    done_next                     =    1;
                    timeout_next                  =    1;
                    state_next                    =     DR_STATE_DONE;
                    exit_code_next                =    FAIL_SYNC_WD;
                end
    
                if(sample) begin
                    clkena_integs_store           =    1'b1;
                    prev_slope_next               =    prev_slope_next_val;
                end

                if(peak_detect) begin
                    if(space_counter < 4) begin
                        peak_space_vec_next[2]    =    peak_space_vec[2];
                        peak_space_vec_next[1]    =    peak_space_vec[1];
                        peak_space_vec_next[0]    =    peak_space_vec[0]+space_counter;
                        glue_next                 =    1;
                    end else if(glue) begin
                        peak_space_vec_next[2]    =    peak_space_vec[2];
                        peak_space_vec_next[1]    =    peak_space_vec[1];
                        peak_space_vec_next[0]    =    peak_space_vec[0]+space_counter;
                        glue_next                 =    0;
                    end else begin
                        peak_space_vec_next[2]    =    peak_space_vec[1];
                        peak_space_vec_next[1]    =    peak_space_vec[0];
                        peak_space_vec_next[0]    =    space_counter;
                        glue_next                 =    0;
                    end
                                
                    space_counter_clr             =    1'b1;
                                
                    if((peak_space_vec[1] >= 6'd29 && peak_space_vec[1] <= 6'd34) && (peak_space_vec[0] >= 6'd13 && peak_space_vec[0] <= 6'd18) && (space_counter >= 6'd13 && space_counter <= 6'd18)) begin
                        align_val_next            =    (sym_counter + 4'd7);     //Modulo 16 implemented automatically
                        wd_timer_clr              =    1'b1;
                        state_next                =    DR_STATE_BITS;
                        sclr_integs_mainalt_0     =    1'b1;
                        burn_next                 =    1'b1;
                        //bit_counter_dn_next     =    sram_fromdata_in[7:0];        // Do this here, after the double registered RAM is sure to have settled.
                        bit_counter_dn_load       =    1'b1;
                        bit_counter_up_clr        =    1'b1;
                    end
                end    
            end    
            DR_STATE_BITS: begin

                                    
                if(sample) begin
                    if(((sym_counter-align_val) % 16) == 8)    begin
                        if(burn != 0)
                            sclr_integs_mainalt_0    =    1'b1;
                        else begin
                            first_half_bit_next      =    integ_main_0 >= 0;
                            clkena_integs_mainalt    =    1'b1;
                            sclr_integs_mainalt_0    =    1'b1;
                        end
                    end    else if(sym_counter == align_val) begin
                        if(burn != 0) begin
                            burn_next                =     0;
                            sclr_integs_mainalt_0    =    1'b1;

                            // If we are on the first packet of a kill, we need to subtract 9 from the 41 entered in from RX_BITS_WRITE. 
                            // Yes this is terrible but we have to live with this hack for now.
                            if (kill_first_pkt && (radio_state==STATE_RX_WRITE))  begin
                                bit_counter_dn_dec9    =    1'b1;
                            end

                        end else begin
                            crc_shift                  =    1'b1;
                            if(bit_counter_up == 0 && bit_decision == 0 && is_delayed_reply)
                                bit_counter_dn_dec9    =    1'b1;    //We received an error-free delayed reply, so #bits is 8 less than usual
                            else
                                bit_counter_dn_dec1    =    1'b1;
                                            
                            bit_counter_up_incr        =    bit_counter_up >= 5'd16 ? 1'b0 : 1'b1; 
                            bit_8_counter_incr         =    1'b1;
                            //sram_todata_out_next     =    {bit_decision,sram_todata_out[7:1]}; //Why a shift register not detected? Fixed this on 091316
                            sram_todata_out_next       =    {sram_todata_out[6:0],bit_decision};
                                            
                            if((radio_state    ==    STATE_RX_RN16_I || radio_state == STATE_RX_RN16) && bit_counter_up < 16)
                                shift_rn16             =    1'b1;    //This is actually correct even though RN16_I and RN16 both end differently (RN16 ends with a CRC-16)
                                                
                            if(radio_state    ==    STATE_RX_HANDLE && bit_counter_up < 16)
                                shift_handle           =    1'b1;
                                                
                            clkena_integs_mainalt      =    1'b1;
                            sclr_integs_mainalt_0      =    1'b1;
                                                
                            if(bit_8_counter == 3'd7) begin
                                sram_wren_next         =    1'b1;    // This needs to be delayed a few ns before it hits the SRAM, or inverted
                            end
                            if(bit_counter_dn == 0)    begin // We have reached the end of the packet (may need to set this to == 1, otherwise RX_RN16_I will not work)
                                state_next             =    DR_STATE_RPT_EXIT_CODE;    // Remember, we won't do CORDIC here (for now). This can be done offline in MCU.
                                clr_readout_addr       =    1'b1;
                                en_readout             =    1'b1;
                                load_readout           =    1'b1;
                                                    
                                if(crc_ok || radio_state == STATE_RX_RN16_I)           //RX response to query or query rep or query adjust has no CRC
                                    exit_code_next        =    PACKET_SUCCESS;
                                else
                                    exit_code_next        =    FAIL_CRC_CODE;
                            end        // if(bit_counter_dn == 0)
                        end    // else if(sym_counter == align_val)
                    end    // else
                end // if(sample)
            end    // END CASE: DR_STATE_BITS
            DR_STATE_RPT_EXIT_CODE: begin
                sram_todata_out_next      =    {readout_vec[7:4],exit_code};
                //sram_todata_out_next    =    readout_vec;
                incr_readout_addr         =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MI_BYT0;
            end
            DR_STATE_RPT_MI_BYT0: begin
                //sram_todata_out_next    =    integ_main[7:0];
                sram_todata_out_next      =    readout_vec;
                incr_readout_addr         =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MI_BYT1;
            end
            DR_STATE_RPT_MI_BYT1: begin
                //sram_todata_out_next    =    integ_main[15:8];
                sram_todata_out_next      =    readout_vec;
                incr_readout_addr         =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MI_BYT2;
            end
            DR_STATE_RPT_MI_BYT2: begin
                //sram_todata_out_next    =    integ_main[23:16];
                sram_todata_out_next      =    readout_vec;
                incr_readout_addr         =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MI_BYT3;
            end
            DR_STATE_RPT_MI_BYT3: begin
                //sram_todata_out_next    =    integ_main[31:24];
                sram_todata_out_next      =    readout_vec;
                incr_readout_addr         =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MQ_BYT0;
            end
            DR_STATE_RPT_MQ_BYT0: begin
                //sram_todata_out_next    =    integ_alt[7:0];
                sram_todata_out_next      =    readout_vec;
                incr_readout_addr         =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MQ_BYT1;
            end
            DR_STATE_RPT_MQ_BYT1: begin
                //sram_todata_out_next    =    integ_alt[15:8];
                sram_todata_out_next      =    readout_vec;
                incr_readout_addr         =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MQ_BYT2;
            end
            DR_STATE_RPT_MQ_BYT2: begin
                //sram_todata_out_next    =    integ_alt[23:16];
                sram_todata_out_next      =    readout_vec;
                //incr_readout_addr       =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_RPT_MQ_BYT3;
            end
            DR_STATE_RPT_MQ_BYT3: begin
                //sram_todata_out_next    =    integ_alt[31:24];
                sram_todata_out_next      =    readout_vec;
                //incr_readout_addr       =    1'b1;
                en_readout                =    1'b1;
                sram_wren_next            =    1'b1;
                state_next                =    DR_STATE_DONE;
                done_next                 =    1'b1;
                fail_crc_next             =    exit_code    !=    PACKET_SUCCESS;
            end
            default: begin
                state_next                =    DR_STATE_DONE;
                done_next                 =    1'b1;
            end
        endcase
    end
                                
    // Infer flops
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state_curr          <=    DR_STATE_DONE;
            done                <=    0;
            timeout             <=    0;
            fail_crc            <=    0;
    
            sram_address        <=    9'b0;
            sram_wren           <=    0;
            sram_todata_out     <=    0;
    
            wd_timer            <=    0;
            locked_timer        <=    0;
            bit_counter_dn      <=    0;
            bit_counter_up      <=    0;
            bit_8_counter       <=    0;
            space_counter       <=    0;
            sym_counter         <=    0;
    
            integ_main_0        <=    32'b0;
            integ_alt_0         <=    24'b0;
            integ_main          <=    32'b0;
            integ_alt           <=    32'b0;
            integ_main_store    <=    32'b0;
            
            prev_slope          <=    0;
            peak_detect         <=    0;
            
            sqwv                <=    0;
                
            align_val           <=    4'b0;
            burn                <=    0;
            clr_n_crc           <=    0;
            glue                <=    0;
            
            exit_code           <=    NOTHING_HAPPENED;
    
            peak_space_vec[2]   <=    6'b0;
            peak_space_vec[1]   <=    6'b0;
            peak_space_vec[0]   <=    6'b0;
                    
            first_half_bit      <=    1'b0;
                    
            readout_addr        <=    3'b0;
        end else begin
                        
            if(sclr_integs_store)
                integ_main_store        <=    32'b0;
            else begin
                if(clkena_integs_store)
                    integ_main_store    <=    integ_main_0;    //032516 - Be careful, whether to use integ_main_0_next or integ_main_0 depends on when _store is asserted
            end
                                
            if(sclr_integs_mainalt_0)    begin
                integ_main_0            <=    32'b0;
                integ_alt_0             <=    24'b0;
            end else begin
                integ_main_0            <=    integ_main_0_next;
                integ_alt_0             <=    integ_alt_0_next;
            end
                    
            if(sclr_integs_mainalt) begin
                    integ_main          <=    32'b0;
                    integ_alt           <=    32'b0;
            end else begin
                if(clkena_integs_mainalt) begin
                    integ_main          <=    integ_main_next;
                    integ_alt           <=    integ_alt_next;
                end
            end
                                
            if(wd_timer_clr)
                    wd_timer            <=    0;
            else
                    wd_timer            <=    wd_timer_next;
                            
            if(locked_timer_clr)
                    locked_timer        <=    0;
            else
                    locked_timer        <=    locked_timer_next;
                    
            if(sram_wren_next)
                sram_address            <=    sram_address_next;
            else if(sram_address_load)
                sram_address            <=    sram_address_loadval;
                    
                    
            if(bit_counter_dn_dec9)
                bit_counter_dn          <=    bit_counter_dn-8'd9;
            else if(bit_counter_dn_dec1)
                bit_counter_dn          <=    bit_counter_dn-8'd1;
            else if(bit_counter_dn_load)
                bit_counter_dn          <=    sram_fromdata_in[7:0];
                        
            if(bit_counter_up_clr)
                bit_counter_up          <=    5'b0;
            else if(bit_counter_up_incr)
                bit_counter_up          <=    bit_counter_up+5'b1;
                    
            if(bit_8_counter_clr)
                bit_8_counter           <=    3'b0;
            else if(bit_8_counter_incr)
                bit_8_counter           <=    bit_8_counter+3'b1;
                        
            if(space_counter_clr)
                space_counter           <=    6'b0;
            else if(space_counter_incr)
                space_counter           <=    space_counter+6'b1;
                        
            if(sym_counter_clr)
                sym_counter             <=    4'b0;
            else if(sym_counter_incr)
                sym_counter             <=    sym_counter+4'b1;
                    
            if(clr_readout_addr)    begin
                readout_addr            <=    3'b0;
            end else if(incr_readout_addr) begin
                readout_addr            <=    readout_addr+3'd1;
            end
                    
            state_curr                  <=    state_next;
            done                        <=    done_next;
            timeout                     <=    timeout_next;
            fail_crc                    <=    fail_crc_next;
    
            sram_wren                   <=    sram_wren_next;
            sram_todata_out             <=    sram_todata_out_next;
            
            prev_slope                  <=    prev_slope_next;
            peak_detect                 <=    peak_detect_next;
            
            sqwv                        <=    sqwv_next;
                
            align_val                   <=    align_val_next;
            burn                        <=    burn_next;
            clr_n_crc                   <=    clr_n_crc_next;
            glue                        <=    glue_next;
            
            exit_code                   <=    exit_code_next;
                    
            peak_space_vec[2]           <=    peak_space_vec_next[2];
            peak_space_vec[1]           <=    peak_space_vec_next[1];
            peak_space_vec[0]           <=    peak_space_vec_next[0];
                   
            first_half_bit              <=    first_half_bit_next;
        end
    end // end always@(posedge clk or negedge rst_n)
                    
endmodule
                