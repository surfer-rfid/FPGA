/////////////////////////////////////////////////////////////////////////////////////////
//                                                                                     //
// Module : Clock Management                                                           //
//                                                                                     //
// Filename: clk_mgmt.v                                                                //
// Creation Date: 1/12/2016                                                            //
// Author: Edward Keehr                                                                //
//                                                                                     //
// Copyright Superlative Semiconductor LLC 2021                                        //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2         //
// You may redistribute and modify this documentation and make products                //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).            //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED                    //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                        //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2                  //
// for applicable conditions.                                                          //
//                                                                                     //
// Description:                                                                        //
//                                                                                     //
//    This block contains all of the clock management circuitry. In this file,         //
//    we try to do things the 'right' way first, then may try to reduce LUT count      //
// if we really need to.                                                               //
//                                                                                     //
//    36MHz clock failure detection circuit: We implement a circuit to detect          //
// when the SX1257 clock fails. When this happens, the clk_36 and clk_4p5 are          //
// gated off until they are running again and are enabled by the micro-                //
// controller                                                                          //
//                                                                                     //
// Dividers: done to minimize master clock to slave clock skew. Only one               //
// clk-Q delay is present.                                                             //
//                                                                                     //
//    Revisions:                                                                       //
//    022216 - Switched clk 55/27.5 to 48/24 for iCE40 Ultra                           //
//    Why not get rid of the division from 48 to 24? Because at the moment we use      //
//    the faster 48MHz clock to check for the presence of the 36Mhz clock using        //
//    a technique which assumes that the guarantted clock is faster.                   //
//                                                                                     //
//                                                                                     //
//    032416 - Switch it back.                                                         //
//    080516 - Switch valid and running signals to be defined by state, not            //
//    state transitions. Define an IRQ signal for when clk_36_in becomes valid         //
//    and invalid. This is important because if the clk_36 just stops then so will     //
//    the rfidr state machine during a radio transaction and the MCU will need to      //
//    take corrective action. This IRQ can be asserted whenever clk_36_valid changes,  //
//    so it should only take 1 LUT and we define it in code outside of the code        //
//    blocks already defined.                                                          //
//    Added a dummy state in the state machine for good practice.                      //
//    Found out that the clock gating lets one clock cycle slip through the gating     //
//    while the clocks are disabled provided that the clocks stopped while they        //
//    were low. Decided to leave this in place to speed up design.                     //
//    Even if this clock does something funny, normal SW procedure will probably       //
//    be to reset the entire 4p5/36 domain after a clock halt.                         //
//                                                                                     //
//    081916 - Fix bug in which signals sent back to the MCU interface were            //
//    clocked off of clk_55 instead of clk_27p5                                        //
//                                                                                     //
/////////////////////////////////////////////////////////////////////////////////////////


module clk_mgmt(
    //Inputs
    input        wire        clk_36_in,
    input        wire        clk_36_start,            //Needs to come from spi.v
    input        wire        rst_n_4p5,
    input        wire        rst_n_27p5,
    input        wire        rst_n_36_in,
    input        wire        rst_n_36,
    input        wire        rst_n_55,
    //Outputs
    output       wire        clk_36,
    output       wire        clk_4p5,
    output       wire        clk_4p5_stretch_en,
    output       reg         clk_36_valid_reg,        //Needs to go to spi.v. This signal means that we have a valid clock from the SX1257.
    output       reg         clk_36_running_reg,      //Needs to go to spi.v. This signal means that the internal 36MHz clock is running. It is delayed somewhat from the actual state machine.
    output       wire        clk_36_irq,              //Needs to go to rfdir_fsm.v. This signal informs 
    output       wire        clk_27p5,
    output       wire        clk_55
);

//Params and localparams

localparam    STATE_CLK_36_LO_INACTIVE    =    3'b000;
localparam    STATE_CLK_36_HI_INACTIVE    =    3'b001;
localparam    STATE_CLK_36_LO_PRELIM      =    3'b010;
localparam    STATE_CLK_36_HI_PRELIM      =    3'b011;
localparam    STATE_CLK_36_LO_ACTIVE      =    3'b100;
localparam    STATE_CLK_36_HI_ACTIVE      =    3'b101;
localparam    STATE_DUMMY_1               =    3'b110;
localparam    STATE_DUMMY_2               =    3'b111;

//Internal wire

wire            clk_4p5_unbuf;

//Internal regs

reg    [2:0]       state_next, state;
//reg    [2:0]     clk_4p5_div_ctr;              //Remove to try instantiation of div by 8 cell to get timing tool to work
reg                clk_27p5_rst_ctr;
reg                clk_27p5_unbuf;
reg                clk_27p5_rega;
reg                clk_27p5_regb, clk_27p5_regc;

reg                reset_active_ctr;
reg                reset_wd_timer;

reg    [2:0]       wd_timer_next,   wd_timer;
reg    [3:0]       active_ctr_next, active_ctr;

reg                clk_36_valid_old;            //Use these signals to store the clk_36_valid signal 
reg                clk_36_valid;
reg                clk_36_running;
reg                clk_36_resync_to_55_1,clk_36_resync_to_55_2;


//Modules

clk_gate_buf clk_buf_36 (
    .inclk  (clk_36_in),
    .ena    (1'b1),
    .outclk (clk_36)
);

clk_gate_buf clk_buf_4p5 (
    .inclk  (clk_4p5_unbuf),
    .ena    (1'b1),
    .outclk (clk_4p5)
);

clk_gate_buf clk_buf_27p5 (
    .inclk(clk_27p5_unbuf),
    .ena(1'b1),
    .outclk(clk_27p5)
);    

internal_osc osc_55mhz (
    .oscena (1'b1),
    .clkout (clk_55)
);

// Run dividers to create 4.5MHz clk from 36 MHz clk
// We don't reset the division counter here because we would need the 27p5MHz clock toggling to release the reset
// but we would need the reset released for the clock to toggle.

clk_mgmt_div_by_8 u_clk_mgmt_div_by_8_0 (
    .clk_36_in(clk_36),
    .rst_n_36_in(rst_n_36),
    .clk_4p5_unbuf_out(clk_4p5_unbuf),
    .clk_4p5_stretch_en(clk_4p5_stretch_en)
);

assign    clk_36_irq = clk_36_valid_old && !clk_36_valid_reg;    //Assert an IRQ when the clock is detected to have stopped

// Run dividers to create 27p5MHz clk from 55MHz clk
// We don't reset the division counter here because we would need the 27p5MHz clock toggling to release the reset
// but we would need the reset released for the clock to toggle.
// 081016 - But doing this leaves a problem for simulation in that the state of the clock is not defined.
// So we can check for a reset that is synced with clk_55
// We just stop the clock when we see the reset.
// When the reset is deasserted, wait for the next clk_55 edge then set clock to zero.
// Have a flag variable that exits this out-of-reset state after one cycle to resume normal clock division operation.
        
always @(posedge clk_55 or negedge rst_n_55) begin
    if(!rst_n_55) begin
        clk_27p5_rst_ctr    <=    1'b0;                    //If a reset occurs, freeze the clock
        clk_27p5_unbuf      <=    1'b0;
        clk_27p5_rega       <=    1'b0;
    end else begin
        if(clk_27p5_rst_ctr == 1'b0) begin                 //Once the reset has deasserted, on the first clock cycle out, set the clock to zero. Either this makes a proper 1,0 or a long 0,0
            clk_27p5_unbuf      <=    1'b0;
            clk_27p5_rega       <=    1'b0;
            clk_27p5_rst_ctr    <=    1'b1;                //Set the reset counter to 1 so that in the following cycle, we resume proper clock division.
        end else begin
            clk_27p5_unbuf      <=    !(clk_27p5_unbuf | clk_27p5_rega);
            clk_27p5_rega       <=    clk_27p5_unbuf;
        end
    end
end

always @(posedge clk_55 or negedge rst_n_55) begin
    if(!rst_n_55)    begin
        clk_36_resync_to_55_1    <=    1'b0;
        clk_36_resync_to_55_2    <=    1'b0;
    end else begin
        clk_36_resync_to_55_1    <=    clk_36_in;
        clk_36_resync_to_55_2    <=    clk_36_resync_to_55_1;
    end
end

// Detect whether clk_36 is actually running or not
// In general, clk_36 is guaranteed to toggle at least every other clk_55 cycle
// If it does not, we say that the clock is dead

always @(*)    begin

    wd_timer_next       =    wd_timer+3'b1;
    active_ctr_next     =    active_ctr;
    reset_active_ctr    =    1'b0;
    reset_wd_timer      =    1'b0;
    clk_36_running      =    1'b0;                                //These output variables should be based on state, not state transitions.
    clk_36_valid        =    1'b0;                                //The reason is that they correspond directly to the defined states!
    state_next          =    state;

    case(state)
        STATE_CLK_36_LO_INACTIVE: begin
            if(wd_timer    > 3'd3)    begin                             //Watchdog timer is set to expire if 4 clk55 edges have been seen without a change in clk_36_in.
                reset_active_ctr        =    1'b1;                      //In reality it can be set to expire at 3 clk55 edges, but this provides some margin against jitter.
            end
            if(clk_36_resync_to_55_2 ==    1'b1) begin
                reset_wd_timer          =    1'b1;                      //We saw an edge, so reset the watchdog timer.
                active_ctr_next         =    active_ctr+4'b1;           //Wait for 8 clean edges before declaring this clk_36_in valid 
                if(active_ctr    > 4'd7)    begin                       //We declare clk_in_valid.
                    state_next          =    STATE_CLK_36_HI_PRELIM;    //Move to a state where we wait for the MCU to enable the clock.
                    reset_active_ctr    =    1'b1;
                end else
                    state_next          =    STATE_CLK_36_HI_INACTIVE;  //We saw a high edge, so now wait for a low edge. Still waiting for enough edges to declare the clock valid
            end
        end
        
        STATE_CLK_36_HI_INACTIVE: begin
            if(wd_timer    > 3'd3)    begin
                reset_active_ctr        =    1'b1;
            end
            if(clk_36_resync_to_55_2 ==    1'b0) begin
                reset_wd_timer          =    1'b1;
                active_ctr_next         =    active_ctr+4'b1;
                if(active_ctr    > 4'd7) begin
                    state_next          =    STATE_CLK_36_LO_PRELIM;
                    reset_active_ctr    =    1'b1;
                end else
                    state_next          =    STATE_CLK_36_LO_INACTIVE;
            end
        end
    
        STATE_CLK_36_LO_PRELIM:    begin                                //These two states represent the states in which the input 36MHz clock had been deemed valid and
            clk_36_valid                =    1'b1;                      //we are waiting for a clock 'power-on' from the MCU.
            if(wd_timer    > 3'd3)    begin                             //As such, the input clock still needs to be monitored and any inactivity forces a return
                state_next              =    STATE_CLK_36_LO_INACTIVE;  //to the clock inactive state.
                reset_wd_timer          =    1'b1;
            end
            if(clk_36_resync_to_55_2 ==    1'b1) begin
                reset_wd_timer          =    1'b1;
                state_next              =    STATE_CLK_36_HI_PRELIM;
            end
        end
        
        STATE_CLK_36_HI_PRELIM:    begin
            clk_36_valid                =    1'b1;
            if(wd_timer    > 3'd3)    begin
                state_next              =    STATE_CLK_36_HI_INACTIVE;
                reset_wd_timer          =    1'b1;
            end
            if(clk_36_resync_to_55_2 ==    1'b0) begin
                reset_wd_timer          =    1'b1;
                state_next              =    STATE_CLK_36_LO_PRELIM;
            end
        end
        
        STATE_CLK_36_LO_ACTIVE:    begin                                //These two states represent the states in which the MCU had signaled to enable the  
            reset_wd_timer              =    1'b1;                      //internal 36Mhz clock. In this case, we set the 36MHz clock to be running.
            reset_active_ctr            =    1'b1;                      //It will take a few clock cycles to actually start running, since there is a 
            if(clk_36_resync_to_55_2    ==   1'b0)                      //set of resync flops. 
                state_next              =    STATE_CLK_36_LO_INACTIVE;
        end
                
        STATE_CLK_36_HI_ACTIVE:    begin
            reset_wd_timer              =    1'b1;
            reset_active_ctr            =    1'b1;
            if(clk_36_resync_to_55_2    ==   1'b0)
                state_next              =    STATE_CLK_36_LO_INACTIVE;
        end        

        STATE_DUMMY_1: begin                                           //If we get into a bad state - something has gone terribly wrong.
            reset_wd_timer              =    1'b1;                     //Reset all timers and go back to the state where input clock is presumed invalid.
            reset_active_ctr            =    1'b1;                     //The switch from valid to invalid will trigger an IRQ to the MCU.
            if(clk_36_resync_to_55_2    ==    1'b0)
                state_next              =    STATE_CLK_36_LO_INACTIVE;
        end        
        
        STATE_DUMMY_2: begin                                           //If we get into a bad state - something has gone terribly wrong.
            reset_wd_timer              =    1'b1;                     //Reset all timers and go back to the state where input clock is presumed invalid.
            reset_active_ctr            =    1'b1;                     //The switch from valid to invalid will trigger an IRQ to the MCU.
            if(clk_36_resync_to_55_2    ==    1'b0)
                state_next              =    STATE_CLK_36_LO_INACTIVE;
        end
        
        default: begin
            reset_wd_timer              =    1'b1;
            reset_active_ctr            =    1'b1;
            if(clk_36_resync_to_55_2    ==    1'b0)
                state_next              =    STATE_CLK_36_LO_INACTIVE;
        end
    endcase
end

// Clk36 activity detection state machine flops
// This needs to be done for clock 55 because the clock detection scheme is designed for the detected clock
// running slower than the detection clock.

always @(posedge clk_55 or negedge rst_n_55) begin
    if(!rst_n_55)    begin
        state                <=    STATE_CLK_36_LO_INACTIVE;
        wd_timer             <=    3'b0;
        active_ctr           <=    4'b0;
    end
    else begin
        state                <=    state_next;
        if(reset_wd_timer)
            wd_timer         <=    3'b0;
        else
            wd_timer         <=    wd_timer_next;
        if(reset_active_ctr)
            active_ctr       <=    4'b0;
        else
            active_ctr       <=    active_ctr_next;
    end
end

//Register signals going out to the MCU interface on the 27.5 MHZ clock
//Two of the three input signals are generated on clk_55 but since it is 
//synchronous with clk_27p5 this should be OK.

//Proper design technique is to stretch the signal using clk55 prior to 
//sampling with the slower clock
//But this only potentially improves timing margin.
//Timing margin likely OK as-is for such a small set of signals.


always @(posedge clk_27p5 or negedge rst_n_27p5) begin
    if(!rst_n_27p5)    begin
        clk_36_valid_reg     <=    1'b0;
        clk_36_running_reg   <=    1'b0;
        clk_36_valid_old     <=    1'b0;
    end else begin
        clk_36_running_reg   <=    clk_36_valid;
        clk_36_valid_reg     <=    clk_36_valid;
        clk_36_valid_old     <=    clk_36_valid_reg;
    end
end

endmodule