//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
// Module : Clock Crossings                                                         //
//                                                                                  //
// Filename: clk_crossings.v                                                        //
// Creation Date: 1/12/2016                                                         //
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
//    This block contains all of the signals that need to be double registered      //
// across clock domain boundaries (and hence false-pathed during timing             //
//    analysis).                                                                    //
//                                                                                  //
// We do have a couple of instances where we send multi-bit buses across the        //
// asynchronous boundary. How is this OK?                                           //
//                                                                                  //
//    1. radio_exit_code: this is just a diagnostic signal for the MCU.             //
//    The MCU cannot read this until well after it is settled.                      //
//                                                                                  //
//    2. radio_data, radio_csel: these are handled by delaying doing anything       //
// with these signals in spi.v until 1 clock cycle after radio_rdy has been         //
//    seen by implementing a dummy wait state in the state machine.                 //
//                                                                                  //
//    3. radio_mode: there is also effectively a dummy wait state here              //
//    If there wasn't, we'd potentially be in trouble, because radio_go and         //
// radio_mode are set at the same time in the spi.v block.                          //
//                                                                                  //
//    Revisions:                                                                    //
//                                                                                  //
//    022216 - Changed all of 27.5MHz to 24MHz                                      //
//    030116 - Removed cntrlr_cipo_pin                                               //
//    032416 - Changed 24 to 27.5 again                                             //
//    091816 - Added txcancel aux data                                              //
//    092416 - Removed double flops on data going from txcancel to spi controller.  //
//    This was done to finally allow the FPGA fitting to close.                     //
//    The reason that this is acceptable is because this transfer is at least a     //
//    half handshake, almost a full handshake, and effectively a full handshake.    //
//    Remember that according to pages 207-208 of the Mishra book, half handshakes  //
//    are acceptable, but potentially tricky, going from slow to fast clock         //
//    domains (as we are doing here).                                               //
//    Handshake criteria:                                                           //
//    1. When xfer data is ready, t_rdy is asserted from t domain flop. CHECK!      //
//    2. t_data is stable at this point. CHECK!                                     //
//    3. t_rdy is 2-flop synced to r domain. CHECK!                                 //
//    4. r_ack is asserted from r domain flop. CHECK!                               //
//    5. r_ack is 2 flop synced. CHECK!                                             //
//    So far this is a half handshake and we meet these requirements.               //
//    6. When r_ack is driven high, t_rdy is driven low. CHECK!                     //
//    7. When t_rdy is driven low, r_ack is driven low. CHECK!                      //
//    8. TX waits to see rack driven low before placing new data on the line.       //
//    NO CHECK on this last one. But it does not matter since spi_cntrlr will be in //
//    an ACK state and it will be a few more states before it is latching data      //
//    again.                                                                        //
//    111016 - Add signals to permit a real inventory with this IP                  //
//    021518 - Add provisions for killing tag.                                      //
//    120520 - Add provisions for adding robustness to programming.                 //
//    122320 - Add provisions for programming TX offset over SPI                    //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

module    clk_crossings(
    //Inputs from 4.5MHz domain to 27p5MHz domain
    input    wire             radio_busy_in,              //From radio_fsm.v to rfidr_fsm.v
    input    wire    [1:0]    radio_exit_code_in,         //From radio_fsm.v to spi.v
    input    wire             radio_done_in,              //From radio_fsm.v to rfidr_fsm.v
    
    input    wire    [7:0]    txcancel_data_in,           //From tx_cancel.v to spi.v
    input    wire    [14:0]   txcancel_data_aux_in,       //From tx_cancel.v to spi.v
    input    wire             txcancel_csel_in,           //From tx_cancel.v to spi.v
    input    wire             txcancel_rdy_in,            //From tx_cancel.v to spi.v
    
    input    wire             tx_error_in,                //From radio_fsm.v to spi.v
    input    wire    [2:0]    write_cntr_in,              //From radio_fsm.v to spi.v
    
    input    wire             wave_storage_done_in,
    input    wire             wave_storage_running_in,
    
    //Inputs from 27p5MHz domain to 4.5MHz domain
    input    wire             radio_go_in,                //From rfidr_fsm.v to radio_fsm.v
    input    wire    [1:0]    radio_mode_in,              //From spi.v to radio_fsm.v
    input    wire             radio_ack_in,               //From spi.v to tx_cancel.v
    input    wire             use_i_in,                   //From spi.v to CDR
    input    wire             alt_radio_fsm_loop_in,      //From spi.v to radio_fsm.v
    input    wire             end_radio_fsm_loop_in,      //From spi.v to radio_fsm.v
    input    wire             use_select_pkt_in,          //From spi.v to radio_fsm.v
    input    wire             kill_write_pkt_in,          //From spi.v to radio_fsm.v
    input    wire    [3:0]    sdm_offset_in,              //From spi.v to tx_sdm_c8g.v
    input    wire    [3:0]    zgn_offset_in,              //From spi.v to tx_zero_pattern_gen_c8g.v
    
    //Inputs from external async domain to 27p5MHz domain
    
    input    wire             prphrl_copi_in,              //From external to spi.v
    input    wire             prphrl_nps_in,               //From external to spi.v
    input    wire             prphrl_pclk_in,              //From external to spi.v
    
    //Clock and reset inputs
    
    input    wire             clk_27p5,
    input    wire             clk_4p5,
    input    wire             rst_n_27p5,
    input    wire             rst_n_4p5,
    
    //Outputs from 4.5MHz domain to 27p5MHz domain
    output    reg             radio_busy_out,             //From radio_fsm.v to rfidr_fsm.v
    output    reg    [1:0]    radio_exit_code_out,        //From radio_fsm.v to spi.v
    output    reg             radio_done_out,             //From radio_fsm.v to rfidr_fsm.v
    
    output    reg    [7:0]    txcancel_data_out,          //From tx_cancel.v to spi.v
    output    reg    [14:0]   txcancel_data_aux_out,      //From tx_cancel.v to spi.v
    output    reg             txcancel_csel_out,          //From tx_cancel.v to spi.v
    output    reg             txcancel_rdy_out,           //From tx_cancel.v to spi.v    
    
    output    reg             tx_error_out,               //From radio_fsm.v to spi.v
    output    reg    [2:0]    write_cntr_out,             //From radio_fsm.v to spi.v
    
    output    reg             wave_storage_done_out,
    output    reg             wave_storage_running_out,
    
    //Outputs from 27p5MHz domain to 4.5MHz domain
    output    reg             radio_go_out,               //From rfidr_fsm.v to radio_fsm.v
    output    reg    [1:0]    radio_mode_out,             //From spi.v to radio_fsm.v
    output    reg             radio_ack_out,              //From spi.v to tx_cancel.v
    output    reg             use_i_out,                  //From spi.v to CDR
    output    reg             alt_radio_fsm_loop_out,     //From spi.v to radio_fsm.v
    output    reg             end_radio_fsm_loop_out,     //From spi.v to radio_fsm.v
    output    reg             use_select_pkt_out,         //From spi.v to radio_fsm.v
    output    reg             kill_write_pkt_out,         //From spi.v to radio_fsm.v
    output    reg    [3:0]    sdm_offset_out,             //From spi.v to tx_sdm_c8g.v
    output    reg    [3:0]    zgn_offset_out,             //From spi.v to tx_zero_pattern_gen_c8g.v
    
    //Outputs from external async domain to 27p5MHz domain
    output    reg             prphrl_copi_out,             //From external to spi.v
    output    reg             prphrl_nps_out,              //From external to spi.v
    output    reg             prphrl_pclk_out              //From external to spi.v
);

    //Declare temporary registers
    
    reg             radio_busy_temp;                      //From radio_fsm.v to rfidr_fsm.v
    reg    [1:0]    radio_exit_code_temp;                 //From radio_fsm.v to spi.v
    reg             radio_done_temp;                      //From radio_fsm.v to rfidr_fsm.v
    
    //reg    [7:0]    txcancel_data_temp;                 //From tx_cancel.v to spi.v
    //reg    [14:0]   txcancel_data_aux_temp;             //From tx_cancel.v to spi.v
    //reg             txcancel_csel_temp;                 //From tx_cancel.v to spi.v
    reg             txcancel_rdy_temp;                    //From tx_cancel.v to spi.v
    
    reg             tx_error_temp;                        //From radio_fsm.v to spi.v
    reg    [2:0]    write_cntr_temp;                      //From radio_fsm.v to spi.v
    
    reg             wave_storage_done_temp;
    reg             wave_storage_running_temp;
    
    //Inputs from 27p5MHz domain to 4.5MHz domain
    reg             radio_go_temp;                        //From rfidr_fsm.v to radio_fsm.v
    reg    [1:0]    radio_mode_temp;                      //From spi.v to radio_fsm.v
    reg             radio_ack_temp;                       //From spi.v to tx_cancel.v
    reg             use_i_temp;
    reg             alt_radio_fsm_loop_temp;
    reg             end_radio_fsm_loop_temp;
    reg             use_select_pkt_temp;
    reg             kill_write_pkt_temp;
    reg    [3:0]    sdm_offset_temp;                      //From spi.v to tx_sdm_c8g.v
    reg    [3:0]    zgn_offset_temp;                      //From spi.v to tx_zero_pattern_gen_c8g.v
    
    //Inputs from external async domain to 27p5MHz domain
    
    reg             prphrl_copi_temp;                     //From external to spi.v
    reg             prphrl_nps_temp;                      //From external to spi.v
    reg             prphrl_pclk_temp;                     //From external to spi.v
    
    always @(*)    begin
        txcancel_csel_out        =    txcancel_csel_in;
        txcancel_data_out        =    txcancel_data_in;
        txcancel_data_aux_out    =    txcancel_data_aux_in;
    end
    
    always@(posedge clk_4p5 or negedge rst_n_4p5)
        if(!rst_n_4p5) begin
            radio_go_temp              <=    1'b0;
            radio_mode_temp            <=    2'b0;
            radio_ack_temp             <=    1'b0;
            use_i_temp                 <=    1'b0;
            alt_radio_fsm_loop_temp    <=    1'b0;
            end_radio_fsm_loop_temp    <=    1'b0;
            use_select_pkt_temp        <=    1'b0;
            kill_write_pkt_temp        <=    1'b0;
            sdm_offset_temp            <=    4'b0;
            zgn_offset_temp            <=    4'b0;
            
            radio_go_out               <=    1'b0;
            radio_mode_out             <=    2'b0;
            radio_ack_out              <=    1'b0;
            use_i_out                  <=    1'b0;
            alt_radio_fsm_loop_out     <=    1'b0;
            end_radio_fsm_loop_out     <=    1'b0;
            use_select_pkt_out         <=    1'b0;
            kill_write_pkt_out         <=    1'b0;
            sdm_offset_out             <=    4'b0;
            zgn_offset_out             <=    4'b0;

        end else begin
            radio_go_temp              <=    radio_go_in;
            radio_mode_temp            <=    radio_mode_in;
            radio_ack_temp             <=    radio_ack_in;
            use_i_temp                 <=    use_i_in;
            alt_radio_fsm_loop_temp    <=    alt_radio_fsm_loop_in;
            end_radio_fsm_loop_temp    <=    end_radio_fsm_loop_in;
            use_select_pkt_temp        <=    use_select_pkt_in;
            kill_write_pkt_temp        <=    kill_write_pkt_in;
            sdm_offset_temp            <=    sdm_offset_in;
            zgn_offset_temp            <=    zgn_offset_in;
            
            radio_go_out               <=    radio_go_temp;
            radio_mode_out             <=    radio_mode_temp;
            radio_ack_out              <=    radio_ack_temp;
            use_i_out                  <=    use_i_temp;
            alt_radio_fsm_loop_out     <=    alt_radio_fsm_loop_temp;
            end_radio_fsm_loop_out     <=    end_radio_fsm_loop_temp;
            use_select_pkt_out         <=    use_select_pkt_temp;
            kill_write_pkt_out         <=    kill_write_pkt_temp;
            sdm_offset_out             <=    sdm_offset_temp;
            zgn_offset_out             <=    zgn_offset_temp;
        end
        
    always@(posedge clk_27p5 or negedge rst_n_27p5) begin
        if(!rst_n_27p5) begin
            radio_busy_temp            <=    1'b0;
            radio_exit_code_temp       <=    2'b0;
            radio_done_temp            <=    1'b0;
            //txcancel_data_temp       <=    8'b0;
            //txcancel_data_aux_temp   <=    15'b0;
            //txcancel_csel_temp       <=    1'b0;
            txcancel_rdy_temp          <=    1'b0;
            tx_error_temp              <=    1'b0;
            write_cntr_temp            <=    3'b0;
            wave_storage_done_temp     <=    1'b0;
            wave_storage_running_temp  <=    1'b0;
            
            prphrl_copi_temp           <=    1'b0;
            prphrl_nps_temp            <=    1'b0;
            prphrl_pclk_temp           <=    1'b0;
            
            radio_busy_out             <=    1'b0;
            radio_exit_code_out        <=    2'b0;
            radio_done_out             <=    1'b0;
            //txcancel_data_out        <=    8'b0;
            //txcancel_data_aux_out    <=    15'b0;
            //txcancel_csel_out        <=    1'b0;
            txcancel_rdy_out           <=    1'b0;
            tx_error_out               <=    1'b0;
            write_cntr_out             <=    3'b0;
            wave_storage_done_out      <=    1'b0;
            wave_storage_running_out   <=    1'b0;
            
            prphrl_copi_out            <=    1'b0;
            prphrl_nps_out             <=    1'b0;
            prphrl_pclk_out            <=    1'b0;
        end else begin
            radio_busy_temp            <=    radio_busy_in;
            radio_exit_code_temp       <=    radio_exit_code_in;
            radio_done_temp            <=    radio_done_in;
            //txcancel_data_temp       <=    txcancel_data_in;
            //txcancel_data_aux_temp   <=    txcancel_data_aux_in;
            //txcancel_csel_temp       <=    txcancel_csel_in;
            txcancel_rdy_temp          <=    txcancel_rdy_in;
            tx_error_temp              <=    tx_error_in;
            write_cntr_temp            <=    write_cntr_in;
            wave_storage_done_temp     <=    wave_storage_done_in;
            wave_storage_running_temp  <=    wave_storage_running_in;
            
            prphrl_copi_temp           <=    prphrl_copi_in;
            prphrl_nps_temp            <=    prphrl_nps_in;
            prphrl_pclk_temp           <=    prphrl_pclk_in;
            
            radio_busy_out             <=    radio_busy_temp;
            radio_exit_code_out        <=    radio_exit_code_temp;
            radio_done_out             <=    radio_done_temp;
            //txcancel_data_out        <=    txcancel_data_temp;
            //txcancel_data_aux_out    <=    txcancel_data_aux_temp;
            //txcancel_csel_out        <=    txcancel_csel_temp;
            txcancel_rdy_out           <=    txcancel_rdy_temp;
            tx_error_out               <=    tx_error_temp;
            write_cntr_out             <=    write_cntr_temp;
            wave_storage_done_out      <=    wave_storage_done_temp;
            wave_storage_running_out   <=    wave_storage_running_temp;
            
            prphrl_copi_out            <=    prphrl_copi_temp;
            prphrl_nps_out             <=    prphrl_nps_temp;
            prphrl_pclk_out            <=    prphrl_pclk_temp;
        end
    end
endmodule
