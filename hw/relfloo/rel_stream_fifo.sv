// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Author: Georg Rutishauser <georgr@iis.ee.ethz.ch>

module rel_stream_fifo #(
    /// FIFO is in fall-through mode
    parameter bit          FallThrough = 1'b0,
    /// Default data width if the fifo is of type logic
    parameter int unsigned DataWidth   = 32,
    /// Depth can be arbitrary from 0 to 2**32
    parameter int unsigned Depth       = 8,
    parameter type         data_t      = logic [DataWidth-1:0],
    // DO NOT OVERWRITE THIS PARAMETER
    localparam int unsigned UsageWidth = cc_pkg::idx_width(Depth)
) (
    input  logic                  clk_i,   // Clock
    input  logic                  rst_ni,  // Asynchronous reset active low
                                           // pointers *and* memories.
    input  logic                  flush_i, // Flush the queue; compared to clr_i this only clears
                                           // internal pointers. Sufficient for most functional
                                           // purposes.
    input  logic                  testmode_i,
    output logic [UsageWidth-1:0] usage_o, // Fill pointer
    // input interface
    input  data_t                 data_i,  // Data to push into the fifo
    input  logic [2:0]                 valid_i, // Input data valid
    output logic [2:0]                 ready_o, // Fifo is not full
    // output interface
    output data_t                 data_o,  // Output data
    output logic [2:0]                 valid_o, // Fifo is not empty
    input  logic [2:0]                 ready_i,  // Pop head from fifo

    output logic                  fault_o
);

    logic [2:0] push, pop;
    logic [2:0] empty, full;

    for (genvar i = 0; i < 3; i++) begin : gen_tmr_part
        assign push[i]    = valid_i[i] & ~full[i];
        assign pop[i]     = ready_i[i] & ~empty[i];
        assign ready_o[i] = ~full[i];
        assign valid_o[i] = ~empty[i];
    end

    rel_fifo #(
        .FallThrough(FallThrough),
        .DataWidth  (DataWidth),
        .Depth      (Depth),
        .data_t     (data_t)
    ) rel_fifo_i (
        .clk_i,
        .rst_ni,
        .flush_i,
        .testmode_i,
        .full_o (full),
        .empty_o(empty),
        .usage_o,
        .data_i,
        .push_i (push),
        .data_o,
        .pop_i  (pop),
        .fault_o
    );

endmodule