//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
// Module : RX Waveform Storage                                                     //
//                                                                                  //
// Filename: wave_storage.v                                                         //
// Creation Date: 1/8/2016                                                          //
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
//    This block fills all of the unused RAM on the FPGA with stored SX1257 wave    //
// output in 1-bit sigma-delta output format (arguably the most compressed)         //
//    This block takes as input a "go" signal from the radio_fsm to start           //
//    recording, and an "offset" signal from control register data. This allows     //
// waveform recording to occur using a sliding window, important since we can       //
// only capture about 1.5ms of I/Q data at any given time.                          //
//                                                                                  //
//    Right now, we will make a go of it with just the 36 and 55 MHz clocks.        //
//                                                                                  //
//    Revisions:                                                                    //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

module wave_storage
    (
        // Inputs
        input    wire                in_i, in_q,
        input    wire                clk_27p5,
        input    wire                clk_36,
        input    wire                rst_n,
        input    wire                go,
        input    wire    [23:0]      wait_offset,
        input    wire                clk_27p5_en,
        input    wire    [12:0]      address,
        // Outputs
        output    wire    [7:0]      out,
        output    reg                done,
        output    reg                running
    );

    // Parameter and localparam declarations
    
    localparam    MEM_SAMPLE_DEPTH    =    16'd32767; // One sample = one sample of i and q data. There are 81920 bits available in RAM.
    
    localparam    STATE_DONE          =    2'd0;
    localparam    STATE_WAIT          =    2'd1;
    localparam    STATE_SHIFT         =    2'd2;
    localparam    STATE_LOAD          =    2'd3;
    
    // Register and wire declarations
    
    wire                rst_p;
    
    reg    [7:0]        shift_reg_next, shift_reg;
    reg    [24:0]       wait_idx_next, wait_idx;
    reg    [14:0]       smpl_idx_next, smpl_idx;
    reg    [1:0]        state_next, state;
    reg    [1:0]        load_ctr_next, load_ctr;
    reg                 wait_idx_clear, smpl_idx_clear, load_ctr_clear, wrclocken, wren;
    reg    [12:0]       wraddress;
    
    // Instantiated modules
    
    wave_storage_ram wave_ram(
        .data(shift_reg),
        .rd_aclr(rst_p),
        .rdaddress({1'b0,address}),
        .rdclock(clk_27p5),
        .rdclocken(clk_27p5_en),
        .wraddress({1'b0,wraddress}),
        .wrclock(clk_36),
        .wrclocken(wrclocken),
        .wren(wren),
        .q(out)
    );
    
    // Combinational logic assignments
    
    assign rst_p    =    ~rst_n;
    
    // Combinational logic block for the state machine

    always @(*) begin
        
        // Defaults
        
        shift_reg_next    =    {in_q,in_i,shift_reg[7:2]};        //We may actually save LUT if we break this up into two 1-bit shift registers and interleave the outputs
        done              =    1'b0;
        running           =    1'b1;
        wait_idx_next     =    wait_idx+24'd1;
        smpl_idx_next     =    smpl_idx+15'd1;
        state_next        =    state;
        load_ctr_next     =    load_ctr+2'b01;
        wait_idx_clear    =    1'b1;
        smpl_idx_clear    =    1'b1;
        load_ctr_clear    =    1'b1;
        wraddress         =    smpl_idx[14:2];
        wrclocken         =    1'b0;
        wren              =    1'b0;
        
        case(state)
        
            STATE_DONE: begin
                done       =    1'b1;
                running    =    1'b0;
                if(go)    begin
                    state_next    =    STATE_WAIT;
                end
            end
            
            STATE_WAIT: begin
                wait_idx_clear    =    1'b0;
                
                if(wait_idx >= wait_offset)
                    state_next    =    STATE_SHIFT;
            end
            
            STATE_SHIFT: begin
            
                smpl_idx_clear    =    1'b0;
                load_ctr_clear    =    1'b0;
                wrclocken         =    1'b1;
            
                if(smpl_idx >= MEM_SAMPLE_DEPTH) begin
                    state_next    =    STATE_DONE;
                end else if(load_ctr    ==    2'b10) begin
                    state_next    =    STATE_LOAD;
                end
            
            end
            
            STATE_LOAD: begin
            
                smpl_idx_clear    =    1'b0;
                load_ctr_clear    =    1'b0;
                wren              =    1'b1;
                wrclocken         =    1'b1;
                
                if(smpl_idx >= MEM_SAMPLE_DEPTH) begin
                    state_next    =    STATE_DONE;
                end else begin
                    state_next    =    STATE_SHIFT;
                end
            
            end
        endcase
    end
            

    // Flops inference
    
    always @(posedge clk_36 or negedge rst_n)    begin
        if(!rst_n)    begin
            wait_idx        <=    24'b0;
            smpl_idx        <=    15'b0;
            load_ctr        <=    2'b0;
            state           <=    STATE_DONE;
            shift_reg       <=    8'b0;
        end  else    begin
            if(wait_idx_clear)
                wait_idx    <=    24'b0;
            else
                wait_idx    <=    wait_idx_next;
            if(smpl_idx_clear)
                smpl_idx    <=    15'b0;
            else
                smpl_idx    <=    smpl_idx_next;
            if(load_ctr_clear)
                load_ctr    <=    2'b0;
            else
                load_ctr    <=    load_ctr_next;
            
            state           <=    state_next;
            shift_reg       <=    shift_reg_next;
        end
    end
endmodule
