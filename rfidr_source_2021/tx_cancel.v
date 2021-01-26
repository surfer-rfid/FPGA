////////////////////////////////////////////////////////////////////////////////////////
//                                                                                    //
// Module : TX Cancellation Logic                                                     //
//                                                                                    //
// Filename: tx_cancel.v                                                              //
// Creation Date: 12/27/2015                                                          //
// Author: Edward Keehr                                                               //
//                                                                                    //
// Copyright Superlative Semiconductor LLC 2021                                       //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2        //
// You may redistribute and modify this documentation and make products               //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).           //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                   //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                       //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2                 //
// for applicable conditions.                                                         //
//                                                                                    //
// Description:                                                                       //
//        This file describes the TX Cancellation Logic. The TX Cancel logic          //
//    runs at 4.5MHz and uses a state machine operation to undertake different        //
//    operations at each of the 128 steps between DC samples.                         //
//                                                                                    //
//    Revisions:                                                                      //
//                                                                                    //
//  032416 - In new Quartus environment, implement the 2-bit system                   //
//    062216 - Implement reduced truncation and blind rotation features.              //
//    071516 - Update to add changes required by top level Octave sim.                //
//    091216 - Needed to add gating on state transitions due to lag in handshaking    //
//    This may be a problem with regards to cap. state update - if it takes too       //
//    long, the cap value will jump around as it is trying to settle.                 //
//    091816 - Needed to transfer all data at once in order to avoid feedback lag.    //
//    Also, this should save LUT.                                                     //
//    112216 - TX Gain was wrong! 0xB8 low gain, 0x9A high gain.                      //
//    010117 - Transition to the SDM- based design                                    //
//    082817 - Incorporate improved DTC/TMN test mode for automated TMN meas.         //
//    101017 - Incorporate data-driven gain control, other matches with octave        //
//    112617 - Add fail counter back in for reliable operation.                       //
//                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////

module tx_cancel
    (
        // Inputs
        input    wire    signed    [15:0]    dc_in_i,
        input    wire    signed    [15:0]    dc_in_q,
        input    wire                        dc_ready,
        input    wire                        rst_n,
        input    wire                        spi_ack,        //This signal comes in from main 55 MHz to 4p5 MHz synchronizer
        input    wire                        clk_4p5,        //4p5 MHz clock is used here
        input    wire              [7:0]     mem_wdata,
        input    wire              [9:0]     mem_wraddress,
        input    wire                        mem_clk,
        input    wire                        mem_wren,
        input    wire                        go_radio,        //Have it reset after each TX transaction
        
        // Outputs
        output    wire             [7:0]    mem_rdata,
        output    reg              [7:0]    spi_data_out,
        output    wire             [14:0]   spi_data_aux_out, //New as of 9/18. It never needs to change so it's a wire.
        output    reg                       spi_data_csel,    //This is the chip select for which of the DTC/Radio is targeted. 1 bit as of 9/18
        output    reg                       spi_data_rdy      //in order to send gain or capacitor config information.
    );
    
    // Parameter and localparam declarations
    
    localparam    STATE_IDLE                =    4'd0;
    localparam    STATE_DC_READY            =    4'd1;
    localparam    STATE_CURR_ERROR_LOAD     =    4'd2;
    localparam    STATE_STEP_VEC_LOAD       =    4'd3;
    localparam    STATE_STEP_VEC_LATCH      =    4'd4;
    localparam    STATE_COMPUTE1            =    4'd5;
    localparam    STATE_ASSERT_SPI_RDY0     =    4'd6;
    localparam    STATE_WAIT_SPI_RDY0       =    4'd7;
    localparam    STATE_ASSERT_SPI_RDY1     =    4'd8;
    localparam    STATE_WAIT_SPI_RDY1       =    4'd9;
    localparam    STATE_DUMMY_10            =    4'd10;
    localparam    STATE_DUMMY_11            =    4'd11;
    localparam    STATE_DUMMY_12            =    4'd12;    
    localparam    STATE_DUMMY_13            =    4'd13;
    localparam    STATE_DUMMY_14            =    4'd14;
    localparam    STATE_DUMMY_15            =    4'd15;
    
    localparam    HI_GAIN_SETTING           =    8'b001_1010_0;    //Set to 0x34 - Max LNA gain, LNA and SDM saturate at similar levels
    localparam    MD_GAIN_SETTING           =    8'b100_1010_0;    //Set to 0x94 - Med LNA gain, LNA and SDM saturate at similar levels
    localparam    LO_GAIN_SETTING           =    8'b110_1010_0;    //Set to 0xD4 - Min LNA gain, LNA and SDM saturate at similar levels
    
    localparam    RADIO_RX_ADDRESS          =    8'b1_000_1100;    //First bit is a 1 for write, 0x0c is address for Rx Gain
        
    // Register and wire declarations
    
    wire    signed    [17:0]    mult_i_out, mult_q_out, curr_error, common_adder_out, step_vec1_next, step_vec2_next;
    wire    signed    [19:0]    prev_error_flipped;
    reg     signed    [19:0]    hi_prev_error_flipped;
    wire    signed    [21:0]    mult_i_shift4b_out, mult_q_shift4b_out, prev_error_fail_boost, hi_prev_error_fail_boost;
    wire    signed    [26:0]    mult_shift8b_out;    
    wire                        curr_error_gt_16383_next, curr_error_gt_2047_next, curr_error_gt_255_next, curr_error_gt_127_next;
    wire                        curr_error_gt_31_next, curr_error_gt_23_next, curr_error_gte_prev_error;
    wire    signed    [17:0]    state_cap1_next, state_cap2_next;
    wire    signed    [15:0]    state_cap1_next_sat, state_cap2_next_sat;
    wire    signed    [1:0]     mult_i_small_out, mult_q_small_out;
    wire                        abs_i_greater;
    
    // Combinational registers
    
    reg                         spi_data_rdy_next;
    reg                [3:0]    state_next;
    reg                [1:0]    loop_mode_next;
    reg                         load_prev_error, load_step_vec1, load_step_vec2, latch_step_vec1, latch_step_vec2, load_lna_gain;
    reg                         dc_in_reg_store;
    reg     signed     [1:0]    prev_error_flip;
    reg                         compare_curr_err;
    reg                         c1_flag_next, c2_flag_next;
    reg                         burn_next;
    reg                         burn_higain, burn_higain_next;
    reg                [1:0]    lna_gain_state_next;          //00-LO, 01-MD, 02-HI, 03-Treat as HI, revert to 02
    reg                         lna_gain_change_next;         //Only perform SPI comms to SX1257 if the LNA gain changes
    reg                         reset_cap_state_next;         //If we think we're railed out, reset caps and try again!!!!
    reg                         incr_fail_ctr, clear_fail_ctr;
    

    
    // Real registers
    
    reg     signed    [15:0]    dc_in_i_store, dc_in_q_store;
    reg                         curr_error_gt_16383, curr_error_gt_2047, curr_error_gt_255, curr_error_gt_127, curr_error_gt_31, curr_error_gt_23;
    reg               [3:0]     state_curr;
    reg               [14:0]    state_cap1, state_cap2;
    reg               [1:0]     loop_mode;
    reg     signed    [17:0]    step_vec1, step_vec2;
    reg                         burn;
    reg                         c1_flag, c2_flag;
    reg     signed    [17:0]    prev_error;
    reg               [2:0]     fail_ctr;                    //Abolish fail ctr for now 101017
    reg               [1:0]     lna_gain_state;              //00-LO, 01-MD, 02-HI, 03-Treat as HI, revert to 02
    reg                         lna_gain_change;             //Only perform SPI comms to SX1257 if the LNA gain changes
    reg                         reset_cap_state;             //If we think we're railed out, reset caps and try again!!!!
    
    // Module declarations
    
    txcancel_mem txcancel_mem_0(
        .data_a(8'b0),
        .address_a(10'b0),
        .clock_a(clk_4p5),
        .wren_a(1'b0),
        .q_a(),
        .data_b(mem_wdata),
        .address_b(mem_wraddress),
        .clock_b(mem_clk),
        .wren_b(mem_wren),
        .q_b(mem_rdata)
    ); //a = txcancel side (4.5MHz), b=spi side (27.5MHz)
    
    lpm_mult_dual
        #(
            .WIDTH_A(16),
            .WIDTH_B(2)
        )
    mult_i
        (
            .a_in(dc_in_i_store),             //16b
            .b_in(mult_i_small_out),          //2b
            .y_out(mult_i_out)                //18b
        );
    
    lpm_mult_dual
        #(
            .WIDTH_A(16),
            .WIDTH_B(2)
        )
    mult_q
        (
            .a_in(dc_in_q_store),
            .b_in(mult_q_small_out),
            .y_out(mult_q_out)
        );

    lpm_mult_dual
        #(
            .WIDTH_A(18),
            .WIDTH_B(4)
        )
    fail_boost_reg
        (
            .a_in(prev_error_flipped[18:1]),
            .b_in((fail_ctr>=3'd6 && incr_fail_ctr) ? 4'sb0010 : 4'sb0001), //Putting zero-blanking here results in 18-LE improvement
            .y_out(prev_error_fail_boost)
        );
    
    lpm_mult_dual
        #(
            .WIDTH_A(18),
            .WIDTH_B(4)
        )
    hi_fail_boost_reg
        (
            .a_in(hi_prev_error_flipped[17:0]),
            .b_in((fail_ctr>=3'd6 && incr_fail_ctr) ? 4'sb0010 : 4'sb0001), //Putting zero-blanking here results in 18-LE improvement
            .y_out(hi_prev_error_fail_boost)
        );
    
    lpm_mult_dual
        #(
            .WIDTH_A(18),
            .WIDTH_B(4)
        )
    mult_i_shift_1
        (
            .a_in(mult_i_out),
            .b_in(abs_i_greater ? 4'sb0100 : 4'sb0001), //Putting zero-blanking here results in 18-LE improvement
            .y_out(mult_i_shift4b_out)
        );
    
    lpm_mult_dual
        #(
            .WIDTH_A(18),
            .WIDTH_B(4)
        )
    mult_q_shift_1
        (
            .a_in(mult_q_out),
            .b_in(abs_i_greater ? 4'sb0001 : 4'sb0100),
            .y_out(mult_q_shift4b_out)
        );
    
    lpm_mult_dual
        #(
            .WIDTH_A(18),
            .WIDTH_B(9)
        )
    mult_shift_2
        (
            .a_in(common_adder_out),
            .b_in(lna_gain_state==2'b00 ? 9'sb010000000 : (lna_gain_state==2'b01 ? 9'sb000010000 : 9'sb000000001)),
            .y_out(mult_shift8b_out)
        );
    
    lpm_mult_dual
        #(
            .WIDTH_A(18),
            .WIDTH_B(2)
        )
    mult_flip
        (
            .a_in(prev_error),
            .b_in(prev_error_flip),
            .y_out(prev_error_flipped)
        );
    
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(18)
        ) 
    add_18_1
        (
            .c_in(1'b0),
            .a_in(mult_i_shift4b_out[19:2]),
            .b_in(mult_q_shift4b_out[19:2]),
            .y_out(common_adder_out)
        );
        
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(18)
        ) 
    add_18_2
        (
            .c_in(1'b0),
            .a_in(step_vec1),
            .b_in({3'b0,state_cap1}),
            .y_out(state_cap1_next)
        );
    
    lpm_add_ci
        #(
            .WIDTH_IN_OUT(18)
        ) 
    add_18_3
        (
            .c_in(1'b0),
            .a_in(step_vec2),
            .b_in({3'b0,state_cap2}),
            .y_out(state_cap2_next)
        );
    
    dtc_state_saturate tx_sat1(
        .in(state_cap1_next),
        .out(state_cap1_next_sat)
    );
    
    dtc_state_saturate tx_sat2(
        .in(state_cap2_next),
        .out(state_cap2_next_sat)
    );

    // cap1_next needs to be a 11 bit signed number, as it can go negative
    // can potentially save LUT if this condition is checked in combinational logic then zeros entered in.
    // cap1 and cap 2 are each initialized to 0111101111, or 495
    
    // Combinational logic
    
    
    assign    spi_data_aux_out            =    {state_cap1[9:5],state_cap2[14:10],state_cap2[9:5]};
    assign    mult_i_small_out            =    (dc_in_i_store >= 0) ? 2'sb01 : 2'sb11;
    assign    mult_q_small_out            =    (dc_in_q_store >= 0) ? 2'sb01 : 2'sb11;
    assign    abs_i_greater               =    mult_i_out >= mult_q_out;
    assign    curr_error                  =    mult_shift8b_out[24:7];
    assign    curr_error_gt_16383_next    =    curr_error > 18'sd16383;
    assign    curr_error_gt_2047_next     =    curr_error > 18'sd2047;
    assign    curr_error_gt_255_next      =    curr_error > 18'sd255;
    assign    curr_error_gt_127_next      =    curr_error > 18'sd127;
    assign    curr_error_gt_31_next       =    curr_error > 18'sd31;
    assign    curr_error_gt_23_next       =    curr_error > 18'sd23;
    
    assign    curr_error_gte_prev_error   =    curr_error >= prev_error;
    
    // State machine combinational logic
    
    always @(*)    begin        
        // Defaults
        state_next               =    state_curr;
        dc_in_reg_store          =    1'b0;
        compare_curr_err         =    1'b0;
        
        loop_mode_next           =    loop_mode;
        
        latch_step_vec1          =    1'b0;
        latch_step_vec2          =    1'b0;
        load_step_vec1           =    1'b0;
        load_step_vec2           =    1'b0;
        load_prev_error          =    1'b0;
        load_lna_gain            =    1'b0;
        
        prev_error_flip          =    2'sb00;
        
        spi_data_csel            =    1'b0;
        spi_data_out             =    {{3{1'b0}},state_cap1[14:10]};
        spi_data_rdy_next        =    1'b0;
        
        c1_flag_next             =    c1_flag;
        c2_flag_next             =    c2_flag;
        burn_next                =    burn;
        burn_higain_next         =    burn_higain;
        
        hi_prev_error_flipped    =    19'sd32;
        
        lna_gain_state_next      =    lna_gain_state;
        lna_gain_change_next     =    1'b0;
        reset_cap_state_next     =    1'b0;
        
        incr_fail_ctr            =    1'b0;
        clear_fail_ctr           =    1'b0;
            
        case(state_curr)
            
            STATE_IDLE: begin
                if(dc_ready)    begin
                    state_next        =    STATE_DC_READY;
                    dc_in_reg_store   =    1'b1;
                end
            end
            
            STATE_DC_READY: begin
                state_next            =    STATE_CURR_ERROR_LOAD;
                compare_curr_err      =    1'b1;
                //Can also register control signals for multipliers here
            end
            
            STATE_CURR_ERROR_LOAD: begin
                state_next            =    STATE_STEP_VEC_LOAD;
                case(loop_mode)
                    2'b00: begin
                        load_prev_error        =    1'b1;
                    end
                    2'b01: begin
                        //Do nothing
                    end
                    2'b10: begin
                        load_prev_error        =    1'b1;
                    end
                    2'b11: begin
                        //Do nothing
                    end
                endcase
            end
            
            STATE_STEP_VEC_LOAD: begin
                state_next            =    STATE_STEP_VEC_LATCH;
                case(loop_mode)
                    2'b00: begin
                        if(c1_flag==0)    begin
                            prev_error_flip          =    2'sb01;
                            hi_prev_error_flipped    =    19'sd32;
                        end else begin
                            prev_error_flip          =    2'sb11;
                            hi_prev_error_flipped    =    -19'sd32;
                        end
                        load_step_vec1               =    1'b1;
                    end
                    2'b01: begin
                        if(c1_flag==0) begin
                            prev_error_flip          =    2'sb11;
                            hi_prev_error_flipped    =    -19'sd32;
                        end else begin
                            prev_error_flip          =    2'sb01;
                            hi_prev_error_flipped    =    19'sd32;
                        end
                        if(curr_error_gte_prev_error && burn)    begin    
                            load_step_vec1           =    1'b1;
                            c1_flag_next             =    !c1_flag;
                            incr_fail_ctr            =    1'b1;
                        end else begin
                            clear_fail_ctr           =    1'b1;
                        end
                    end
                    2'b10: begin
                        if(c2_flag==0) begin
                            prev_error_flip          =    2'sb01;
                            hi_prev_error_flipped    =    19'sd32;
                        end else begin
                            prev_error_flip          =    2'sb11;
                            hi_prev_error_flipped    =    -19'sd32;
                        end
                        load_step_vec2               =    1'b1;
                    end
                    2'b11: begin
                        if(c2_flag==0) begin
                            prev_error_flip          =    2'sb11;
                            hi_prev_error_flipped    =    -19'sd32;
                        end else begin
                            prev_error_flip          =    2'sb01;
                            hi_prev_error_flipped    =    19'sd32;
                        end
                        if(curr_error_gte_prev_error && burn)    begin
                            load_step_vec2           =    1'b1;
                            c2_flag_next             =    !c2_flag;
                            incr_fail_ctr            =    1'b1;
                        end else begin
                            clear_fail_ctr           =    1'b1;
                        end
                        
                        load_lna_gain                =    1'b1;
                        
                        case(lna_gain_state)
                            2'b00: begin
                                if(curr_error_gt_16383)    begin
                                    reset_cap_state_next    =    1'b1;
                                end else if (!curr_error_gt_255) begin
                                    lna_gain_state_next     =    2'b01;
                                    lna_gain_change_next    =    1'b1;
                                end
                            end
                            2'b01: begin
                                if(curr_error_gt_2047)    begin
                                    lna_gain_state_next     =    2'b00;
                                    lna_gain_change_next    =    1'b1;
                                end else if (!curr_error_gt_31) begin
                                    lna_gain_state_next     =    2'b10;
                                    lna_gain_change_next    =    1'b1;
                                end
                            end
                            2'b10: begin
                                if(curr_error_gt_127)    begin
                                    lna_gain_state_next     =    2'b01;
                                    lna_gain_change_next    =    1'b1;
                                end
                            end
                            2'b11: begin
                                if(curr_error_gt_127)    begin
                                    lna_gain_state_next     =    2'b01;
                                    lna_gain_change_next    =    1'b1;
                                end    else begin
                                    lna_gain_state_next     =    2'b10;    //We only get here if a bit gets flipped, so put the system back in its correct state. This can be removed to save LUT if need be.
                                end
                            end
                        endcase
                    end
                endcase
            end
            
            STATE_STEP_VEC_LATCH: begin
                state_next            =    STATE_COMPUTE1;
                case(loop_mode)
                    2'b00: begin
                        latch_step_vec1            =    1'b1;
                    end
                    2'b01: begin
                        if(curr_error_gte_prev_error && burn)    begin
                            latch_step_vec1        =    1'b1;
                        end
                    end
                    2'b10: begin
                        latch_step_vec2            =    1'b1;
                    end
                    2'b11: begin
                        if(curr_error_gte_prev_error && burn)    begin
                            latch_step_vec2        =    1'b1;
                        end
                    end
                endcase
            end
                        
            STATE_COMPUTE1: begin
                case(loop_mode)
                    2'b00: begin    loop_mode_next    =    2'b01;    end
                    2'b01: begin    loop_mode_next    =    2'b10;    end
                    2'b10: begin    loop_mode_next    =    2'b11;    end
                    2'b11: begin    loop_mode_next    =    2'b00;    burn_next    =    1'b1; end
                endcase
                if(!curr_error_gt_23 && lna_gain_state[1]==1'b1 && burn_higain)      //AHA - this is where we turn off all SPI activity when error gets low enough. But still we should turn off LNA gain when we can.
                    state_next                =    STATE_IDLE;                       //burn_higain ensures that have at least one run-thru at high gain prior to shutting down SPI
                else
                    state_next                =    STATE_ASSERT_SPI_RDY0;            // At the end of this cycle, initial matrix computation will be done
                    
                //If we've latched in a double-step due to fail counter, this should be a safe place to clear the fail counter

                if(fail_ctr == 3'd7)
                    clear_fail_ctr    =    1'b1;
            end
            
            STATE_ASSERT_SPI_RDY0: begin
                spi_data_csel            =    1'b0;
                spi_data_rdy_next        =    1'b1;                                // This signal must come from a flop
                spi_data_out             =    {{3{1'b0}},state_cap1[14:10]};
                if(!spi_ack)                                                       // Needed because latency of ACK falling is 4 clk_4p5
                    state_next           =    STATE_WAIT_SPI_RDY0;
            end
            
            STATE_WAIT_SPI_RDY0: begin
                spi_data_csel            =    1'b0;
                spi_data_out             =    {{3{1'b0}},state_cap1[14:10]};
                
                if(spi_ack)    begin                                               // Remember to double sync this ack signal    
                    spi_data_rdy_next    =    1'b0;
                    if(lna_gain_change) begin
                        state_next       =    STATE_ASSERT_SPI_RDY1;
                    end else begin
                        state_next       =    STATE_IDLE;                          // No sending SPI data to SX1257 unless we need to
                    end
                end else begin
                    spi_data_rdy_next    =    1'b1;
                end
            end
            
            STATE_ASSERT_SPI_RDY1: begin                                           // This changes the Rx gain of the radio
                spi_data_csel            =    1'b1;                                // In the future perhaps do not always send this. IT IS NOW THE FUTURE!!!!
                spi_data_rdy_next        =    1'b1;                                // This signal must come from a flop
                
                case(lna_gain_state)
                    2'b00: begin    
                        spi_data_out        =    LO_GAIN_SETTING; 
                        burn_higain_next    =    1'b0;
                    end
                    2'b01: begin    
                        spi_data_out        =    MD_GAIN_SETTING; 
                        burn_higain_next    =    1'b0;
                    end
                    2'b10: begin
                        spi_data_out        =    HI_GAIN_SETTING;
                        burn_higain_next    =    1'b1;
                    end
                    2'b11: begin
                        spi_data_out        =    HI_GAIN_SETTING;
                        burn_higain_next    =    1'b1;
                    end
                endcase
                
                if(!spi_ack)
                    state_next              =    STATE_WAIT_SPI_RDY1;
            end
            
            STATE_WAIT_SPI_RDY1: begin
                spi_data_csel               =    1'b1;
                
                case(lna_gain_state)
                    2'b00: begin    spi_data_out        =    LO_GAIN_SETTING; end
                    2'b01: begin    spi_data_out        =    MD_GAIN_SETTING; end
                    2'b10: begin
                        spi_data_out        =    HI_GAIN_SETTING;
                        burn_higain_next    =    1'b1;
                    end
                    2'b11: begin
                        spi_data_out        =    HI_GAIN_SETTING;
                        burn_higain_next    =    1'b1;
                    end
                endcase
                
                if(spi_ack)    begin                          // Remember to double sync this ack signal
                    spi_data_rdy_next    =    1'b0;
                    state_next           =    STATE_IDLE;
                end else begin
                    spi_data_rdy_next    =    1'b1;
                end
            end
            
            STATE_DUMMY_10: begin
                state_next    =    STATE_IDLE;
            end
            
            STATE_DUMMY_11: begin
                state_next    =    STATE_IDLE;
            end
            
            STATE_DUMMY_12: begin
                state_next    =    STATE_IDLE;
            end
            
            STATE_DUMMY_13: begin
                state_next    =    STATE_IDLE;
            end
            
            STATE_DUMMY_14: begin
                state_next    =    STATE_IDLE;
            end
            
            STATE_DUMMY_15: begin
                state_next    =    STATE_IDLE;
            end
            
        endcase
    end
    
    always @(posedge clk_4p5 or negedge rst_n) begin
        
        if(!rst_n) begin
            state_curr             <=    STATE_IDLE;
            spi_data_rdy           <=    1'b0;
            loop_mode              <=    2'b0;
            state_cap1             <=    15'd16384; //No longer reset on each go radio - current cvg is too slow to allow this
            state_cap2             <=    15'd16384; //No longer reset on each go radio - current cvg is too slow to allow this
            dc_in_i_store          <=    16'sd0;
            dc_in_q_store          <=    16'sd0;
            curr_error_gt_16383    <=    1'b0; //Was 0, all of these
            curr_error_gt_2047     <=    1'b0;
            curr_error_gt_255      <=    1'b0;
            curr_error_gt_127      <=    1'b0;
            curr_error_gt_31       <=    1'b0;
            curr_error_gt_23       <=    1'b0;
            step_vec1              <=    18'sb0;
            step_vec2              <=    18'sb0;
            burn                   <=    1'b0;
            c1_flag                <=    1'b0;
            c2_flag                <=    1'b0;
            prev_error             <=    18'b0;
            burn_higain            <=    1'b0;
            fail_ctr               <=    3'b0;
            lna_gain_state         <=    2'b00;
            lna_gain_change        <=    1'b0;
            reset_cap_state        <=    1'b0;
        end    else    begin

            state_curr             <=    state_next;
            spi_data_rdy           <=    spi_data_rdy_next;
            loop_mode              <=    loop_mode_next;
            c1_flag                <=    c1_flag_next;
            c2_flag                <=    c2_flag_next;

            if(go_radio) begin
                burn               <=    1'b0;
                burn_higain        <=    1'b0;
            end else begin
                burn               <=    burn_next;
                burn_higain        <=    burn_higain_next;
            end

            if(clear_fail_ctr) begin
                fail_ctr           <=    3'b0;
            end else if(incr_fail_ctr && !(fail_ctr == 3'd7)) begin
                fail_ctr           <=    fail_ctr+3'd1;
            end
            
            if(load_step_vec1 && burn) begin
                if(!lna_gain_state[1])
                    step_vec1      <=    prev_error_fail_boost[17:0]; //Was 17:0 - reduced to avoid chattering 
                else
                    step_vec1      <=  hi_prev_error_fail_boost[17:0];
            end else if(load_step_vec2 && burn) begin
                if(!lna_gain_state[1])
                    step_vec2      <=    prev_error_fail_boost[17:0]; //Was 17:0 - reduced to avoid chattering
                else
                    step_vec2      <=  hi_prev_error_fail_boost[17:0];
            end

            if(compare_curr_err)    begin
                curr_error_gt_16383    <=    curr_error_gt_16383_next;
                curr_error_gt_2047     <=    curr_error_gt_2047_next;
                curr_error_gt_255      <=    curr_error_gt_255_next;
                curr_error_gt_127      <=    curr_error_gt_127_next;
                curr_error_gt_31       <=    curr_error_gt_31_next;
                curr_error_gt_23       <=    curr_error_gt_23_next;
            end
            
            if(load_prev_error)    begin
                prev_error             <=    curr_error;
            end

            if(latch_step_vec1) begin
                if(reset_cap_state)    begin
                    state_cap1 <= 15'd16384;
                end else if (!(!curr_error_gt_23 && lna_gain_state[1]) && burn) begin
                    state_cap1         <=    state_cap1_next_sat[14:0];
                end
            end else if(latch_step_vec2) begin
                if(reset_cap_state)    begin
                    state_cap2 <= 15'd16384;
                end else if (!(!curr_error_gt_23 && lna_gain_state[1]) && burn) begin
                    state_cap2         <=    state_cap2_next_sat[14:0];
                end
            end
                
            
            if(go_radio) begin
                lna_gain_state         <=    2'b00;
            end else if(load_lna_gain) begin
            //if(load_lna_gain) begin
                lna_gain_state         <=    lna_gain_state_next;
                lna_gain_change        <=    lna_gain_change_next;
                reset_cap_state        <=    reset_cap_state_next;
            end
                
            if(dc_in_reg_store)    begin
                dc_in_i_store          <=    dc_in_i;
                dc_in_q_store          <=    dc_in_q;
            end
            
        end
    end
endmodule

