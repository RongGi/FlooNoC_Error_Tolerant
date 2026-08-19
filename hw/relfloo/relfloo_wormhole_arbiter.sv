// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"

/// A wormhole arbiter
module relfloo_wormhole_arbiter import floo_pkg::*;
#(
  parameter int unsigned NumRoutes  = 1,
  parameter type         flit_t     = logic
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  /// Ports towards the input routes
  input  logic  [2:0][NumRoutes-1:0]  valid_i,
  output logic  [2:0][NumRoutes-1:0]  ready_o,
  input  flit_t [NumRoutes-1:0]  data_i,
  /// Ports towards the output route
  output logic  [2:0]                 valid_o,
  input  logic  [2:0]                 ready_i,
  output flit_t                  data_o
);
  typedef logic [cf_math_pkg::idx_width(NumRoutes)-1:0] arb_idx_t;

  logic [2:0]last_out, last_q;
  arb_idx_t[2:0] selected_idx, valid_selected_idx;
  arb_idx_t valid_selected_idx_tmr;

  logic [2:0][NumRoutes-1:0] valid_d, valid_q;

  // Use arbiter to determine overall packet arbitration
  TODO
  for (genvar i = 0; i < 3; i++) begin : tmr_select
    rr_arb_tree #(
      .NumIn    ( NumRoutes ),
      .DataType ( logic     ),
      .ExtPrio  ( 1'b0      ),
      .AxiVldRdy( 1'b1      ),
      .LockIn   ( 1'b1      ), // Ensure LockIn to avoid changing priority
      .FairArb  ( 1'b1      )
    ) i_rr_arb_packets (
      .clk_i,
      .rst_ni,
      .flush_i( 1'b0 ),
      .rr_i   ( '0 ),
      .req_i  ( valid_d[i] ),
      .gnt_o  (),
      .data_i ( '0 ),
      .req_o  (),
      .gnt_i  ( ready_i[i] & last_out[i] ),
      .data_o (),
      .idx_o  ( selected_idx[i] )
    );

    assign valid_selected_idx[i] = (|valid_i[i]) ? selected_idx[i] : '0;

    // Manually connect handshake and data signals
    assign valid_o[i] = valid_i[i][valid_selected_idx_tmr];
  end
  bitwise_TMR_voter_fail #(
      .DataWidth ( $bits(valid_selected_idx[0]) ),
      .VoterType ( 1 )
  ) i_hdr_tmr (
      .a_i              ( valid_selected_idx[0] ),
      .b_i              ( valid_selected_idx[1] ),
      .c_i              ( valid_selected_idx[2] ),
      .majority_o       ( valid_selected_idx_tmr ),
      .fault_detected_o ( )
  );
  assign data_o  = data_i [valid_selected_idx_tmr];
  for (genvar i = 0; i < 3; i++) begin : gen_ready
    always_comb begin : proc_ready_o
      ready_o[i] = '0;
      // when valid_i is invalid, there's no generated ready bit
      ready_o[i][valid_selected_idx_tmr] = (|valid_i[i])? ready_i[i] : '0;
    end
  
    assign last_out[i] = data_o.hdr[i].last & valid_o[i];
  end

  always_comb begin : proc_valid
    for (int i = 0; i < 3; i++) begin
      valid_d[i] = valid_q[i];
      if (valid_q[i] == '0 || last_q[i]) begin
        valid_d[i] = valid_i[i];
      end
    end
  end
TODO
  `FF(valid_q, valid_d, '0)
  `FF(last_q, last_out & ready_i, '0)

  `ASSERT(InvalidCreation, valid_o |-> |valid_i)

endmodule
