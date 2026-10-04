// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "common_cells/registers.svh"
`include "common_cells/assertions.svh"
`include "floo_noc/registers.svh"

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
  output flit_t                  data_o,
  output logic                   faults_o
);
  typedef logic [cc_pkg::idx_width(NumRoutes)-1:0] arb_idx_t;

  logic [1:0] FF_TMR_fault;
  logic voter_fault;
  logic arb_fault;

  logic [2:0]last_out, last_q;
  arb_idx_t[2:0] selected_idx, valid_selected_idx;
  logic [2:0] arb_ready_in;
  flit_t [2:0] data_sel;

  logic [2:0][NumRoutes-1:0] valid_d, valid_q;

  //data transposing for arb_tree
  logic [NumRoutes-1:0][2:0] valid_transposed;

  for (genvar r = 0; r < NumRoutes; r++) begin: transpose_route
    for (genvar i = 0; i < 3; i++) begin: transpose_tmr
      assign valid_transposed[r][i] = valid_d[i][r];
    end
  end

  //assigning ready in signals
  for (genvar i = 0; i < 3; i++) begin: tmr_arb_ready_in
    assign arb_ready_in[i] = ready_i[i] & last_out[i];
  end

  // Use arbiter to determine overall packet arbitration
  rel_rr_arb_tree #(
    .NumIn    ( NumRoutes ),
    .DataType ( logic ),
    .ExtPrio  ( 1'b0      ),
    .AxiVldRdy( 1'b1      ),
    .LockIn   ( 1'b1      ), // Ensure LockIn to avoid changing priority
    .FairArb  ( 1'b1      ),
    .TmrStatus( 1'b1      )
  ) i_rr_arb_packets (
    .clk_i,
    .rst_ni,
    .flush_i( 1'b0 ),
    .rr_i   ( '0 ),
    .req_i  ( valid_transposed ),
    .gnt_o  ( ),
    .data_i ( '0),
    .req_o  (),
    .gnt_i  ( arb_ready_in ),
    .data_o (),
    .idx_o  ( selected_idx ),
    .fault_o( arb_fault)
  );
  //tmr signal connection
  for (genvar i = 0; i < 3; i++) begin: tmr_valid_out
    assign valid_selected_idx[i] = (|(valid_i[i])) ? selected_idx[i] : '0;
    assign valid_o[i] = valid_i[i][valid_selected_idx[i]];
  end

  // bitwise data voting
  flit_t [2**$bits(arb_idx_t)-1:0] data_in;
  always_comb begin
    data_in = '0;
    for (int r = 0; r < NumRoutes; r++) data_in[r] = data_i[r];
  end
  for (genvar r = 0; r < 3; r++) begin : gen_sel
    assign data_sel[r] = data_in[valid_selected_idx[r]];
  end
  bitwise_TMR_voter_fail #(
    .DataWidth ( $bits(flit_t) ),
    .VoterType ( 1 )
    ) i_idx_vote (
    .a_i              ( data_sel[0] ),
    .b_i              ( data_sel[1] ),
    .c_i              ( data_sel[2] ),
    .majority_o       ( data_o),
    .fault_detected_o ( )
  );

  // bitwise voting of output 
  for (genvar i = 0; i < 3; i++) begin: tmr_ready_out
    always_comb begin : proc_ready_o
      ready_o[i] = '0;
        // when valid_i is invalid, there's no generated ready bit
      ready_o[i][valid_selected_idx[i]] = (|valid_i[i])? ready_i[i] : '0;
    end
  end

  for (genvar i = 0; i < 3; i++) begin: tmr_last_out
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

  `TMRFF(valid_q, valid_d, FF_TMR_fault[0], '0)
  `TMRFF(last_q, last_out & ready_i, FF_TMR_fault[1], '0)
  assign voter_fault = 1'b0;
  assign faults_o = |{FF_TMR_fault, arb_fault, voter_fault};

  `ASSERT(InvalidCreation, valid_o |-> |valid_i)


  `ASSERT_INIT(DataIdxOrder, $bits(data_i[0]) == $bits(flit_t))

endmodule
