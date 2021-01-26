/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
// Module: IRQ Merging and Pulse Stretching                                        //
//                                                                                 //
// Filename: irq_merge.v                                                           //
// Creation Date: 8/19/2015                                                        //
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
// Description: This function merges the fsm_irq, clock_stop_irq,                  //
// and spi_master_irq into the IRQ pin.                                            //
// Furthermore, the IRQ pulse is lengthened in case the MCU has                    //
// trouble seeing it.                                                              //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

module irq_merge(
    input    wire    irq_fsm,
    input    wire    irq_clock,
    input    wire    irq_spi,
    input    wire    irq_extra,
    input    wire    clk_27p5,
    input    wire    rst_n_27p5,
    output   reg     mcu_irq
);

localparam    STATE_IDLE=1'b0;
localparam    STATE_ASRT=1'b1;

wire                 irq_merge;
reg                  state, state_next, counter_clr, mcu_irq_next;
reg        [2:0]     counter;

assign    irq_merge    =    irq_fsm || irq_clock || irq_spi || irq_extra;

always @(*) begin
    //Defaults
    state_next        =    state;
    counter_clr       =    1'b1;
    mcu_irq_next      =    1'b0;

    case(state)
        STATE_IDLE: begin
            if(irq_merge)
                state_next    =    STATE_ASRT;
        end
        STATE_ASRT: begin
            mcu_irq_next    =    1'b1;
            counter_clr     =    1'b0;
            if(counter > 3'd3)
                state_next    =    STATE_IDLE;
        end
    endcase
end

//This behavior guarantees streched pulses but we can still get a 
//minimum low time of one clock cycle.
//This is OK though because the MCU software should respond to two IRQs the same as one IRQ.
//Also, the MCU will have deglitching registers on its inputs.
//Whether it sees the low pulse or not is irrelevant to us.

always @(posedge clk_27p5 or negedge rst_n_27p5)    begin
    if(!rst_n_27p5)    begin
        counter        <=    3'b0;
        mcu_irq        <=    1'b0;
        state          <=    STATE_IDLE;
    end    else begin
        if(counter_clr)
            counter    <=    3'b0;
        else
            counter    <=    counter + 3'd1;
            
        mcu_irq        <=    mcu_irq_next;
        state          <=    state_next;
    end
end

endmodule
    
                
