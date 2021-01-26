//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
// Module : SPI Periperal and Controller Pass-Through                               //
//                                                                                  //
// Filename: spi_cntrlr.v                                                           //
// Creation Date: 3/27/2016                                                         //
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
//    This is strictly an SPI controller block: we are trying to get minimal LUT.   //
//                                                                                  //
//    Updates:                                                                      //
//    091816 - Modified to send out all DTC information at once.                    //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

module spi_cntrlr(
    //Inputs
    inout    wire                cntrlr_cipo,             //A bidirectional pin that is ordinarily tristated and used as input only when cntrlr_nps[4] is low
    
    input    wire    [7:0]       txcancel_data,           //Needs double flop synchronizer external to this block
    input    wire    [14:0]      txcancel_data_aux,       //Needs double flop synchronizer external to this block
    input    wire                txcancel_csel,           //Needs double flop synchronizer external to this block
    input    wire                txcancel_rdy,            //Needs double flop synchronizer external to this block
    
    input    wire    [7:0]       cntrlr_addr_buf,         //No need to retime, runs on 27.5 MHZ domain
    input    wire    [7:0]       cntrlr_data_buf,         //No need to retime, runs on 27.5 MHZ domain
    input    wire                cntrlr_spi_rdy,          //No need to retime, runs on 27.5 MHZ domain
    
    input    wire                clk,                     //27p5MHz clock 
    input    wire                rst_n,
    
    input    wire                radio_running,           //Needs double flop synchronizer external to this block
    
    //Outputs
    output    wire               cntrlr_nps_rdio,         //One-hot encoded since this maps to pins 4:Radio, 3-0: DTCs
    output    wire               cntrlr_nps_dtc,
    output    reg                cntrlr_pclk,
    
    output    reg                cntrlr_copi_cap3,
    output    reg                cntrlr_copi_cap2,
    output    reg                cntrlr_copi_cap1,
    output    reg                cntrlr_copi_cap0_rdio,
    
    output    reg                radio_ack,               //Assert this when txcancel_rdy is high and packet has been processed
    output    reg    [7:0]       cntrlr_rx_buf,           //No need to retime, runs on 27.5 MHZ domain
    output    reg                cntrlr_spi_pending,      //No need to retime, runs on 27.5 MHZ domain
    output    reg                cntrlr_spi_done,         //No need to retime, runs on 27.5 MHZ domain
    output    reg                irq_spi
);

    // Parameter and localparam declarations

    localparam    STATE_IDLE    =    2'd0;                //Only go to radio modes from this state, wait for previous operation to finish.
    localparam    STATE_TX      =    2'd1;
    localparam    STATE_ACK     =    2'd2;
    
    // Register declarations

    reg    [15:0]      cntrlr_tx_buf_next, cntrlr_tx_buf, cntrlr_tx_buf_load;                   //Shift register for storing radio data (Consumes only reg, not LUT as a mux would).
    reg    [7:0]       cntrlr_rx_buf_next, cap1_tx_buf, cap1_tx_buf_next, cap2_tx_buf, cap2_tx_buf_next, cap3_tx_buf, cap3_tx_buf_next;
    reg    [3:0]       cntrlr_tx_bit_cntr_next, cntrlr_tx_bit_cntr, cntrlr_tx_bit_cntr_load;    //Counter for counting the number of bits that have gone out the master
    reg    [1:0]       cntrlr_pclk_cntr_next, cntrlr_pclk_cntr;
    reg                cntrlr_copi_cap0_rdio_next, cntrlr_copi_cap1_next, cntrlr_copi_cap2_next, cntrlr_copi_cap3_next;
    reg                cntrlr_pclk_next;
    reg    [1:0]       cntrlr_nps_next, cntrlr_nps;
    reg    [1:0]       state_next, state;
    reg                cntrlr_spi_pending_next;
    reg                cntrlr_spi_done_next;
    reg                cntrlr_tx_mux_next, cntrlr_tx_mux;
    reg                load_registers;
    reg                radio_ack_next, irq_spi_next;

    // Control cntrlr_cipo_pin tristating
    
    assign    cntrlr_cipo                   =    cntrlr_nps[1] == 0 ? 1'bz : 1'b0;
    assign    cntrlr_nps_rdio               =    cntrlr_nps[1];
    assign    cntrlr_nps_dtc                =    cntrlr_nps[0];
    
    always @(*)    begin
    
        //Defaults
        
        state_next                    =    state;                    //State is flopped at the full clock rate
        cntrlr_tx_buf_next            =    cntrlr_tx_buf;
        cap1_tx_buf_next              =    cap1_tx_buf;
        cap2_tx_buf_next              =    cap2_tx_buf;
        cap3_tx_buf_next              =    cap3_tx_buf;
        cntrlr_tx_buf_load            =    {cntrlr_addr_buf,cntrlr_data_buf};
        cntrlr_tx_bit_cntr_next       =    cntrlr_tx_bit_cntr;
        cntrlr_tx_bit_cntr_load       =    4'b0;
        cntrlr_pclk_next              =    1'b0;                    //This is muxed, we don't reg it before pin
        cntrlr_rx_buf_next            =    cntrlr_rx_buf;
        cntrlr_nps_next               =    cntrlr_nps;
        //cntrlr_copi_cap3_next       =    1'b0;
        //cntrlr_copi_cap2_next       =    1'b0;
        //cntrlr_copi_cap1_next       =    1'b0;
        cntrlr_copi_cap0_rdio_next    =    cntrlr_tx_buf[7];
        cntrlr_copi_cap1_next         =    cap1_tx_buf[7];
        cntrlr_copi_cap2_next         =    cap2_tx_buf[7];
        cntrlr_copi_cap3_next         =    cap3_tx_buf[7];
        cntrlr_pclk_cntr_next         =    cntrlr_pclk_cntr;
        cntrlr_spi_pending_next       =    cntrlr_spi_pending;
        cntrlr_spi_done_next          =    cntrlr_spi_done;
        load_registers                =    1'b0;
        cntrlr_tx_mux_next            =    cntrlr_tx_mux;
        radio_ack_next                =    radio_ack;
        irq_spi_next                  =    1'b0;
            
        case(state)
            STATE_IDLE: begin
            
                cntrlr_nps_next            =    2'b10;
                cntrlr_pclk_cntr_next      =    2'b0;
                cntrlr_tx_bit_cntr_next    =    4'b0;
                load_registers             =    1'b0;
                cntrlr_spi_pending_next    =    1'b0;
                cntrlr_spi_done_next       =    1'b0;
                
                if(radio_running)    begin
                    if(txcancel_rdy) begin
                        load_registers     =    1'b1;
                        state_next         =    STATE_TX;
                        case(txcancel_csel)
                            1'b0:       begin
                                cntrlr_nps_next            =    2'b11;
                                cntrlr_tx_buf_load         =    {8'b10001100,txcancel_data};
                                cntrlr_tx_bit_cntr_load    =    4'd8;
                                cntrlr_tx_mux_next         =    1'b1;
                            end
                            default:    begin
                                cntrlr_nps_next            =    2'b00;
                                cntrlr_tx_buf_load         =    {8'b10001100,txcancel_data};
                                cntrlr_tx_bit_cntr_load    =    4'b0;
                                cntrlr_tx_mux_next         =    1'b0;
                            end
                        endcase
                    end
                end else begin
                    if(cntrlr_spi_rdy) begin
                        cntrlr_spi_pending_next    =    1'b1;
                        load_registers             =    1'b1;
                        state_next                 =    STATE_TX;
                        cntrlr_tx_buf_load         =    {cntrlr_addr_buf,cntrlr_data_buf};
                        cntrlr_nps_next            =    2'b00;    //Only write to the SX1257
                        cntrlr_tx_bit_cntr_load    =    4'b0;
                        cntrlr_tx_mux_next         =    1'b0;
                    end
                end
            end
            
            STATE_TX: begin
                
                cntrlr_pclk_cntr_next              =    cntrlr_pclk_cntr+2'b01;        //PCLK is low at this point
                cntrlr_pclk_next                   =    cntrlr_pclk_cntr[1];
                
                if(cntrlr_tx_mux)    begin
                    cntrlr_copi_cap0_rdio_next     =    cntrlr_tx_buf[7];
                end    else    begin
                    cntrlr_copi_cap0_rdio_next     =    cntrlr_tx_buf[15];
                end
                
                if(cntrlr_pclk_cntr_next    == 2'b00) begin                             //Switch bit on the falling edge of the "clock"
                    cntrlr_tx_buf_next             =    {cntrlr_tx_buf[14:0],1'b0};     //Shifting in a 1'b1 permits shift reg construct
                    cap1_tx_buf_next               =    {cap1_tx_buf[6:0],1'b0};
                    cap2_tx_buf_next               =    {cap2_tx_buf[6:0],1'b0};
                    cap3_tx_buf_next               =    {cap3_tx_buf[6:0],1'b0};
                    cntrlr_tx_bit_cntr_next        =    cntrlr_tx_bit_cntr+4'd1;        //Ideally this is flopped on negedge cntrlr_pclk. Not sure if OK.
                        if(cntrlr_tx_bit_cntr    ==    4'd15)    begin                  //cntrlr_tx_bit_cntr will automatically roll over to 0 for the next state
                            state_next        =    STATE_ACK;
                            radio_ack_next    =    1'b1;
                            if(!radio_running)
                                irq_spi_next      =    1'b1;                           //IRQ should be issued on the transition to STATE_ACK, even though it comes before spi_done
                        end                                                            //This is fine since there will be a delay in the irq merger.
                end
                
                if(cntrlr_pclk_cntr    == 2'b10 && cntrlr_spi_pending && cntrlr_tx_bit_cntr >= 4'd7 && cntrlr_tx_bit_cntr <= 4'd15)    //Capture returned data on pclk RE
                    cntrlr_rx_buf_next    =    {cntrlr_rx_buf[6:0],cntrlr_cipo};
                
            end
            
            STATE_ACK: begin                                                           //Wait for tx_cancel.v to deassert data_rdy bit.
                radio_ack_next             =    1'b1;                                  //Then move to IDLE state and wait for it to go high again
                cntrlr_spi_pending_next    =    1'b0;    
                cntrlr_spi_done_next       =    1'b1;                                                       //This extra cycle should keep NSS architecturally active for an extra clock cycle
                if((!txcancel_rdy && radio_running) || (!cntrlr_spi_rdy && !radio_running))    begin        //which will allow the SX1257 NSS hold time requirement to be met.
                    radio_ack_next         =    1'b0;
                    cntrlr_spi_done_next   =    1'b0;
                    state_next             =    STATE_IDLE;
                end
            end
            
            default: begin
                state_next    =    STATE_IDLE;
            end
            
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state                    <=    STATE_IDLE;
            cntrlr_tx_buf            <=    16'b0;
            cap1_tx_buf              <=    8'b0;
            cap2_tx_buf              <=    8'b0;
            cap3_tx_buf              <=    8'b0;
            cntrlr_tx_bit_cntr       <=    4'b0;
            cntrlr_rx_buf            <=    8'b0;
            cntrlr_nps               <=    2'b10;
            cntrlr_pclk              <=    1'b0;
            cntrlr_copi_cap3         <=    1'b0;
            cntrlr_copi_cap2         <=    1'b0;
            cntrlr_copi_cap1         <=    1'b0;
            cntrlr_copi_cap0_rdio    <=    1'b0;
            cntrlr_pclk_cntr         <=    2'b0;
            cntrlr_spi_pending       <=    1'b0;
            cntrlr_spi_done          <=    1'b0;
            cntrlr_tx_mux            <=    1'b0;
            radio_ack                <=    1'b0;
            irq_spi                  <=    1'b0;
        end    else    begin
            state                    <=    state_next;
            cntrlr_rx_buf            <=    cntrlr_rx_buf_next;
            cntrlr_nps               <=    cntrlr_nps_next;
            cntrlr_pclk              <=    cntrlr_pclk_next;
            cntrlr_copi_cap3         <=    cntrlr_copi_cap3_next;
            cntrlr_copi_cap2         <=    cntrlr_copi_cap2_next;
            cntrlr_copi_cap1         <=    cntrlr_copi_cap1_next;
            cntrlr_copi_cap0_rdio    <=    cntrlr_copi_cap0_rdio_next;
            cntrlr_pclk_cntr         <=    cntrlr_pclk_cntr_next;
            cntrlr_spi_pending       <=    cntrlr_spi_pending_next;
            cntrlr_spi_done          <=    cntrlr_spi_done_next;
            cntrlr_tx_mux            <=    cntrlr_tx_mux_next;
            radio_ack                <=    radio_ack_next;
            irq_spi                  <=    irq_spi_next;
            
            if(load_registers)    begin
                cntrlr_tx_buf        <=    cntrlr_tx_buf_load;
                cap1_tx_buf          <=    {3'b000,txcancel_data_aux[14:10]};
                cap2_tx_buf          <=    {3'b000,txcancel_data_aux[9:5]};
                cap3_tx_buf          <=    {3'b000,txcancel_data_aux[4:0]};
                cntrlr_tx_bit_cntr   <=    cntrlr_tx_bit_cntr_load;
            end else begin
                cntrlr_tx_buf        <=    cntrlr_tx_buf_next;
                cap1_tx_buf          <=    cap1_tx_buf_next;
                cap2_tx_buf          <=    cap2_tx_buf_next;
                cap3_tx_buf          <=    cap3_tx_buf_next;
                cntrlr_tx_bit_cntr   <=    cntrlr_tx_bit_cntr_next;
            end
        end
    end
endmodule

    