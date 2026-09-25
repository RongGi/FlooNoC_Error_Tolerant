// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Thomas Benz <tbenz@ethz.ch>

/// Optimal implementation of a stream FIFO based on the common cells modules.
/// Selects the smaller and faster spill register if the depth is 2 and the FIFO if
/// the depth is >2. Throws an error for the meaningless configurations depth 0 and 1.
module relfloo_stream_fifo_optimal_wrap #(
    /// Depth can be arbitrary from 2 to 2**32
    parameter int unsigned Depth = 32'd8,
    /// Type of the FIFO
    parameter type data_t = logic,
    /// Print information when the simulation launches
    parameter bit PrintInfo = 1'b0,
    // DO NOT OVERWRITE THIS PARAMETER
    localparam int unsigned UsageWidth = cc_pkg::idx_width(Depth),
    // estimated theshold
    localparam int unsigned WideCorrectorThreshold = 32'd300
) (
    input  logic                  clk_i,   // Clock
    input  logic                  rst_ni,  // Asynchronous reset active low
    input  logic                  testmode_i,
    input  logic                  flush_i, // Flush the fifo by draining its contents and clearing
                                           // its pointers. Sufficient for most functional purposes.
    output logic [UsageWidth-1:0] usage_o, // Fill pointer
    // Input interface
    input  data_t                 data_i,  // Data to push into the fifo
    input  logic [2:0]                 valid_i, // Input data valid
    output logic [2:0]                 ready_o, // Fifo is not full
    // Output interface
    output data_t                 data_o,  // Output data
    output logic [2:0]                 valid_o, // Fifo is not empty
    input  logic [2:0]                 ready_i,  // Pop head from fifo

    output logic [1:0]            fault_o
);
    logic  faults;
    logic [1:0] corrector_faults;
    assign fault_o[0] = |faults | corrector_faults[0];
    assign fault_o[1] = corrector_faults[1];
    //--------------------------------------
    // Prevent Depth 0 and 1
    //--------------------------------------
    // Throw an error if depth is 0 or 1
    `ifndef SYNTHESIS
    if (Depth < 32'd2) begin : gen_fatal
        initial begin
            $fatal(1, "FIFO of depth %d does not make any sense!", Depth);
        end
    end
    `endif

    //--------------------------------------
    // Spill register (depth 2)
    //--------------------------------------
    // Instantiate a spill register for depth 2
    if (Depth == 32'd2) begin : gen_spill

        // print info
        `ifndef SYNTHESIS
        if (PrintInfo) begin : gen_info
            initial begin
                $display("[%m] Instantiate spill register (of depth %d)", Depth);
            end
        end
        `endif

        // spill register

//..............................................


        data_t corrector, corrected;
        if ($bits(data_t) < WideCorrectorThreshold) begin: gen_corrector_narrow
            relfloo_corrector #(
                .chan_t(data_t)
            ) i_relfloo_corrector (
                .chan_i (corrector) ,
                .chan_o (corrected),
                .fault_o (corrector_faults)
            );
        end else begin: gen_corrector_wide
            relfloo_corrector_wide #(
                .chan_t(data_t)
            ) i_relfloo_corrector_wide (
                .chan_i (corrector) ,
                .chan_o (corrected),
                .fault_o (corrector_faults)
            );
        end
  //....................................

        rel_spill_register #(
            .T(data_t),
            .Bypass ( 1'b0    ),
            .TmrHandshake ( 1'b1 ),
            .DataCorrector ( 1'b1 )
        ) i_rel_spill_register_flushable (
            .clk_i   ,
            .rst_ni  ,
            .valid_i ,
            .ready_o ,
            .data_i  ,
            .valid_o ,
            .ready_i ,
            .data_o,
            .fault_o(faults),
            
            .data_corrector_o(corrector),
            .data_corrected_i(corrected)
        );


        // usage is not supported

        assign usage_o = 'x;
    end


    //--------------------------------------
    // FIFO register (depth 3+)
    //--------------------------------------
    // default to stream fifo
    if (Depth > 32'd2) begin : gen_fifo

        // print info
        `ifndef SYNTHESIS
        if (PrintInfo) begin : gen_info
            initial begin
                $info("[%m] Instantiate stream FIFO of depth %d", Depth);
            end
        end
        `endif

        // stream fifo
        rel_stream_fifo #(
            .Depth  ( Depth  ),
            .data_t ( data_t )
        ) i_stream_fifo (
            .clk_i,
            .rst_ni,
            .flush_i,
            .testmode_i,
            .usage_o,
            .data_i,
            .valid_i,
            .ready_o,
            .data_o,
            .valid_o,
            .ready_i,
            .fault_o(faults)
        );
        assign corrector_faults = 2'b00;
    end

endmodule : relfloo_stream_fifo_optimal_wrap