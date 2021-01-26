////////////////////////////////////////////////////////////////////////////////////
//                                                                                //
// Module : RX Clock Recovery Top Level Unit (one total for I and Q channels)     //
//                                                                                //
// Filename: clk_rcvy.v                                                           //
// Creation Date: 12/1/2015                                                       //
// Author: Edward Keehr                                                           //
//                                                                                //
// Copyright Superlative Semiconductor LLC 2021                                   //
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2    //
// You may redistribute and modify this documentation and make products           //
// using it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl).       //
// This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED               //
// WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY                   //
// AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-P v2             //
// for applicable conditions.                                                     //
//                                                                                //
// Description:                                                                   //
//        This is the top level of the clock recovery circuit                     //
//                                                                                //
//    Revisions:                                                                  //
//                                                                                //
////////////////////////////////////////////////////////////////////////////////////

module clk_rcvy
    (
        // Inputs
        input    wire                    data,
        input    wire                    clk,
        input    wire                    rst_n,
        // Outputs
        output    reg                    clk_zero_xing
    );
    
    // Parameter and localparam declarations
    //    Register and wire declarations
    
    wire    signed    [16:0]    tank_lsb;
    wire    signed    [3:0]    period;
    wire    signed    [1:0]    freq_delta;
    wire    signed    [2:0]    phase_delta;
    
    //    wire            [3:0]        phI_edge;                // Not used, gives a warning so we cut it out
    wire              [3:0]    phIb_edge;
    wire              [3:0]    phIb_edgeB;
    wire              [3:0]    phQ_edge;
    wire              [3:0]    phQb_edge, phQb_edge_pre1, phQb_edge_pre2;
    wire    signed    [10:0]   state_next_pre;
    wire    signed    [9:0]    state_next;
    reg     signed    [5:0]    phase_delta_counter_next;
    wire                       data_delta;
    
    reg                        clk_phI_pulse;
    reg                        clk_phQ_pulse;
    reg                        clk_phIb_pulse;
    reg                        clk_phIb_pulseB;
    reg                        clk_phQb_pulse;
    reg                        clk_period_pulse;
    
    reg               [3:0]    counter, counter_next;
    reg     signed    [5:0]    phase_delta_counter;
    reg     signed    [9:0]    state;
    reg                        data_edge_block, data_edge_block_next;
    reg                        data_edge;
    reg                        data_prev;
    
    // Module declarations
    
    signed_saturate
        #(
            .WIDTH_IN(10),
            .WIDTH_OUT(9)
        )
    sat1
        (
            .in     (state_next_pre),
            .out    (state_next)
        );
    
    cr_phase_det    cr_phase_det
        (
            .data               (data),
            .clk                (clk),
            .rst_n              (rst_n),
            .clkIph             (clk_phI_pulse),
            .clkIbph            (clk_phIb_pulseB),
            .phase_delta        (phase_delta)
        );
        
    cr_freq_det    cr_freq_det
        (
            .data_edge          (data_edge),
            .clk                (clk),
            .rst_n              (rst_n),
            .phI_edge           (clk_phI_pulse),    // Update frequency on the second cycle of the period, using the old period and edge values
            .phQ_edge           (clk_phQ_pulse),
            .phIb_edge          (clk_phIb_pulse),
            .phQb_edge          (clk_phQb_pulse),
            .out                (freq_delta)
        );
        
    cr_period_sdm    cr_period_sdm
        (
            .tank_lsb           (tank_lsb),
            .clk                (clk),
            .clk_mask           (clk_period_pulse),    // Finally, update period on the final cycle of the period, before the counter comparison is made to period
            .rst_n              (rst_n),
            .period             (period)
        );
        
    // Combinational logic - assign statements

    //    assign    phI_edge                =    1;                                                    //Not used, gives a warning so we cut it out
    assign    phQ_edge                    =    {{2{1'b0}},period[3:2]};                                //Implement floor(period/4)
    assign    phIb_edge                   =    {1'b0,period[3:1]};                                        //Implement floor(0.5*period) - Minimum value is 5
    assign    phIb_edgeB                  =    {1'b0,period[3:1]}+{3'b000,1'b1};                        //Implement floor(0.5*period)+1 - Minimum value is 5
    assign    phQb_edge_pre1              =    {1'b0,period[3:1]}+{2'b00,period[3:2]};                 //Implement floor(0.75*period)
    assign    phQb_edge                   =    phQb_edge_pre1+{3'b000,period[1] && period[0]};            //Lattice compiler wants the computation to be split up
    
    // Shift 'edges all one clock cycle early
    
    //assign    phQ_edge                  =    {{2{1'b0}},period[3:2]}-{3'b000,1'b1};                //Implement floor(period/4)-1
    //assign     phIb_edge                =    {1'b0,period[3:1]}-{3'b000,1'b1};                    //Implement floor(0.5*period)-1 - Minimum value is 5
    //assign     phIb_edgeB               =    {1'b0,period[3:1]};                                    //Implement floor(0.5*period) - Minimum value is 5
    //assign    phQb_edge_pre1            =    {1'b0,period[3:1]}-{3'b000,1'b1};                     //Implement floor(0.75*period)-1
    //assign    phQb_edge_pre2            =    {2'b00,period[3:2]}+{3'b000,period[1] && period[0]};//Lattice compiler wants the computation to be split up
    //assign    phQb_edge                 =    phQb_edge_pre1+phQb_edge_pre2;
    
    assign    state_next_pre              =    {state[9],state}+{{8{phase_delta[2]}},phase_delta}+{{8{freq_delta[1]}},freq_delta,1'b0}; //A 11 bit [10:0] signal pre-saturation, 10 bit after.
    assign    tank_lsb                    =    {{1{phase_delta_counter_next[5]}},phase_delta_counter_next,10'b0}+{{1{state_next[9]}},state_next,6'b0};    //A 17 bit signal
    assign    data_delta                  =    data ^ data_prev;
    //assign    phase_delta_counter_next    =    phase_delta_counter+{{3{phase_delta[2]}},phase_delta};    //Phase delta can be either +/- 2 for 14 cycles, so phase delta is 3 bits and phase delta counter is 6 bits signed
    
    //    Combinational logic - conditional assignments

    always @(*)
        begin
            // Defaults
            clk_phI_pulse                =    1'b0;
            clk_phQ_pulse                =    1'b0;
            clk_phIb_pulse               =    1'b0;
            clk_phIb_pulseB              =    1'b0;
            clk_phQb_pulse               =    1'b0;
            clk_period_pulse             =    1'b0;
            clk_zero_xing                =    1'b0;
            phase_delta_counter_next     =    phase_delta_counter+{{3{phase_delta[2]}},phase_delta};
            
            counter_next                 =    counter+4'b1;  
            data_edge_block_next         =    data_edge_block;
            
            // Conditional cases where defaults do not apply.
            if(data_delta && !data_edge_block) begin
                data_edge                =    1'b1;
                data_edge_block_next     =    1'b1;
            end else begin
                data_edge                =    1'b0;
            end
            
            if(counter == 4'b1)    begin
                clk_zero_xing            =    1'b1;
                phase_delta_counter_next =    {{3{phase_delta[2]}},phase_delta};
            end
            
            if(counter == phQ_edge) begin
                clk_phQ_pulse            =    1'b1;
            end
            
            if(counter == phIb_edge) begin
                clk_phIb_pulse           =    1'b1;
            end
            
            if(counter == phIb_edgeB) begin
                clk_phIb_pulseB          =    1'b1;
            end
            
            if(counter == phQb_edge) begin
                clk_phQb_pulse           =    1'b1;
            end
            
            if(counter == period)    begin
                clk_phI_pulse            =    1'b1;
                clk_period_pulse         =    1'b1;
                counter_next             =    4'b1;
                data_edge_block_next     =    1'b0;
            end
        end
        
    // Infer flops
    
    always @(posedge clk or negedge rst_n)
        begin
            if(!rst_n)    begin
                counter             <=     4'd1;
                phase_delta_counter    <=     6'sd0;
                data_prev            <=    1'b0;
                data_edge_block        <=    1'b0;
                state                <=    10'b0;
            end else begin
                counter                <=     counter_next;
                data_prev            <=    data;
                data_edge_block        <=    data_edge_block_next;
                state                <=    state_next;
                phase_delta_counter    <=    phase_delta_counter_next;                
            end
        end
        
    endmodule
                    