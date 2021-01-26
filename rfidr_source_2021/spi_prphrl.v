/////////////////////////////////////////////////////////////////////////////////////////
//                                                                                     //
// Module : SPI Peripheral                                                             //
//                                                                                     //
// Filename: spi_prphrl.v                                                              //
// Creation Date: 3/27/2016                                                            //
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
//    This is strictly an SPI peripheral block: we are trying to get minimal LUT.      //
//    090516 - Added radio_num_tags as an input                                        //
//    111016 - Added support for full inventory                                        //
//    112616 - Fixed issue with full inventory wherein we would like feedback to       //
//    shut off the new_query and inventory_end bits once they have been used by the    //
//    radio fsm                                                                        //
//    082817 - Add fine-tune DTC test capabilities for automated testing of TMN        //
//    021518 - Add bit for kill_write_packet. Also add input clear_kill_pkt.           //
//    120520 - Rename new_query and inventory_end bits. Added provisions for improved  //
//    robustness and error handling during programming.                                //
//    122620 - Add bits for programatically setting TX offsets. Remove all mentions    //
//    of waveform offset in an attempt to recover some LUT.                            //
//                                                                                     //
/////////////////////////////////////////////////////////////////////////////////////////

module spi_prphrl(
    //Inputs
    input    wire                prphrl_copi,             //Needs double flop synchronizer external to this block
    input    wire                prphrl_nps,              //Needs double flop synchronizer external to this block
    input    wire                prphrl_pclk,             //Needs double flop synchronizer external to this block
    
    input    wire    [7:0]       radio_sram_rdata,
    input    wire    [7:0]       wvfm_sram_rdata,
    input    wire    [7:0]       txcancel_sram_rdata,
    
    input    wire                clk,                    //27p5MHz clock 
    input    wire                rst_n,
    
    //Inputs related to control registers
    
    input    wire                wave_storage_running,   //Needs double flop synchronizer external to this block
    input    wire                wave_storage_done,      //Needs double flop synchronizer external to this block
    input    wire    [1:0]       radio_exit_code,        //Needs double flop synchronizer external to this block
    input    wire                radio_done,             //Needs double flop synchronizer external to this block
    input    wire                radio_running,          //Needs double flop synchronizer external to this block
    input    wire                tx_error,               //Needs double flop synchronizer external to this block
    input    wire    [2:0]       write_cntr,             //Needs double flop synchronizer external to this block
    input    wire                clk_36_valid,
    input    wire                clk_36_running,
    input    wire    [7:0]       cntrlr_rx_buf,           //No need to retime, runs on 27.5 MHZ domain
    input    wire                cntrlr_spi_pending,      //No need to retime, runs on 27.5 MHZ domain
    input    wire                cntrlr_spi_done,         //No need to retime, runs on 27.5 MHZ domain
    
    //Outputs
    output   reg                 prphrl_cipo,
    
    output   wire    [9:0]       radio_sram_addr,
    output   wire    [7:0]       radio_sram_wdata,
    output   reg                 radio_sram_we_data,
    output   wire    [9:0]       txcancel_sram_addr,
    output   wire    [7:0]       txcancel_sram_wdata,
    output   reg                 txcancel_sram_we_data,
    output   wire    [12:0]      wvfm_sram_addr,
    
    //Outputs related to control registers
    
    output   reg                 go_radio,
    output   reg                 irq_ack,
    output   reg     [1:0]       radio_mode,
    output   reg                 alt_radio_fsm_loop,
    output   reg                 end_radio_fsm_loop,
    output   reg                 use_select_pkt,
    output   reg                 kill_write_pkt,
    output   reg                 sw_reset,
    output   reg     [7:0]       wvfm_offset,
    output   reg                 clk_36_start,
    output   reg                 use_i,
    output   reg     [7:0]       cntrlr_addr_buf,        //No need to retime, runs on 27.5 MHZ domain
    output   reg     [7:0]       cntrlr_data_buf,        //No need to retime, runs on 27.5 MHZ domain
    output   reg                 cntrlr_spi_rdy,         //No need to retime, runs on 27.5 MHZ domain
    output   reg     [9:0]       spi_cap_val_1,
    output   reg     [9:0]       spi_cap_val_2,
    output   reg                 dtc_test_mode,
    output   reg                 dtc_test_go,
    output   reg     [3:0]       sdm_offset,
    output   reg     [3:0]       zgn_offset
);

    // Parameter and localparam declarations

    localparam    STATE_IDLE        =    2'd0;        //Wait for SCLK to start going    
    localparam    STATE_RX          =    2'd1;        //Receive 24b of data
    localparam    STATE_LOAD_TX     =    2'd2;        //This assumes that we have more than one clock cycle between SPI controller REs.
    localparam    STATE_TX          =    2'd3;        //Play back read data or data just written

    // Wire declarations
    
    wire            prphrl_nps_start_message;
    wire            prphrl_pclk_re;
    //wire            prphrl_pclk_fe;    Somehow this is never read
    wire    [2:0]   user_mem_addr;
    wire    [7:0]   user_mem_wdata;
    wire            is_write;
    wire            is_wvfm_sram_addr;
    wire            is_radio_sram_addr;
    wire            is_txcancel_sram_addr;
    wire            is_user_mem_addr;
    wire            radio_done_re;
    
    // Register declarations
    
    reg             prphrl_pclk_r;                           //For detecting rising and falling edge
    reg             prphrl_nps_r;                            //For detecting rising and falling edge
    reg    [4:0]    txrx_cntr_next, txrx_cntr;               //Counts up to 24 bits. Used for all mode timings.
    reg    [23:0]   prphrl_rx_buf_next, prphrl_rx_buf;       //Should save LUT by having many shift in/parallel out buffers
    reg    [7:0]    prphrl_tx_buf_next, prphrl_tx_buf;       //as opposed to muxing many signals into a few shift registers
    reg    [7:0]    prphrl_tx_buf_load;
    reg    [1:0]    state_next, state;
    //reg    [7:0]    wvfm_offset_next;
    reg    [1:0]    radio_mode_next;
    reg             use_i_next, alt_radio_fsm_loop_next, end_radio_fsm_loop_next, use_select_pkt_next, kill_write_pkt_next;
    reg    [7:0]    cntrlr_addr_buf_next, cntrlr_data_buf_next;
    reg             cntrlr_spi_rdy_next, prphrl_cipo_next;
    reg             load_prphrl_tx_buf;
    reg             irq_ack_next, go_radio_next, sw_reset_next, clk_36_start_next;    //One shot control registers
    reg             radio_done_dly;
    reg    [9:0]    spi_cap_val_1_next, spi_cap_val_2_next;
    reg             dtc_test_mode_next, clear_cap_vals_next, incr_cap_val_2_next, incr_cap_val_1_next;
    reg    [3:0]    sdm_offset_next, zgn_offset_next;
    
    // Control Register Declarations
    // Combinational logic assignments
    // Detect rising and falling edges of various input signals.
    
    assign    prphrl_nps_start_message  =    {prphrl_nps_r,prphrl_nps}      ==    2'b10;    // Message starts on SS falling edge
    assign    prphrl_pclk_re            =    {prphrl_pclk_r,prphrl_pclk}    ==    2'b01;
    //assign    prphrl_pclk_fe          =    {prphrl_pclk_r,prphrl_pclk}    ==    2'b10;
    
    assign    wvfm_sram_addr            =    prphrl_rx_buf_next[20:8];
    assign    radio_sram_addr           =    prphrl_rx_buf_next[17:8];
    assign    radio_sram_wdata          =    prphrl_rx_buf_next[7:0];
    assign    txcancel_sram_addr        =    prphrl_rx_buf_next[17:8];
    assign    txcancel_sram_wdata       =    prphrl_rx_buf_next[7:0];
    assign    user_mem_addr             =    prphrl_rx_buf_next[10:8];
    assign    user_mem_wdata            =    prphrl_rx_buf_next[7:0];
    assign    is_write                  =    prphrl_rx_buf_next[22];
    assign    is_wvfm_sram_addr         =    prphrl_rx_buf_next[21];
    assign    is_radio_sram_addr        =    ~is_wvfm_sram_addr && prphrl_rx_buf_next[20];
    assign    is_txcancel_sram_addr     =    ~is_wvfm_sram_addr && ~is_radio_sram_addr && prphrl_rx_buf_next[19];
    assign    is_user_mem_addr          =    ~is_wvfm_sram_addr && ~is_radio_sram_addr && ~is_txcancel_sram_addr && prphrl_rx_buf_next[18];
    
    assign    radio_done_re             =    radio_done && !radio_done_dly;
    
    // Register logic to permit detection of rising and falling edges of various input signals
    
    always @(posedge clk or negedge rst_n)    begin
        if(!rst_n)    begin
            prphrl_pclk_r    <=    1'b0;
            prphrl_nps_r     <=    1'b0;
        end    else    begin
            prphrl_pclk_r    <=    prphrl_pclk;
            prphrl_nps_r     <=    prphrl_nps;
        end
    end
    
    always @(*)    begin
    
        //Defaults
        
        state_next                 =    state;                  //State is flopped at the full clock rate
        txrx_cntr_next             =    txrx_cntr;
        prphrl_rx_buf_next         =    prphrl_rx_buf;
        prphrl_tx_buf_next         =    prphrl_tx_buf;
        //prphrl_tx_buf_load       =    {radio_exit_code,radio_mode,irq_ack,go_radio};
        prphrl_tx_buf_load         =    wvfm_sram_rdata;
        prphrl_cipo_next           =    prphrl_cipo;
        radio_sram_we_data         =    1'b0;
        txcancel_sram_we_data      =    1'b0;
        load_prphrl_tx_buf         =    1'b0;
        irq_ack_next               =    1'b0;                    //One shot control register
        go_radio_next              =    1'b0;                    //One shot control register
        sw_reset_next              =    1'b0;                    //One shot control register
        clk_36_start_next          =    1'b0;                    //One shot control register
        //wvfm_offset_next         =    wvfm_offset;             //Persistent control register
        radio_mode_next            =    radio_mode;
        alt_radio_fsm_loop_next    =    alt_radio_fsm_loop    &&    !radio_done_re;        //Reset new query once we have completed a slot
        end_radio_fsm_loop_next    =    end_radio_fsm_loop    &&    !radio_done_re;        //Reset inventory end once we have completed a slot
        use_select_pkt_next        =    use_select_pkt        &&    !radio_done_re;
        kill_write_pkt_next        =    kill_write_pkt        &&    !radio_done_re;        //Clear the kill pkt flag after the transaction
        use_i_next                 =    use_i;                    //Persistent control register
        cntrlr_addr_buf_next       =    cntrlr_addr_buf;           //Persistent control register
        cntrlr_data_buf_next       =    cntrlr_data_buf;           //Persistent control register
        cntrlr_spi_rdy_next        =    cntrlr_spi_rdy;            //Was considered one-shot at one point (pre-8/14 but re-examination of the code showed expected behavior was more like async handshaking)
        spi_cap_val_1_next         =    spi_cap_val_1;
        spi_cap_val_2_next         =    spi_cap_val_2;
        dtc_test_mode_next         =    dtc_test_mode;
        clear_cap_vals_next        =    1'b0;                     //One shot control register 
        incr_cap_val_2_next        =    1'b0;                     //One shot control register
        incr_cap_val_1_next        =    1'b0;                     //One shot control register
        sdm_offset_next	           =    sdm_offset;
        zgn_offset_next	           =    zgn_offset;
        
    
        if(prphrl_pclk_re)
            prphrl_rx_buf_next     =    {prphrl_rx_buf[22:0],prphrl_copi};
                
        case(state)
            STATE_IDLE: begin
            
                txrx_cntr_next     =    5'b0;
                
                if(prphrl_nps_start_message) begin
                    state_next        =    STATE_RX;
                    txrx_cntr_next    =    5'b0;
                end
            end
            
            STATE_RX: begin
            
                if(prphrl_pclk_re) begin
                    txrx_cntr_next    =    txrx_cntr+5'b1;
                
                    if(txrx_cntr    ==    5'd22) begin
                
                        state_next        =    STATE_LOAD_TX;
                        txrx_cntr_next    =    5'b0;
                
                        if(is_write) begin
                            if(is_radio_sram_addr)
                                radio_sram_we_data       =    1'b1;
                            if(is_txcancel_sram_addr)
                                txcancel_sram_we_data    =    1'b1;
                            if(is_user_mem_addr)    begin
                                case(user_mem_addr)
                                    3'b000: begin
                                        use_i_next                 =    user_mem_wdata[4];
                                        radio_mode_next            =    user_mem_wdata[3:2];
                                        irq_ack_next               =    user_mem_wdata[1];
                                        go_radio_next              =    user_mem_wdata[0];
                                    end
                                    3'b001: begin
                                        clk_36_start_next          =    user_mem_wdata[7];
                                        use_select_pkt_next        =    user_mem_wdata[6];
                                        alt_radio_fsm_loop_next    =    user_mem_wdata[5];
                                        end_radio_fsm_loop_next    =    user_mem_wdata[4];
                                    end
                                    3'b010: begin
                                        cntrlr_spi_rdy_next        =    user_mem_wdata[1];
                                        sw_reset_next              =    user_mem_wdata[0];
                                    end
//                                    3'b011: begin
//                                        wvfm_offset_next         =    user_mem_wdata[7:0];
//                                    end
                                    3'b100: begin
                                        cntrlr_addr_buf_next       =    user_mem_wdata[7:0];
                                    end
                                    3'b101: begin
                                        cntrlr_data_buf_next       =    user_mem_wdata[7:0];
                                    end
                                    3'b110: begin
                                        //dtc_test_mode_next           =    user_mem_wdata[3]; 
                                        //101117 - Comment out this to try to remove all dtc test mode HW. 120117 - need it to turn on TX
                                        //sx1257_pll_chk_mode_next     =    user_mem_wdata[4];
                                        kill_write_pkt_next        =    user_mem_wdata[5];
                                        dtc_test_mode_next         =    1'b0;
                                        clear_cap_vals_next        =    user_mem_wdata[2];
                                        incr_cap_val_2_next        =    user_mem_wdata[1];
                                        incr_cap_val_1_next        =    user_mem_wdata[0];
                                    end
                                    3'b111: begin
                                        sdm_offset_next            =    user_mem_wdata[7:4];
                                        zgn_offset_next            =    user_mem_wdata[3:0];
                                    end
                                    default: begin end
                                endcase
                            end
                        end 
                    end    
                end
            end
            STATE_LOAD_TX: begin    //Introduce a state to load TX buffer during reads to account for the fact that SRAMs have registered inputs (and hence delays).
                state_next    =    STATE_TX;
                if(is_write)    begin
                    //For now, do nothing. We may need to load all zeros here.
                end    else    begin
                    load_prphrl_tx_buf    =    1'b1;
                    //Limit to 8 muxings, should keep LUT to 56 here
                    if(is_wvfm_sram_addr)
                        prphrl_tx_buf_load    =    wvfm_sram_rdata;
                    if(is_radio_sram_addr)
                        prphrl_tx_buf_load    =    radio_sram_rdata;
                    if(is_txcancel_sram_addr)
                        prphrl_tx_buf_load    =    txcancel_sram_rdata;
                    if(is_user_mem_addr)    begin
                        case(user_mem_addr)
                            3'b000: begin
                                //prphrl_tx_buf_load    =    {radio_exit_code,radio_mode,1'b0,1'b0};
                                prphrl_tx_buf_load    =    {1'b0,radio_exit_code,use_i,radio_mode,clk_36_valid,clk_36_running};
                            end
                            3'b001: begin
                                //prphrl_tx_buf_load    =    {1'b0,clk_36_valid,clk_36_running,1'b0,wave_storage_running,wave_storage_done,radio_running,radio_done};
                                prphrl_tx_buf_load    =    {1'b0,use_select_pkt,alt_radio_fsm_loop,end_radio_fsm_loop,wave_storage_running,wave_storage_done,radio_running,radio_done};
                            end
                            3'b010: begin
                                prphrl_tx_buf_load    =    {1'b0,cntrlr_spi_pending,cntrlr_spi_done,1'b0,tx_error,write_cntr};
                            end
//                            3'b011: begin
//                                prphrl_tx_buf_load    =    wvfm_offset;
//                            end
                            3'b101: begin //122320 Was changed from Address 7 - will need to change this in MCU FW.
                                prphrl_tx_buf_load    =    cntrlr_rx_buf;
                            end
                            3'b110: begin
                                prphrl_tx_buf_load    =    {2'b0,kill_write_pkt,1'b0,dtc_test_mode,3'b0};
                            end
                            3'b111: begin
                                prphrl_tx_buf_load    =    {sdm_offset,zgn_offset}; //Need to read this back to confirm correct programming.
                            end
                            default: begin
                                prphrl_tx_buf_load    =    {radio_exit_code,use_i,radio_mode,clk_36_valid,clk_36_running};
                            end
                        endcase
                    end
                end    
            end
            STATE_TX: begin                                               //prphrl data out should change on falling edge of clk at NRF51822 pin
                                                                          //But we don't have enough time to make this turnaround with 3 clk delays in the path for the worst case clock delta
                if(prphrl_pclk_re) begin                                   //So therefore, we launch when we see the prphrl clk re.
                    if(txrx_cntr    < 5'd8) begin                         //This guarantees that the data is ready at the NRF51822 well before the next rising edge.
                        txrx_cntr_next        =    txrx_cntr+5'b1;
                        prphrl_cipo_next      =    prphrl_tx_buf[7];       //This needs to go out immediately, but there will be a delay - 082016: we do need to register this, so we have a total of 3 delays
                        prphrl_tx_buf_next    =    {prphrl_tx_buf[6:0],1'b0};//Shift, shifting in a 1`b1 so that no LUT are used - 082016: Use 0, it will make things simpler for now.
                    end   else    begin
                        txrx_cntr_next    =    5'b0;
                        state_next        =    STATE_IDLE;
                    end
                end
            end
            
            default: begin    
                state_next    =    STATE_IDLE;
            end
            
        endcase
        
            if(prphrl_nps && (state != STATE_IDLE))
                state_next        =    STATE_IDLE;        //If we ever see prphrl_nps show up at the wrong time, stop and go to IDLE where we presumably reset.
            //The only question is whether this statement is overridden by anything in the case statement.
    end
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state                 <=    STATE_IDLE;
            txrx_cntr             <=    5'b0;
            prphrl_rx_buf         <=    24'b0;
            prphrl_tx_buf         <=    8'b0;
            wvfm_offset           <=    8'b0;
            radio_mode            <=    2'b0;
            alt_radio_fsm_loop    <=    1'b0;
            end_radio_fsm_loop    <=    1'b0;
            use_select_pkt        <=    1'b0;
            kill_write_pkt        <=    1'b0;
            use_i                 <=    1'b0;
            cntrlr_addr_buf       <=    8'b0;
            cntrlr_data_buf       <=    8'b0;
            cntrlr_spi_rdy        <=    1'b0;
            prphrl_cipo           <=    1'b0;
            irq_ack               <=    1'b0;                    //One shot control register
            go_radio              <=    1'b0;                    //One shot control register
            sw_reset              <=    1'b0;                    //One shot control register
            clk_36_start          <=    1'b0;                    //One shot control register
            radio_done_dly        <=    1'b0;
            spi_cap_val_1         <=    10'd512;                 //To send to middle of pattern
            spi_cap_val_2         <=    10'd512;                 //To send to middle of pattern
            dtc_test_mode         <=    1'b0;
            dtc_test_go           <=    1'b0;
            sdm_offset            <=    4'b0;
            zgn_offset            <=    4'b0;
        end    else    begin
            state                 <=    state_next;
            txrx_cntr             <=    txrx_cntr_next;
            prphrl_rx_buf         <=    prphrl_rx_buf_next;
            wvfm_offset           <=    8'b0;
            radio_mode            <=    radio_mode_next;
            alt_radio_fsm_loop    <=    alt_radio_fsm_loop_next;
            end_radio_fsm_loop    <=    end_radio_fsm_loop_next;
            use_select_pkt        <=    use_select_pkt_next;
            kill_write_pkt        <=    kill_write_pkt_next;
            use_i                 <=    use_i_next;
            cntrlr_addr_buf       <=    cntrlr_addr_buf_next;
            cntrlr_data_buf       <=    cntrlr_data_buf_next;
            cntrlr_spi_rdy        <=    cntrlr_spi_rdy_next;
            prphrl_cipo           <=    prphrl_cipo_next;
            irq_ack               <=    irq_ack_next;             //One shot control register
            go_radio              <=    go_radio_next;            //One shot control register
            sw_reset              <=    sw_reset_next;            //One shot control register
            clk_36_start          <=    clk_36_start_next;        //One shot control register
            radio_done_dly        <=    radio_done;
            dtc_test_mode         <=    dtc_test_mode_next;
            sdm_offset            <=    sdm_offset_next;
            zgn_offset            <=    zgn_offset_next;
            
            //if(clear_cap_vals_next || ~dtc_test_mode)    begin    //If we force dtc_test_mode to 0, we want synthesis to take out all 40 added LUT, here and in txcancel.v
            if(clear_cap_vals_next || 1'b1) begin //120117 - Effective force DTC mode off
                spi_cap_val_1     <=    10'd512;
                spi_cap_val_2     <=    10'd512;
                dtc_test_go       <=    1'b1;
            end else if (incr_cap_val_1_next || incr_cap_val_2_next) begin
                dtc_test_go       <=    1'b1;
                if(incr_cap_val_1_next)
                    spi_cap_val_1 <=    spi_cap_val_1_next+10'd1;
                if(incr_cap_val_2_next)
                    spi_cap_val_2 <=    spi_cap_val_2_next+10'd1;
            end else begin
                spi_cap_val_1     <=    spi_cap_val_1_next;
                spi_cap_val_2     <=    spi_cap_val_2_next;
                dtc_test_go       <=    1'b0;
            end
        
            if(load_prphrl_tx_buf)
                prphrl_tx_buf     <=    prphrl_tx_buf_load;
            else
                prphrl_tx_buf     <=    prphrl_tx_buf_next;
        
        end
    end
endmodule