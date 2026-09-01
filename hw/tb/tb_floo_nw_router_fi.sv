// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Chen Wu <chenwu@iis.ee.ethz.ch>
//
// Unified fault-injection testbench for the FlooNoC NW router.
// One file covers four DUT configurations, selected by Bender target /
// preprocessor macro:
//
//   - baseline (neither macro): DUT = floo_nw_router, single-copy I/O.
//   - TARGET_STMR: DUT = floo_nw_routerTMR (state-only). Single-copy data
//                  ports identical to baseline; clk/rst are triplicated
//                  (clk_iA/B/C, rst_niA/B/C) — TB drives all three from the
//                  shared clk_i / rst_ni so GM behaves like baseline. Only
//                  registers triplicated and voted internally; DUT exports
//                  a single combined tmrError voter-error output. No border
//                  voter (no replicated outputs to vote on).
//   - TARGET_CTMR: DUT = floo_nw_routerTMR (coarse). Three unvoted replicas;
//                  border majority voters in this wrapper. No DUT error.
//   - TARGET_FTMR: DUT = floo_nw_routerTMR (full). Triplicated + internally
//                  voted; DUT exports tmrErrorA/B/C; border voters here too.
//
// TARGET_NETLIST swaps the inner i_dut from RTL to the synthesized wrappers
// (floo_synth_nw_router / floo_synth_nw_routerTMR), backed by a gate-level
// netlist supplied at vlogan time. The wrapper module name and signal
// hierarchy (i_dut_wrapper.i_dut.**) stay identical so strobe.sv and the
// SFF FaultList scope work unchanged. STMR has no synth-wrapper variant
// yet, so TARGET_STMR + TARGET_NETLIST is rejected.
//
// The macros TARGET_STMR / TARGET_CTMR / TARGET_FTMR / TARGET_NETLIST are
// emitted automatically by Bender from `-t stmr` / `-t ctmr` / `-t ftmr` /
// `-t netlist`. See floonoc_zoix/Makefile for the build flow.

`include "axi/typedef.svh"
`include "axi/assign.svh"
`include "floo_noc/typedef.svh"

// HAS_TMR: any TMR scheme (STMR, CTMR, or FTMR)
`ifdef TARGET_STMR
  `define HAS_TMR
`endif
`ifdef TARGET_CTMR
  `define HAS_TMR
`endif
`ifdef TARGET_FTMR
  `define HAS_TMR
`endif

// FLIT_TMR: flit triplicated and thus need border voters (CTMR or FTMR)
`ifdef TARGET_CTMR
  `define FLIT_TMR
`endif
`ifdef TARGET_FTMR
  `define FLIT_TMR
`endif

// --------------------------------------------------------------------------
// Wrapper: single-copy external ports, macro-gated DUT selection internally.
// --------------------------------------------------------------------------
module floo_nw_router_fi_dut_wrapper #(
  parameter int unsigned NumRoutes = floo_test_pkg::NumRoutes,
  parameter int unsigned NumInputs = NumRoutes,
  parameter int unsigned NumOutputs = NumRoutes,
  parameter type id_t = logic,
  parameter int unsigned NumAddrRules = 1,
  parameter type addr_rule_t = logic,
  parameter type hdr_t = logic,
  parameter type floo_req_t = logic,
  parameter type floo_rsp_t = logic,
  parameter type floo_wide_t = logic,
  `ifdef TARGET_RELNOC
  parameter type relfloo_req_t = logic,
  parameter type relfloo_rsp_t = logic,
  parameter type relfloo_wide_t = logic,
  parameter type floo_req_chan_t = logic,
  parameter type relfloo_req_chan_t = logic,
  parameter type floo_rsp_chan_t = logic,
  parameter type relfloo_rsp_chan_t = logic,
  parameter type floo_wide_chan_t = logic,
  parameter type relfloo_wide_chan_t = logic,
  `endif

  parameter int unsigned NumEndpoints = 5
) (
  input   logic       clk_i,
  input   logic       rst_ni,
  input   id_t        id_i,
  input   addr_rule_t [NumAddrRules-1:0] id_route_map_i,
  input   floo_req_t  [NumInputs-1:0] floo_req_i,
  input   floo_rsp_t  [NumOutputs-1:0] floo_rsp_i,
  output  floo_req_t  [NumOutputs-1:0] floo_req_o,
  output  floo_rsp_t  [NumInputs-1:0] floo_rsp_o,
  input   floo_wide_t [NumRoutes-1:0] floo_wide_i,
  output  floo_wide_t [NumRoutes-1:0] floo_wide_o,

  input logic [NumEndpoints-1:0][1:0] end_of_sim_endpoints,
  input logic end_of_sim_monitor
);

  // Defensive: TARGET_STMR / TARGET_CTMR / TARGET_FTMR are mutually exclusive
  `ifdef TARGET_CTMR
  `ifdef TARGET_FTMR
    initial $fatal(1, "TARGET_CTMR and TARGET_FTMR are mutually exclusive");
  `endif
  `endif
  `ifdef TARGET_STMR
  `ifdef TARGET_CTMR
    initial $fatal(1, "TARGET_STMR and TARGET_CTMR are mutually exclusive");
  `endif
  `ifdef TARGET_FTMR
    initial $fatal(1, "TARGET_STMR and TARGET_FTMR are mutually exclusive");
  `endif
  `endif

  // --------------------------------------------------------------------
  // Strobe-facing signals: declared unconditionally so strobe.sv stays
  // config-agnostic. Unused branches drive them to 0.
  // --------------------------------------------------------------------
  logic                  dut_error;
  logic                  border_error;
  logic [NumOutputs-1:0] dut_req_replica_mismatch;
  logic [NumInputs-1:0]  dut_rsp_replica_mismatch;
  logic [NumRoutes-1:0]  dut_wide_replica_mismatch;

  // ====================================================================
  // BASELINE / STMR
  // Single-copy I/O. TARGET_STMR swaps the module to floo_nw_routerTMR
  // (state-only TMR) which keeps the same port list but exports a single
  // combined tmrError voter-error output.
  // ====================================================================

  `ifdef TARGET_FTMR
  logic tmrErrorA, tmrErrorB, tmrErrorC;
  `elsif TARGET_STMR
  logic tmrError;
  `elsif TARGET_RELNOC
  logic relErrorCorr, relErrorDet;
  `endif

  `ifdef FLIT_TMR
    floo_req_t  [NumOutputs-1:0] req_oA, req_oB, req_oC;
    floo_rsp_t  [NumInputs-1:0]  rsp_oA, rsp_oB, rsp_oC;
    floo_wide_t [NumRoutes-1:0]  wide_oA, wide_oB, wide_oC;
  `endif

  `ifndef TARGET_NETLIST
    `ifdef HAS_TMR
    floo_nw_routerTMR #(
    `elsif TARGET_RELNOC
    relfloo_req_t  [NumInputs-1:0]  relfloo_req_in;
    relfloo_req_t  [NumOutputs-1:0] relfloo_req_out;
    relfloo_rsp_t  [NumOutputs-1:0] relfloo_rsp_in;
    relfloo_rsp_t  [NumInputs-1:0]  relfloo_rsp_out;
    relfloo_wide_t [NumRoutes-1:0]  relfloo_wide_in;
    relfloo_wide_t [NumRoutes-1:0]  relfloo_wide_out;
    
    ////////////////////
    // FLIT ENCODER   //
    ////////////////////
    for (genvar in = 0; in < NumInputs; in++) begin : gen_req_in
      relfloo_encoder #(
        .chan_t     ( floo_req_chan_t        ),
        .rel_chan_t ( relfloo_req_chan_t     )
      ) i_req_rel_enc (
        .valid_i    ( floo_req_i[in].valid ),
        .ready_i    ( floo_req_i[in].ready ),
        .chan_i     ( floo_req_i[in].req   ),
        .valid_o    ( relfloo_req_in[in].valid       ),
        .ready_o    ( relfloo_req_in[in].ready       ),
        .chan_o     ( relfloo_req_in[in].req         )
      );
    end

    for (genvar out = 0; out < NumOutputs; out++) begin : gen_rsp_in
      relfloo_encoder #(
        .chan_t     ( floo_rsp_chan_t        ),
        .rel_chan_t ( relfloo_rsp_chan_t     )
      ) i_rsp_rel_enc (
        .valid_i    ( floo_rsp_i[out].valid ),
        .ready_i    ( floo_rsp_i[out].ready ),
        .chan_i     ( floo_rsp_i[out].rsp   ),
        .valid_o    ( relfloo_rsp_in[out].valid       ),
        .ready_o    ( relfloo_rsp_in[out].ready       ),
        .chan_o     ( relfloo_rsp_in[out].rsp         )
      );
    end

    for (genvar r = 0; r < NumRoutes; r++) begin : gen_wide_in
      relfloo_encoder #(
        .chan_t     ( floo_wide_chan_t         ),
        .rel_chan_t ( relfloo_wide_chan_t      )
      ) i_wide_rel_enc (
        .valid_i    ( floo_wide_i[r].valid  ),
        .ready_i    ( floo_wide_i[r].ready  ),
        .chan_i     ( floo_wide_i[r].wide   ),
        .valid_o    ( relfloo_wide_in[r].valid        ),
        .ready_o    ( relfloo_wide_in[r].ready        ),
        .chan_o     ( relfloo_wide_in[r].wide         )
      );
    end

    ////////////////////
    // FLIT DECODER   //
    ////////////////////
    for (genvar out = 0; out < NumOutputs; out++) begin : gen_req_out
      relfloo_decoder #(
        .chan_t     ( floo_req_chan_t        ),
        .rel_chan_t ( relfloo_req_chan_t     )
      ) i_req_rel_dec (
        .valid_i    ( relfloo_req_out[out].valid       ),
        .ready_i    ( relfloo_req_out[out].ready       ),
        .chan_i     ( relfloo_req_out[out].req         ),
        .valid_o    ( floo_req_o[out].valid ),
        .ready_o    ( floo_req_o[out].ready ),
        .chan_o     ( floo_req_o[out].req   )
      );
    end

    for (genvar in = 0; in < NumInputs; in++) begin : gen_rsp_out
      relfloo_decoder #(
        .chan_t     ( floo_rsp_chan_t        ),
        .rel_chan_t ( relfloo_rsp_chan_t     )
      ) i_rsp_rel_dec (
        .valid_i    ( relfloo_rsp_out[in].valid       ),
        .ready_i    ( relfloo_rsp_out[in].ready       ),
        .chan_i     ( relfloo_rsp_out[in].rsp         ),
        .valid_o    ( floo_rsp_o[in].valid ),
        .ready_o    ( floo_rsp_o[in].ready ),
        .chan_o     ( floo_rsp_o[in].rsp   )
      );
    end

    for (genvar r = 0; r < NumRoutes; r++) begin : gen_wide_out
      relfloo_decoder #(
        .chan_t     ( floo_wide_chan_t         ),
        .rel_chan_t ( relfloo_wide_chan_t      )
      ) i_wide_rel_dec (
        .valid_i    ( relfloo_wide_out[r].valid        ),
        .ready_i    ( relfloo_wide_out[r].ready        ),
        .chan_i     ( relfloo_wide_out[r].wide         ),
        .valid_o    ( floo_wide_o[r].valid ),
        .ready_o    ( floo_wide_o[r].ready ),
        .chan_o     ( floo_wide_o[r].wide   )
      ); 
    end
    relfloo_nw_router #(
    `else
    floo_nw_router #(
    `endif
      .AxiCfgN      ( floo_test_pkg::AxiCfgN          ),
      .AxiCfgW      ( floo_test_pkg::AxiCfgW          ),
      .RouteAlgo    ( floo_pkg::XYRouting             ),
      .NumRoutes    ( floo_pkg::NumDirections         ),
      .InFifoDepth  ( floo_test_pkg::ChannelFifoDepth ),
      .OutFifoDepth ( floo_test_pkg::OutputFifoDepth  ),
      .id_t         ( id_t                            ),
      .NumAddrRules ( NumAddrRules                    ),
      .addr_rule_t  ( addr_rule_t                     ),
      .hdr_t        ( hdr_t                           ),
      `ifdef TARGET_RELNOC
      .floo_req_t   ( relfloo_req_t                      ),
      .floo_rsp_t   ( relfloo_rsp_t                      ),
      .floo_wide_t  ( relfloo_wide_t                     ),
      `else
      .floo_req_t   ( floo_req_t                      ),
      .floo_rsp_t   ( floo_rsp_t                      ),
      .floo_wide_t  ( floo_wide_t                     ),
      `endif
      .red_wide_req_t(),
      .red_wide_rsp_t(),
      .red_narrow_req_t(),
      .red_narrow_rsp_t()
    ) i_dut (
      `ifdef HAS_TMR // triplicated clk and rst
        .clk_iA         ( clk_i                 ),
        .clk_iB         ( clk_i                 ),
        .clk_iC         ( clk_i                 ),
        .rst_niA        ( rst_ni                ),
        .rst_niB        ( rst_ni                ),
        .rst_niC        ( rst_ni                ),
      `else // baseline: single clock and reset
        .clk_i           ( clk_i                 ),
        .rst_ni          ( rst_ni                ),
      `endif // HAS_TMR

      `ifdef FLIT_TMR // CTMR and FTMR: triplicated other ports
        .test_enable_iA  ( 1'b0                  ),
        .test_enable_iB  ( 1'b0                  ),
        .test_enable_iC  ( 1'b0                  ),
        .id_iA           ( id_i                  ),
        .id_iB           ( id_i                  ),
        .id_iC           ( id_i                  ),
        .id_route_map_iA ( id_route_map_i        ),
        .id_route_map_iB ( id_route_map_i        ),
        .id_route_map_iC ( id_route_map_i        ),
        .floo_req_iA     ( floo_req_i            ),
        .floo_req_iB     ( floo_req_i            ),
        .floo_req_iC     ( floo_req_i            ),
        .floo_rsp_iA     ( floo_rsp_i            ),
        .floo_rsp_iB     ( floo_rsp_i            ),
        .floo_rsp_iC     ( floo_rsp_i            ),
        .floo_req_oA     ( req_oA                ),
        .floo_req_oB     ( req_oB                ),
        .floo_req_oC     ( req_oC                ),
        .floo_rsp_oA     ( rsp_oA                ),
        .floo_rsp_oB     ( rsp_oB                ),
        .floo_rsp_oC     ( rsp_oC                ),
        .floo_wide_iA    ( floo_wide_i           ),
        .floo_wide_iB    ( floo_wide_i           ),
        .floo_wide_iC    ( floo_wide_i           ),
        .floo_wide_oA    ( wide_oA               ),
        .floo_wide_oB    ( wide_oB               ),
        .floo_wide_oC    ( wide_oC               )
      `elsif TARGET_RELNOC
        .test_enable_i  ( 1'b0                  ),
        .id_i           ( {id_i,id_i,id_i}      ),
        .id_route_map_i ( {3{id_route_map_i}}   ),
        .floo_req_i     ( relfloo_req_in            ),
        .floo_rsp_i     ( relfloo_rsp_in            ),
        .floo_req_o     ( relfloo_req_out            ),
        .floo_rsp_o     ( relfloo_rsp_out            ),
        .floo_wide_i    ( relfloo_wide_in           ),
        .floo_wide_o    ( relfloo_wide_out           ),
      `else // baseline and STMR: single-copy ports
        .test_enable_i  ( 1'b0                  ),
        .id_i           ( id_i                  ),
        .id_route_map_i ( id_route_map_i        ),
        .floo_req_i     ( floo_req_i            ),
        .floo_rsp_i     ( floo_rsp_i            ),
        .floo_req_o     ( floo_req_o            ),
        .floo_rsp_o     ( floo_rsp_o            ),
        .floo_wide_i    ( floo_wide_i           ),
        .floo_wide_o    ( floo_wide_o           ),
      `endif // FLIT_TMR
        .offload_wide_req_o(),
        .offload_wide_rsp_i(),
        .offload_narrow_req_o(),
        .offload_narrow_rsp_i()
      `ifdef TARGET_STMR
        , .tmrError       ( tmrError              )
      `endif
      `ifdef TARGET_FTMR
        , .tmrErrorA      ( tmrErrorA             )
        , .tmrErrorB      ( tmrErrorB             )
        , .tmrErrorC      ( tmrErrorC             )
      `endif
      `ifdef TARGET_RELNOC
        , .faults_o       ({relErrorDet,relErrorCorr})
      `endif
    );
  `else  // TARGET_NETLIST (baseline only — STMR netlist not supported)
  // Synth wrapper: scalar id_route_map_i, no parameter list.
    `ifndef HAS_TMR
    floo_synth_nw_router i_dut (
      .clk_i          ( clk_i                 ),
      .rst_ni         ( rst_ni                ),
      .test_enable_i  ( 1'b0                  ),
      .id_i           ( id_i                  ),
      .id_route_map_i ( id_route_map_i[0]     ),
      .floo_req_i     ( floo_req_i            ),
      .floo_rsp_i     ( floo_rsp_i            ),
      .floo_req_o     ( floo_req_o            ),
      .floo_rsp_o     ( floo_rsp_o            ),
      .floo_wide_i    ( floo_wide_i           ),
      .floo_wide_o    ( floo_wide_o           )
    );
    `else
    floo_synth_nw_routerTMR i_dut (
      .clk_iA          ( clk_i                 ),
      .clk_iB          ( clk_i                 ),
      .clk_iC          ( clk_i                 ),
      .rst_niA         ( rst_ni                ),
      .rst_niB         ( rst_ni                ),
      .rst_niC         ( rst_ni                ),
      `ifndef TARGET_STMR
        .test_enable_iA  ( 1'b0                  ),
        .test_enable_iB  ( 1'b0                  ),
        .test_enable_iC  ( 1'b0                  ),
        .id_iA           ( id_i                  ),
        .id_iB           ( id_i                  ),
        .id_iC           ( id_i                  ),
        .id_route_map_iA ( id_route_map_i[0]     ),
        .id_route_map_iB ( id_route_map_i[0]     ),
        .id_route_map_iC ( id_route_map_i[0]     ),
        .floo_req_iA     ( floo_req_i            ),
        .floo_req_iB     ( floo_req_i            ),
        .floo_req_iC     ( floo_req_i            ),
        .floo_rsp_iA     ( floo_rsp_i            ),
        .floo_rsp_iB     ( floo_rsp_i            ),
        .floo_rsp_iC     ( floo_rsp_i            ),
        .floo_req_oA     ( req_oA                ),
        .floo_req_oB     ( req_oB                ),
        .floo_req_oC     ( req_oC                ),
        .floo_rsp_oA     ( rsp_oA                ),
        .floo_rsp_oB     ( rsp_oB                ),
        .floo_rsp_oC     ( rsp_oC                ),
        .floo_wide_iA    ( floo_wide_i           ),
        .floo_wide_iB    ( floo_wide_i           ),
        .floo_wide_iC    ( floo_wide_i           ),
        .floo_wide_oA    ( wide_oA               ),
        .floo_wide_oB    ( wide_oB               ),
        .floo_wide_oC    ( wide_oC               )
        `ifdef TARGET_FTMR
        , .tmrErrorA       ( tmrErrorA             )
        , .tmrErrorB       ( tmrErrorB             )
        , .tmrErrorC       ( tmrErrorC             )
        `endif
      `else // TARGET_STMR
        .test_enable_i  ( 1'b0                  ),
        .id_i           ( id_i                  ),
        .id_route_map_i ( id_route_map_i[0]     ),
        .floo_req_i     ( floo_req_i            ),
        .floo_rsp_i     ( floo_rsp_i            ),
        .floo_req_o     ( floo_req_o            ),
        .floo_rsp_o     ( floo_rsp_o            ),
        .floo_wide_i    ( floo_wide_i           ),
        .floo_wide_o    ( floo_wide_o           ),
        .tmrError       ( tmrError              )
      `endif
    );
    `endif // FLIT_TMR
  `endif // TARGET_NETLIST

  `ifdef TARGET_FTMR
    assign dut_error = tmrErrorA | tmrErrorB | tmrErrorC;
  `elsif TARGET_STMR
    assign dut_error = tmrError;
  `elsif TARGET_RELNOC
    assign dut_error = relErrorCorr | relErrorDet;
  `else
    assign dut_error = 1'b0;
  `endif

  // --------------------------------------------------------------------
  // Border voter + per-port replica mismatch (CTMR / FTMR).
  //
  // Inlined Classical_MV majority `(A&B) | (B&C) | (A&C)` per port instead
  // of instancing `bitwise_TMR_voter_fail`, and inlined pairwise mismatch
  // `(A!==B) || (B!==C)` (AB+BC is transitive over equality). Both share
  // the same A/B/C inputs, so they live in one generate block.
  //
  // `border_error` is OR-reduced from the mismatch flags rather than the
  // voter's `fault_detected` cone — Z01X concurrent-FM redundancy-collapses
  // the TMR voter cone, dead-coding `fault_detected_o` to 0 in FM. The
  // explicit `!==` pairwise compare reads A/B/C directly so Z01X keeps
  // them observed and the FM-side mismatch propagates to $fs_compare.
  //
  // `!==` (X-strict) returns a clean 0/1 even with X on a replica, so the
  // strobe never sees an X-tainted compare result.
  // --------------------------------------------------------------------
  `ifdef FLIT_TMR
    for (genvar i = 0; i < NumOutputs; i++) begin: gen_req_border
      assign floo_req_o[i] =
          (req_oA[i] & req_oB[i]) | (req_oB[i] & req_oC[i]) | (req_oA[i] & req_oC[i]);
      assign dut_req_replica_mismatch[i] =
          (req_oA[i] !== req_oB[i]) || (req_oB[i] !== req_oC[i]);
    end
    for (genvar i = 0; i < NumInputs; i++) begin: gen_rsp_border
      assign floo_rsp_o[i] =
          (rsp_oA[i] & rsp_oB[i]) | (rsp_oB[i] & rsp_oC[i]) | (rsp_oA[i] & rsp_oC[i]);
      assign dut_rsp_replica_mismatch[i] =
          (rsp_oA[i] !== rsp_oB[i]) || (rsp_oB[i] !== rsp_oC[i]);
    end
    for (genvar i = 0; i < NumRoutes; i++) begin: gen_wide_border
      assign floo_wide_o[i] =
          (wide_oA[i] & wide_oB[i]) | (wide_oB[i] & wide_oC[i]) | (wide_oA[i] & wide_oC[i]);
      assign dut_wide_replica_mismatch[i] =
          (wide_oA[i] !== wide_oB[i]) || (wide_oB[i] !== wide_oC[i]);
    end
    assign border_error =
        (|dut_req_replica_mismatch) | (|dut_rsp_replica_mismatch) | (|dut_wide_replica_mismatch);
  `else
    assign border_error              = 1'b0;
    assign dut_req_replica_mismatch  = '0;
    assign dut_rsp_replica_mismatch  = '0;
    assign dut_wide_replica_mismatch = '0;
  `endif

  // ====================================================================
  // In-wrapper scoreboard for FM-aware interface_error / leftover detection
  // --------------------------------------------------------------------
  // For each (input_port, output_port, channel) bucket we shadow the flits
  // that have been pushed into the router but not yet emitted, using a
  // synthesizable fifo_v3 (so it stays FM-aware under VC Z01X concurrent
  // mode — smart queues `[$]` are unsupported there and fall to IA).
  //
  //   Push: input_port handshake whose flit.dst_id (XY-routed against
  //         this router's id_i) selects output_port.
  //   Pop:  output_port handshake whose observed flit matches the FIFO
  //         front of one of the input_port buckets feeding it. The match
  //         search is order-agnostic across inputs to decouple from the
  //         router's internal arbiter.
  //
  // Aggregated outputs:
  //   interface_error    — any output handshake whose flit cannot be
  //                        matched to any input bucket front (router
  //                        invented / corrupted / mis-routed a flit).
  //   any_fifo_leftover  — at least one bucket non-empty (used in the
  //                        strobe `final` block to escalate dropped-flit
  //                        faults to *F).
  // ====================================================================

  localparam int unsigned SbDepth =
      floo_test_pkg::ChannelFifoDepth + floo_test_pkg::OutputFifoDepth + 4;

  function automatic int unsigned expected_out_port(id_t self_id, id_t dst_id);
    if      (dst_id.x > self_id.x) return int'(floo_pkg::East);
    else if (dst_id.x < self_id.x) return int'(floo_pkg::West);
    else if (dst_id.y > self_id.y) return int'(floo_pkg::North);
    else if (dst_id.y < self_id.y) return int'(floo_pkg::South);
    else                           return int'(floo_pkg::Eject);
  endfunction

  // The fifo stores the whole link struct floo_<NAME>_t (in-scope as a
  // wrapper parameter). Comparison only uses the `.<NAME>` (chan) field —
  // valid is always 1 at handshake time, and `.ready` carries the OPPOSITE
  // direction's backward bit (unrelated to this side's handshake) so it
  // would cause spurious mismatches if included in the compare.
  `define DECLARE_SB_CHAN(NAME)                                                                    \
    floo_``NAME``_t [NumRoutes-1:0][NumRoutes-1:0] sb_``NAME``_front;                              \
    logic           [NumRoutes-1:0][NumRoutes-1:0] sb_``NAME``_empty;                              \
    logic           [NumRoutes-1:0][NumRoutes-1:0] sb_``NAME``_push;                               \
    logic           [NumRoutes-1:0][NumRoutes-1:0] sb_``NAME``_pop;                                \
    logic           [NumRoutes-1:0][NumRoutes-1:0] sb_``NAME``_match;                              \
    logic           [NumRoutes-1:0]                sb_``NAME``_out_mismatch;                       \
                                                                                                   \
    for (genvar i_g = 0; i_g < NumRoutes; i_g++) begin : gen_sb_``NAME``_in                        \
      for (genvar o_g = 0; o_g < NumRoutes; o_g++) begin : gen_sb_``NAME``_out                     \
        assign sb_``NAME``_push[i_g][o_g] =                                                        \
            floo_``NAME``_i[i_g].valid && floo_``NAME``_o[i_g].ready &&                            \
            (expected_out_port(id_i, floo_``NAME``_i[i_g].``NAME``.generic.hdr.dst_id) == o_g);    \
        cc_fifo #(                                                                                 \
          .FallThrough ( 1'b0                              ),                                     \
          .DataWidth   ( $bits(floo_``NAME``_t)            ),                                     \
          .Depth        ( SbDepth                           )                                      \
        ) i_sb_``NAME``_fifo (                                                                     \
          .clk_i        ( clk_i                             ),                                     \
          .rst_ni       ( rst_ni                            ),                                     \
          .flush_i      ( 1'b0                              ),                                     \
          .clr_i        ( 1'b0                              ),                                     \
          .full_o       (                                   ),                                     \
          .empty_o      ( sb_``NAME``_empty[i_g][o_g]       ),                                     \
          .usage_o      (                                   ),                                     \
          .data_i       ( floo_``NAME``_i[i_g]              ),                                     \
          .push_i       ( sb_``NAME``_push[i_g][o_g]        ),                                     \
          .data_o       ( sb_``NAME``_front[i_g][o_g]       ),                                     \
          .pop_i        ( sb_``NAME``_pop[i_g][o_g]         )                                      \
        );                                                                                         \
      end                                                                                          \
    end                                                                                            \
                                                                                                   \
    always_comb begin                                                                              \
      sb_``NAME``_pop          = '0;                                                               \
      sb_``NAME``_match        = '0;                                                               \
      sb_``NAME``_out_mismatch = '0;                                                               \
      for (int o = 0; o < NumRoutes; o++) begin                                                    \
        automatic logic out_hs    = floo_``NAME``_o[o].valid && floo_``NAME``_i[o].ready;          \
        automatic logic any_match = 1'b0;                                                          \
        for (int i = 0; i < NumRoutes; i++) begin                                                  \
          sb_``NAME``_match[i][o] = out_hs && !sb_``NAME``_empty[i][o] &&                          \
              (sb_``NAME``_front[i][o].``NAME`` === floo_``NAME``_o[o].``NAME``);                  \
          any_match = any_match | sb_``NAME``_match[i][o];                                         \
        end                                                                                        \
        sb_``NAME``_out_mismatch[o] = out_hs && !any_match;                                        \
        if (out_hs) begin                                                                          \
          for (int i = 0; i < NumRoutes; i++) begin                                                \
            if (sb_``NAME``_match[i][o]) begin                                                     \
              sb_``NAME``_pop[i][o] = 1'b1;                                                        \
              break;                                                                               \
            end                                                                                    \
          end                                                                                      \
        end                                                                                        \
      end                                                                                          \
    end

  `DECLARE_SB_CHAN(req)
  `DECLARE_SB_CHAN(rsp)
  `DECLARE_SB_CHAN(wide)

  `undef DECLARE_SB_CHAN

  logic interface_error;
  logic any_fifo_leftover;
  assign interface_error =
      (|sb_req_out_mismatch) | (|sb_rsp_out_mismatch) | (|sb_wide_out_mismatch);
  assign any_fifo_leftover =
      ~(&sb_req_empty) | ~(&sb_rsp_empty) | ~(&sb_wide_empty);

  // --------------------------------------------------------------------
  // End-of-simulation liveness signal for the strobe.
  // --------------------------------------------------------------------
  logic end_of_sim;
  assign end_of_sim = &end_of_sim_endpoints && end_of_sim_monitor;

  // --------------------------------------------------------------------
  // Flattened output signals for Zoix $fs_compare
  // --------------------------------------------------------------------
  localparam int FlooReqBits  = $bits(floo_req_t);
  localparam int FlooRspBits  = $bits(floo_rsp_t);
  localparam int FlooWideBits = $bits(floo_wide_t);

  logic [NumOutputs-1:0][FlooReqBits-1:0]  floo_req_o_flat;
  logic [NumInputs-1:0][FlooRspBits-1:0]   floo_rsp_o_flat;
  logic [NumRoutes-1:0][FlooWideBits-1:0]  floo_wide_o_flat;

  for (genvar i = 0; i < NumOutputs; i++) assign floo_req_o_flat[i]  = floo_req_o[i];
  for (genvar i = 0; i < NumInputs; i++)  assign floo_rsp_o_flat[i]  = floo_rsp_o[i];
  for (genvar i = 0; i < NumRoutes; i++)  assign floo_wide_o_flat[i] = floo_wide_o[i];

  // --------------------------------------------------------------------
  // Per-field-group output slices for the strobe's error-kind axis.
  // Each output link decomposes cleanly into three groups (packed union
  // forces .generic to span the whole chan, so hdr|payload tile it exactly):
  //   hdr  : .<chan>.generic.hdr      -> header corruption  (mis-route, ...)
  //   pl   : .<chan>.generic.payload  -> payload corruption (data wrong)
  //   hs   : {valid, ready}           -> handshake flip
  // The strobe runs a separate $fs_compare on each group to tag the kind.
  //
  // hdr/pl are VALID-GATED (masked to 0 when !valid): the chan data lines are
  // only meaningful during a valid beat. The output FIFO's holding register
  // drives the chan bus even on idle (valid=0) cycles, so an SEU on a stale
  // held flit would otherwise show up as a header/payload divergence (*H/*P)
  // although it is never transmitted — a masked fault mis-tagged as an
  // interface change. Gating by valid makes both GM and FM read 0 on idle
  // cycles, so only divergences on an actually-presented flit are counted
  // (a real send-time corruption, or a dropped beat where GM!=FM on valid).
  // hs is left ungated — a valid-bit flip IS the divergence to catch.
  // --------------------------------------------------------------------
  localparam int HdrBits        = $bits(hdr_t);
  localparam int FlooReqPlBits  = FlooReqBits  - 2 - HdrBits;
  localparam int FlooRspPlBits  = FlooRspBits  - 2 - HdrBits;
  localparam int FlooWidePlBits = FlooWideBits - 2 - HdrBits;

  logic [NumOutputs-1:0][HdrBits-1:0]       floo_req_o_hdr_flat;
  logic [NumInputs-1:0][HdrBits-1:0]        floo_rsp_o_hdr_flat;
  logic [NumRoutes-1:0][HdrBits-1:0]        floo_wide_o_hdr_flat;
  logic [NumOutputs-1:0][FlooReqPlBits-1:0] floo_req_o_pl_flat;
  logic [NumInputs-1:0][FlooRspPlBits-1:0]  floo_rsp_o_pl_flat;
  logic [NumRoutes-1:0][FlooWidePlBits-1:0] floo_wide_o_pl_flat;
  logic [NumOutputs-1:0][1:0]               floo_req_o_hs_flat;
  logic [NumInputs-1:0][1:0]                floo_rsp_o_hs_flat;
  logic [NumRoutes-1:0][1:0]                floo_wide_o_hs_flat;

  for (genvar i = 0; i < NumOutputs; i++) begin : gen_req_field_slice
    assign floo_req_o_hdr_flat[i] = floo_req_o[i].valid ? floo_req_o[i].req.generic.hdr     : '0;
    assign floo_req_o_pl_flat[i]  = floo_req_o[i].valid ? floo_req_o[i].req.generic.payload  : '0;
    assign floo_req_o_hs_flat[i]  = {floo_req_o[i].valid, floo_req_o[i].ready};
  end
  for (genvar i = 0; i < NumInputs; i++) begin : gen_rsp_field_slice
    assign floo_rsp_o_hdr_flat[i] = floo_rsp_o[i].valid ? floo_rsp_o[i].rsp.generic.hdr     : '0;
    assign floo_rsp_o_pl_flat[i]  = floo_rsp_o[i].valid ? floo_rsp_o[i].rsp.generic.payload  : '0;
    assign floo_rsp_o_hs_flat[i]  = {floo_rsp_o[i].valid, floo_rsp_o[i].ready};
  end
  for (genvar i = 0; i < NumRoutes; i++) begin : gen_wide_field_slice
    assign floo_wide_o_hdr_flat[i] = floo_wide_o[i].valid ? floo_wide_o[i].wide.generic.hdr    : '0;
    assign floo_wide_o_pl_flat[i]  = floo_wide_o[i].valid ? floo_wide_o[i].wide.generic.payload : '0;
    assign floo_wide_o_hs_flat[i]  = {floo_wide_o[i].valid, floo_wide_o[i].ready};
  end

  `ifdef TARGET_ZOIX
  `include "strobe.sv"
  `endif

endmodule


// =========================================================================
// Outer testbench. Mirrors tb_floo_nw_router.sv line-for-line except for
// the wrapper instance module name.
// =========================================================================
module tb_floo_nw_router_fi;

  import floo_pkg::*;

  localparam time CyclTime = 10ns;
  localparam time ApplTime = 2ns;
  localparam time TestTime = 8ns;

  localparam int unsigned NumEndpoints = 5;  // N, E, S, W, Eject
  // Keep the golden testcase alive after functional completion so a faulty
  // machine with a bounded timing shift can drain before the common cutoff.
  localparam int unsigned GraceCycles = 500;

  localparam int unsigned NarrowNumReads = 100;
  localparam int unsigned NarrowNumWrites = 100;
  localparam int unsigned WideNumReads = 100;
  localparam int unsigned WideNumWrites = 100;

  logic clk, rst_n;

  localparam chimney_cfg_t NarrowChimneyCfg = ChimneyDefaultCfg;
  localparam chimney_cfg_t WideChimneyCfg = ChimneyDefaultCfg;

  typedef logic [1:0] x_bits_t;
  typedef logic [1:0] y_bits_t;
  `FLOO_TYPEDEF_XY_NODE_ID_T(id_t, x_bits_t, y_bits_t, logic)
  `FLOO_TYPEDEF_HDR_T(hdr_t, id_t, id_t, nw_ch_e, logic)

  `FLOO_TYPEDEF_AXI_FROM_CFG(axi_narrow, floo_test_pkg::AxiCfgN)
  `FLOO_TYPEDEF_AXI_FROM_CFG(axi_wide,   floo_test_pkg::AxiCfgW)
  `FLOO_TYPEDEF_NW_CHAN_ALL(axi, req, rsp, wide, axi_narrow_in, axi_wide_in,
      floo_test_pkg::AxiCfgN, floo_test_pkg::AxiCfgW, hdr_t)
  `FLOO_TYPEDEF_NW_LINK_ALL(req, rsp, wide, req, rsp, wide)
  `RELFLOO_TYPEDEF_NW_CHAN_ALL(axi, req, rsp, wide, axi_narrow_in, axi_wide_in,
      floo_test_pkg::AxiCfgN, floo_test_pkg::AxiCfgW, hdr_t)
  `RELFLOO_TYPEDEF_NW_LINK_ALL(req, rsp, wide, req, rsp, wide) 

  axi_narrow_in_req_t  chimney_narrow_in_req;
  axi_narrow_in_rsp_t  chimney_narrow_in_rsp;
  axi_narrow_out_req_t chimney_narrow_out_req;
  axi_narrow_out_rsp_t chimney_narrow_out_rsp;

  axi_wide_in_req_t    chimney_wide_in_req;
  axi_wide_in_rsp_t    chimney_wide_in_rsp;
  axi_wide_out_req_t   chimney_wide_out_req;
  axi_wide_out_rsp_t   chimney_wide_out_rsp;

  floo_req_t [3-1:0][3-1:0][Eject:North] floo_req_in, floo_req_out;
  floo_rsp_t [3-1:0][3-1:0][Eject:North] floo_rsp_in, floo_rsp_out;
  floo_wide_t [3-1:0][3-1:0][Eject:North] floo_wide_in, floo_wide_out;

  floo_req_t [3-1:0][3-1:0] floo_req_in_eject, floo_req_out_eject;
  floo_rsp_t [3-1:0][3-1:0] floo_rsp_in_eject, floo_rsp_out_eject;
  floo_wide_t [3-1:0][3-1:0] floo_wide_in_eject, floo_wide_out_eject;

  floo_req_t tile_req_eject_in  [NumEndpoints-1:0];
  floo_req_t tile_req_eject_out [NumEndpoints-1:0];
  floo_rsp_t tile_rsp_eject_in  [NumEndpoints-1:0];
  floo_rsp_t tile_rsp_eject_out [NumEndpoints-1:0];
  floo_wide_t tile_wide_eject_in  [NumEndpoints-1:0];
  floo_wide_t tile_wide_eject_out [NumEndpoints-1:0];

  logic mesh_end_of_sim;

  logic [NumEndpoints-1:0][1:0] end_of_sim_endpoints;

  for (genvar x = 0; x < 3; x++) begin : gen_eject_slice_x
    for (genvar y = 0; y < 3; y++) begin : gen_eject_slice_y
      assign floo_req_in_eject[x][y]  = floo_req_in[x][y][Eject];
      assign floo_req_out_eject[x][y] = floo_req_out[x][y][Eject];
      assign floo_rsp_in_eject[x][y]  = floo_rsp_in[x][y][Eject];
      assign floo_rsp_out_eject[x][y] = floo_rsp_out[x][y][Eject];
      assign floo_wide_in_eject[x][y] = floo_wide_in[x][y][Eject];
      assign floo_wide_out_eject[x][y] = floo_wide_out[x][y][Eject];
    end
  end

  assign floo_req_in[1][2][Eject]  = tile_req_eject_in[North];
  assign floo_req_out[1][2][Eject] = tile_req_eject_out[North];
  assign floo_rsp_in[1][2][Eject]  = tile_rsp_eject_in[North];
  assign floo_rsp_out[1][2][Eject] = tile_rsp_eject_out[North];
  assign floo_wide_in[1][2][Eject]  = tile_wide_eject_in[North];
  assign floo_wide_out[1][2][Eject] = tile_wide_eject_out[North];

  assign floo_req_in[1][0][Eject]  = tile_req_eject_in[South];
  assign floo_req_out[1][0][Eject] = tile_req_eject_out[South];
  assign floo_rsp_in[1][0][Eject]  = tile_rsp_eject_in[South];
  assign floo_rsp_out[1][0][Eject] = tile_rsp_eject_out[South];
  assign floo_wide_in[1][0][Eject]  = tile_wide_eject_in[South];
  assign floo_wide_out[1][0][Eject] = tile_wide_eject_out[South];

  assign floo_req_in[2][1][Eject]  = tile_req_eject_in[East];
  assign floo_req_out[2][1][Eject] = tile_req_eject_out[East];
  assign floo_rsp_in[2][1][Eject]  = tile_rsp_eject_in[East];
  assign floo_rsp_out[2][1][Eject] = tile_rsp_eject_out[East];
  assign floo_wide_in[2][1][Eject]  = tile_wide_eject_in[East];
  assign floo_wide_out[2][1][Eject] = tile_wide_eject_out[East];

  assign floo_req_in[0][1][Eject]  = tile_req_eject_in[West];
  assign floo_req_out[0][1][Eject] = tile_req_eject_out[West];
  assign floo_rsp_in[0][1][Eject]  = tile_rsp_eject_in[West];
  assign floo_rsp_out[0][1][Eject] = tile_rsp_eject_out[West];
  assign floo_wide_in[0][1][Eject]  = tile_wide_eject_in[West];
  assign floo_wide_out[0][1][Eject] = tile_wide_eject_out[West];

  clk_rst_gen #(
    .ClkPeriod    ( CyclTime ),
    .RstClkCycles ( 5        )
  ) i_clk_gen (
    .clk_o  ( clk   ),
    .rst_no ( rst_n )
  );

  typedef struct packed {
    int unsigned  idx;
    axi_narrow_addr_t start_addr;
    axi_narrow_addr_t end_addr;
  } node_addr_region_t;

  localparam int unsigned NumAddrRegions = 5;
  localparam node_addr_region_t [NumAddrRegions-1:0] AddrRegions = '{
    '{idx: North, start_addr: 48'h00000000, end_addr: 48'h0000FFFF},
    '{idx: South, start_addr: 48'h00010000, end_addr: 48'h0001FFFF},
    '{idx: East,  start_addr: 48'h00100000, end_addr: 48'h0010FFFF},
    '{idx: West,  start_addr: 48'h00110000, end_addr: 48'h0011FFFF},
    '{idx: Eject, start_addr: 48'h00120000, end_addr: 48'h0012FFFF}
  };

  localparam int unsigned NumAddrRegionsNS = 4;
  localparam int unsigned NumAddrRegionsEW = 4;
  localparam int unsigned NumAddrRegionsEject = 4;

  localparam node_addr_region_t [NumAddrRegionsEject-1:0] EjectAddrRegions = '{
    '{idx: West,  start_addr: 48'h00100000, end_addr: 48'h0010FFFF},
    '{idx: South, start_addr: 48'h00010000, end_addr: 48'h0001FFFF},
    '{idx: East,  start_addr: 48'h00120000, end_addr: 48'h0012FFFF},
    '{idx: North, start_addr: 48'h00210000, end_addr: 48'h0021FFFF}
  };
  localparam node_addr_region_t [NumAddrRegionsNS-1:0] NorthAddrRegions = '{
    '{idx: Eject, start_addr: 48'h00110000, end_addr: 48'h0011FFFF},
    '{idx: South, start_addr: 48'h00010000, end_addr: 48'h0001FFFF},
    '{idx: East,  start_addr: 48'h00120000, end_addr: 48'h0012FFFF},
    '{idx: West,  start_addr: 48'h00100000, end_addr: 48'h0010FFFF}
  };
  localparam node_addr_region_t [NumAddrRegionsEW-1:0] EastAddrRegions = '{
    '{idx: Eject, start_addr: 48'h00110000, end_addr: 48'h0011FFFF},
    '{idx: West,  start_addr: 48'h00100000, end_addr: 48'h0010FFFF},
    '{idx: South, start_addr: 48'h00010000, end_addr: 48'h0001FFFF},
    '{idx: North, start_addr: 48'h00210000, end_addr: 48'h0021FFFF}
  };
  localparam node_addr_region_t [NumAddrRegionsNS-1:0] SouthAddrRegions = '{
    '{idx: Eject, start_addr: 48'h00110000, end_addr: 48'h0011FFFF},
    '{idx: North, start_addr: 48'h00210000, end_addr: 48'h0021FFFF},
    '{idx: East,  start_addr: 48'h00120000, end_addr: 48'h0012FFFF},
    '{idx: West,  start_addr: 48'h00100000, end_addr: 48'h0010FFFF}
  };
  localparam node_addr_region_t [NumAddrRegionsEW-1:0] WestAddrRegions = '{
    '{idx: Eject, start_addr: 48'h00110000, end_addr: 48'h0011FFFF},
    '{idx: South, start_addr: 48'h00010000, end_addr: 48'h0001FFFF},
    '{idx: East,  start_addr: 48'h00120000, end_addr: 48'h0012FFFF},
    '{idx: North, start_addr: 48'h00210000, end_addr: 48'h0021FFFF}
  };

  // NESW Endpoint Tiles
    floo_nw_tile #(
    .DELAY ( 10 ),
    .ApplTime ( ApplTime ),
    .TestTime ( TestTime ),
    .NarrowNumReads ( NarrowNumReads ),
    .NarrowNumWrites ( NarrowNumWrites ),
    .WideNumReads ( WideNumReads ),
    .WideNumWrites ( WideNumWrites ),
    .NumAddrRegions ( NumAddrRegionsNS ),
    .node_addr_region_t ( node_addr_region_t ),
    .AddrRegions ( NorthAddrRegions ),
    .id_t ( id_t ),
    .hdr_t ( hdr_t ),
    .axi_narrow_in_req_t ( axi_narrow_in_req_t ),
    .axi_narrow_in_rsp_t ( axi_narrow_in_rsp_t ),
    .axi_narrow_out_req_t ( axi_narrow_out_req_t ),
    .axi_narrow_out_rsp_t ( axi_narrow_out_rsp_t ),
    .axi_wide_in_req_t ( axi_wide_in_req_t ),
    .axi_wide_in_rsp_t ( axi_wide_in_rsp_t ),
    .axi_wide_out_req_t ( axi_wide_out_req_t ),
    .axi_wide_out_rsp_t ( axi_wide_out_rsp_t ),
    .floo_req_t ( floo_req_t ),
    .floo_rsp_t ( floo_rsp_t ),
    .floo_wide_t ( floo_wide_t )
  ) i_North_tile (
    .clk_i      ( clk                 ),
    .rst_ni     ( rst_n               ),
    .id_i       ( '{x: 2'd1, y: 2'd2, port_id: 1'd0} ),
    .floo_req_i ( floo_req_in[1][2][West:North] ),
    .floo_rsp_i ( floo_rsp_in[1][2][West:North] ),
    .floo_req_o ( floo_req_out[1][2][West:North] ),
    .floo_rsp_o ( floo_rsp_out[1][2][West:North] ),
    .floo_wide_i ( floo_wide_in[1][2][West:North] ),
    .floo_wide_o ( floo_wide_out[1][2][West:North] ),
    .floo_req_Eject_in_o  ( tile_req_eject_in[North]  ),
    .floo_req_Eject_out_o ( tile_req_eject_out[North] ),
    .floo_rsp_Eject_in_o  ( tile_rsp_eject_in[North]  ),
    .floo_rsp_Eject_out_o ( tile_rsp_eject_out[North] ),
    .floo_wide_Eject_in_o ( tile_wide_eject_in[North] ),
    .floo_wide_Eject_out_o( tile_wide_eject_out[North]),
    .end_of_sim ( end_of_sim_endpoints[North]        )
  );

    floo_nw_tile #(
    .DELAY ( 20 ),
    .ApplTime ( ApplTime ),
    .TestTime ( TestTime ),
    .NarrowNumReads ( NarrowNumReads ),
    .NarrowNumWrites ( NarrowNumWrites ),
    .WideNumReads ( WideNumReads ),
    .WideNumWrites ( WideNumWrites ),
    .NumAddrRegions ( NumAddrRegionsNS ),
    .node_addr_region_t ( node_addr_region_t ),
    .AddrRegions ( SouthAddrRegions ),
    .id_t ( id_t ),
    .hdr_t ( hdr_t ),
    .axi_narrow_in_req_t ( axi_narrow_in_req_t ),
    .axi_narrow_in_rsp_t ( axi_narrow_in_rsp_t ),
    .axi_narrow_out_req_t ( axi_narrow_out_req_t ),
    .axi_narrow_out_rsp_t ( axi_narrow_out_rsp_t ),
    .axi_wide_in_req_t ( axi_wide_in_req_t ),
    .axi_wide_in_rsp_t ( axi_wide_in_rsp_t ),
    .axi_wide_out_req_t ( axi_wide_out_req_t ),
    .axi_wide_out_rsp_t ( axi_wide_out_rsp_t ),
    .floo_req_t ( floo_req_t ),
    .floo_rsp_t ( floo_rsp_t ),
    .floo_wide_t ( floo_wide_t )
  ) i_South_tile (
    .clk_i      ( clk                 ),
    .rst_ni     ( rst_n               ),
    .id_i       ( '{x: 2'd1, y: 2'd0, port_id: 1'd0} ),
    .floo_req_i ( floo_req_in[1][0][West:North] ),
    .floo_rsp_i ( floo_rsp_in[1][0][West:North] ),
    .floo_req_o ( floo_req_out[1][0][West:North] ),
    .floo_rsp_o ( floo_rsp_out[1][0][West:North] ),
    .floo_wide_i ( floo_wide_in[1][0][West:North] ),
    .floo_wide_o ( floo_wide_out[1][0][West:North] ),
    .floo_req_Eject_in_o  ( tile_req_eject_in[South]  ),
    .floo_req_Eject_out_o ( tile_req_eject_out[South] ),
    .floo_rsp_Eject_in_o  ( tile_rsp_eject_in[South]  ),
    .floo_rsp_Eject_out_o ( tile_rsp_eject_out[South] ),
    .floo_wide_Eject_in_o ( tile_wide_eject_in[South] ),
    .floo_wide_Eject_out_o( tile_wide_eject_out[South]),
    .end_of_sim ( end_of_sim_endpoints[South]        )
  );

    floo_nw_tile #(
    .DELAY ( 30 ),
    .ApplTime ( ApplTime ),
    .TestTime ( TestTime ),
    .NarrowNumReads ( NarrowNumReads ),
    .NarrowNumWrites ( NarrowNumWrites ),
    .WideNumReads ( WideNumReads ),
    .WideNumWrites ( WideNumWrites ),
    .NumAddrRegions ( NumAddrRegionsEW ),
    .node_addr_region_t ( node_addr_region_t ),
    .AddrRegions ( EastAddrRegions ),
    .id_t ( id_t ),
    .hdr_t ( hdr_t ),
    .axi_narrow_in_req_t ( axi_narrow_in_req_t ),
    .axi_narrow_in_rsp_t ( axi_narrow_in_rsp_t ),
    .axi_narrow_out_req_t ( axi_narrow_out_req_t ),
    .axi_narrow_out_rsp_t ( axi_narrow_out_rsp_t ),
    .axi_wide_in_req_t ( axi_wide_in_req_t ),
    .axi_wide_in_rsp_t ( axi_wide_in_rsp_t ),
    .axi_wide_out_req_t ( axi_wide_out_req_t ),
    .axi_wide_out_rsp_t ( axi_wide_out_rsp_t ),
    .floo_req_t ( floo_req_t ),
    .floo_rsp_t ( floo_rsp_t ),
    .floo_wide_t ( floo_wide_t )
  ) i_East_tile (
    .clk_i      ( clk                 ),
    .rst_ni     ( rst_n               ),
    .id_i       ( '{x: 2'd2, y: 2'd1, port_id: 1'd0} ),
    .floo_req_i ( floo_req_in[2][1][West:North] ),
    .floo_rsp_i ( floo_rsp_in[2][1][West:North] ),
    .floo_req_o ( floo_req_out[2][1][West:North] ),
    .floo_rsp_o ( floo_rsp_out[2][1][West:North] ),
    .floo_wide_i ( floo_wide_in[2][1][West:North] ),
    .floo_wide_o ( floo_wide_out[2][1][West:North] ),
    .floo_req_Eject_in_o  ( tile_req_eject_in[East]  ),
    .floo_req_Eject_out_o ( tile_req_eject_out[East] ),
    .floo_rsp_Eject_in_o  ( tile_rsp_eject_in[East]  ),
    .floo_rsp_Eject_out_o ( tile_rsp_eject_out[East] ),
    .floo_wide_Eject_in_o ( tile_wide_eject_in[East] ),
    .floo_wide_Eject_out_o( tile_wide_eject_out[East]),
    .end_of_sim ( end_of_sim_endpoints[East]        )
  );

    floo_nw_tile #(
    .DELAY ( 40 ),
    .ApplTime ( ApplTime ),
    .TestTime ( TestTime ),
    .NarrowNumReads ( NarrowNumReads ),
    .NarrowNumWrites ( NarrowNumWrites ),
    .WideNumReads ( WideNumReads ),
    .WideNumWrites ( WideNumWrites ),
    .NumAddrRegions ( NumAddrRegionsEW ),
    .node_addr_region_t ( node_addr_region_t ),
    .AddrRegions ( WestAddrRegions ),
    .id_t ( id_t ),
    .hdr_t ( hdr_t ),
    .axi_narrow_in_req_t ( axi_narrow_in_req_t ),
    .axi_narrow_in_rsp_t ( axi_narrow_in_rsp_t ),
    .axi_narrow_out_req_t ( axi_narrow_out_req_t ),
    .axi_narrow_out_rsp_t ( axi_narrow_out_rsp_t ),
    .axi_wide_in_req_t ( axi_wide_in_req_t ),
    .axi_wide_in_rsp_t ( axi_wide_in_rsp_t ),
    .axi_wide_out_req_t ( axi_wide_out_req_t ),
    .axi_wide_out_rsp_t ( axi_wide_out_rsp_t ),
    .floo_req_t ( floo_req_t ),
    .floo_rsp_t ( floo_rsp_t ),
    .floo_wide_t ( floo_wide_t )
  ) i_West_tile (
    .clk_i      ( clk                 ),
    .rst_ni     ( rst_n               ),
    .id_i       ( '{x: 2'd0, y: 2'd1, port_id: 1'd0} ),
    .floo_req_i ( floo_req_in[0][1][West:North] ),
    .floo_rsp_i ( floo_rsp_in[0][1][West:North] ),
    .floo_req_o ( floo_req_out[0][1][West:North] ),
    .floo_rsp_o ( floo_rsp_out[0][1][West:North] ),
    .floo_wide_i ( floo_wide_in[0][1][West:North] ),
    .floo_wide_o ( floo_wide_out[0][1][West:North] ),
    .floo_req_Eject_in_o  ( tile_req_eject_in[West]  ),
    .floo_req_Eject_out_o ( tile_req_eject_out[West] ),
    .floo_rsp_Eject_in_o  ( tile_rsp_eject_in[West]  ),
    .floo_rsp_Eject_out_o ( tile_rsp_eject_out[West] ),
    .floo_wide_Eject_in_o ( tile_wide_eject_in[West] ),
    .floo_wide_Eject_out_o( tile_wide_eject_out[West]),
    .end_of_sim ( end_of_sim_endpoints[West]        )
  );

  for (genvar x = 0; x < 3; x++) begin : gen_dummy_tiles_x
    for (genvar y = 0; y < 3; y++) begin : gen_dummy_tiles_y
      if ((x!=1) && (y!=1)) begin : gen_dummy
        assign floo_req_in[x][y][Eject] = '0;
        assign floo_rsp_in[x][y][Eject] = '0;
        assign floo_wide_in[x][y][Eject] = '0;
        floo_nw_router #(
          .AxiCfgN      ( floo_test_pkg::AxiCfgN          ),
          .AxiCfgW      ( floo_test_pkg::AxiCfgW          ),
          .RouteAlgo    ( floo_pkg::XYRouting             ),
          .NumRoutes    ( floo_test_pkg::NumRoutes        ),
          .InFifoDepth  ( floo_test_pkg::ChannelFifoDepth ),
          .OutFifoDepth ( floo_test_pkg::OutputFifoDepth  ),
          .id_t         ( id_t                            ),
          .hdr_t        ( hdr_t                           ),
          .floo_req_t   ( floo_req_t                      ),
          .floo_rsp_t   ( floo_rsp_t                      ),
          .floo_wide_t  ( floo_wide_t                     ),
          .red_wide_req_t  (),
          .red_wide_rsp_t  (),
          .red_narrow_req_t(),
          .red_narrow_rsp_t()
        ) i_dummy_router (
          .clk_i        ( clk                 ),
          .rst_ni       ( rst_n               ),
          .test_enable_i ( 1'b0 ),
          .id_i           ( '{x: x, y: y, port_id: 1'd0} ),
          .id_route_map_i ( '0                  ),
          .floo_req_i     ( floo_req_in[x][y]   ),
          .floo_rsp_i     ( floo_rsp_in[x][y]   ),
          .floo_req_o     ( floo_req_out[x][y]  ),
          .floo_rsp_o     ( floo_rsp_out[x][y]  ),
          .floo_wide_i    ( floo_wide_in[x][y]  ),
          .floo_wide_o    ( floo_wide_out[x][y] ),
          .offload_wide_req_o(),
          .offload_wide_rsp_i(),
          .offload_narrow_req_o(),
          .offload_narrow_rsp_i()
        );
      end
    end
  end

  floo_axi_test_node #(
    .DELAY ( 0 ),
    .AxiCfg         ( floo_test_pkg::AxiCfgN  ),
    .mst_req_t      ( axi_narrow_in_req_t     ),
    .mst_rsp_t      ( axi_narrow_in_rsp_t     ),
    .slv_req_t      ( axi_narrow_out_req_t    ),
    .slv_rsp_t      ( axi_narrow_out_rsp_t    ),
    .ApplTime       ( ApplTime                ),
    .TestTime       ( TestTime                ),
    .NumAddrRegions ( NumAddrRegionsEject          ),
    .rule_t         ( node_addr_region_t      ),
    .AddrRegions    ( EjectAddrRegions             ),
    .AxiMaxBurstLen ( 4                       ),
    .NumReads       ( NarrowNumReads          ),
    .NumWrites      ( NarrowNumWrites         )
  ) i_narrow_test_node (
    .clk_i      ( clk                 ),
    .rst_ni     ( rst_n               ),
    .slv_port_req_i   ( chimney_narrow_out_req ),
    .slv_port_rsp_o   ( chimney_narrow_out_rsp ),
    .mst_port_req_o   ( chimney_narrow_in_req  ),
    .mst_port_rsp_i   ( chimney_narrow_in_rsp  ),
    .end_of_sim       ( end_of_sim_endpoints[Eject][0]          )
  );

  floo_axi_test_node #(
    .DELAY ( 5 ),
    .AxiCfg         ( floo_test_pkg::AxiCfgW  ),
    .mst_req_t      ( axi_wide_in_req_t       ),
    .mst_rsp_t      ( axi_wide_in_rsp_t       ),
    .slv_req_t      ( axi_wide_out_req_t      ),
    .slv_rsp_t      ( axi_wide_out_rsp_t      ),
    .ApplTime       ( ApplTime                ),
    .TestTime       ( TestTime                ),
    .NumAddrRegions ( NumAddrRegionsEject          ),
    .rule_t         ( node_addr_region_t      ),
    .AddrRegions    ( EjectAddrRegions             ),
    .AxiMaxBurstLen ( 4                       ),
    .NumReads       ( WideNumReads            ),
    .NumWrites      ( WideNumWrites           )
  ) i_wide_test_node (
    .clk_i      ( clk                 ),
    .rst_ni     ( rst_n               ),
    .slv_port_req_i   ( chimney_wide_out_req ),
    .slv_port_rsp_o   ( chimney_wide_out_rsp ),
    .mst_port_req_o   ( chimney_wide_in_req  ),
    .mst_port_rsp_i   ( chimney_wide_in_rsp  ),
    .end_of_sim       ( end_of_sim_endpoints[Eject][1]        )
  );

  floo_nw_chimney #(
    .AxiCfgN              ( floo_test_pkg::AxiCfgN         ),
    .AxiCfgW              ( floo_test_pkg::AxiCfgW         ),
    .ChimneyCfgN          ( floo_test_pkg::ChimneyCfg      ),
    .ChimneyCfgW          ( floo_test_pkg::ChimneyCfg      ),
    .RouteCfg             ( floo_test_pkg::RouteCfg        ),
    .hdr_t                ( hdr_t                          ),
    .id_t                 ( id_t                           ),
    .axi_narrow_in_req_t  ( axi_narrow_in_req_t            ),
    .axi_narrow_in_rsp_t  ( axi_narrow_in_rsp_t            ),
    .axi_narrow_out_req_t ( axi_narrow_out_req_t           ),
    .axi_narrow_out_rsp_t ( axi_narrow_out_rsp_t           ),
    .axi_wide_in_req_t    ( axi_wide_in_req_t              ),
    .axi_wide_in_rsp_t    ( axi_wide_in_rsp_t              ),
    .axi_wide_out_req_t   ( axi_wide_out_req_t             ),
    .axi_wide_out_rsp_t   ( axi_wide_out_rsp_t             ),
    .floo_req_t           ( floo_req_t                     ),
    .floo_rsp_t           ( floo_rsp_t                     ),
    .floo_wide_t          ( floo_wide_t                    )
  ) i_floo_nw_chimney (
    .clk_i   ( clk                 ),
    .rst_ni  ( rst_n               ),
    .test_enable_i  ( 1'b0 ),
    .id_i ( '{x: 2'd1, y: 2'd1, port_id: 1'd0} ),
    .sram_cfg_i           ( '0                      ),
    .axi_narrow_in_req_i  ( chimney_narrow_in_req   ),
    .axi_narrow_in_rsp_o  ( chimney_narrow_in_rsp   ),
    .axi_narrow_out_req_o ( chimney_narrow_out_req  ),
    .axi_narrow_out_rsp_i ( chimney_narrow_out_rsp  ),
    .axi_wide_in_req_i    ( chimney_wide_in_req     ),
    .axi_wide_in_rsp_o    ( chimney_wide_in_rsp     ),
    .axi_wide_out_req_o   ( chimney_wide_out_req    ),
    .axi_wide_out_rsp_i   ( chimney_wide_out_rsp    ),
    .route_table_i        ( '0                      ),
    .floo_req_o           ( floo_req_in[1][1][Eject]      ),
    .floo_rsp_o           ( floo_rsp_in[1][1][Eject]      ),
    .floo_wide_o          ( floo_wide_in[1][1][Eject]     ),
    .floo_req_i           ( floo_req_out[1][1][Eject]     ),
    .floo_rsp_i           ( floo_rsp_out[1][1][Eject]     ),
    .floo_wide_i          ( floo_wide_out[1][1][Eject]    )
  );

  floo_nw_router_fi_dut_wrapper #(
    .id_t ( id_t ),
    .hdr_t ( hdr_t ),
    .floo_req_t ( floo_req_t ),
    .floo_rsp_t ( floo_rsp_t ),
    .floo_wide_t ( floo_wide_t ),
    `ifdef TARGET_RELNOC
    .relfloo_req_t ( relfloo_req_t),
    .relfloo_rsp_t ( relfloo_rsp_t),
    .relfloo_wide_t ( relfloo_wide_t),
    .floo_req_chan_t ( floo_req_chan_t),
    .relfloo_req_chan_t ( relfloo_req_chan_t),
    .floo_rsp_chan_t ( floo_rsp_chan_t),
    .relfloo_rsp_chan_t ( relfloo_rsp_chan_t),
    .floo_wide_chan_t ( floo_wide_chan_t),
    .relfloo_wide_chan_t ( relfloo_wide_chan_t),
    `endif
    .NumEndpoints ( NumEndpoints )
  ) i_dut_wrapper (
    .clk_i        ( clk                 ),
    .rst_ni       ( rst_n               ),
    .id_i         ( '{x: 2'd1, y: 2'd1, port_id: 1'd0} ),
    .id_route_map_i ( '0                  ),
    .floo_req_i     ( floo_req_in[1][1]   ),
    .floo_rsp_i     ( floo_rsp_in[1][1]   ),
    .floo_req_o     ( floo_req_out[1][1]  ),
    .floo_rsp_o     ( floo_rsp_out[1][1]  ),
    .floo_wide_i    ( floo_wide_in[1][1]  ),
    .floo_wide_o    ( floo_wide_out[1][1] ),
    .end_of_sim_endpoints     ( end_of_sim_endpoints   ),
    .end_of_sim_monitor       ( mesh_end_of_sim  )
  );

      floo_mesh_monitor #(
      .Verbose ( 0 ),
      .NumX ( 3 ),
      .NumY ( 3 ),
      .floo_req_t ( floo_req_t ),
      .floo_rsp_t ( floo_rsp_t ),
      .floo_wide_t ( floo_wide_t ),
      .floo_axi_narrow_aw_flit_t ( floo_axi_narrow_aw_flit_t ),
      .floo_axi_narrow_w_flit_t  ( floo_axi_narrow_w_flit_t  ),
      .floo_axi_narrow_ar_flit_t ( floo_axi_narrow_ar_flit_t ),
      .floo_axi_wide_ar_flit_t   ( floo_axi_wide_ar_flit_t   ),
      .floo_axi_narrow_b_flit_t  ( floo_axi_narrow_b_flit_t  ),
      .floo_axi_narrow_r_flit_t  ( floo_axi_narrow_r_flit_t  ),
      .floo_axi_wide_b_flit_t    ( floo_axi_wide_b_flit_t    ),
      .floo_axi_wide_aw_flit_t   ( floo_axi_wide_aw_flit_t   ),
      .floo_axi_wide_w_flit_t    ( floo_axi_wide_w_flit_t    ),
      .floo_axi_wide_r_flit_t    ( floo_axi_wide_r_flit_t    )
    ) i_mesh_monitor (
      .clk_i         ( clk                ),
      .floo_req_in_i ( floo_req_in_eject  ),
      .floo_req_out_i( floo_req_out_eject ),
      .floo_rsp_in_i ( floo_rsp_in_eject  ),
      .floo_rsp_out_i( floo_rsp_out_eject ),
      .floo_wide_in_i( floo_wide_in_eject ),
      .floo_wide_out_i( floo_wide_out_eject ),
      .end_of_sim_o  ( mesh_end_of_sim    )
    );

  for (genvar x = 0; x < 3; x++) begin
    for (genvar y = 0; y < 3; y++) begin
      if (x != 0) begin
        assign floo_req_in[x][y][West] = floo_req_out[x-1][y][East];
        assign floo_rsp_in[x][y][West] = floo_rsp_out[x-1][y][East];
        assign floo_wide_in[x][y][West] = floo_wide_out[x-1][y][East];
      end else begin
        assign floo_req_in[x][y][West] = '0;
        assign floo_rsp_in[x][y][West] = '0;
        assign floo_wide_in[x][y][West] = '0;
      end

      if (x != 2) begin
        assign floo_req_in[x][y][East] = floo_req_out[x+1][y][West];
        assign floo_rsp_in[x][y][East] = floo_rsp_out[x+1][y][West];
        assign floo_wide_in[x][y][East] = floo_wide_out[x+1][y][West];
      end else begin
        assign floo_req_in[x][y][East] = '0;
        assign floo_rsp_in[x][y][East] = '0;
        assign floo_wide_in[x][y][East] = '0;
      end

      if (y != 0) begin
        assign floo_req_in[x][y][South] = floo_req_out[x][y-1][North];
        assign floo_rsp_in[x][y][South] = floo_rsp_out[x][y-1][North];
        assign floo_wide_in[x][y][South] = floo_wide_out[x][y-1][North];
      end else begin
        assign floo_req_in[x][y][South] = '0;
        assign floo_rsp_in[x][y][South] = '0;
        assign floo_wide_in[x][y][South] = '0;
      end

      if (y != 2) begin
        assign floo_req_in[x][y][North] = floo_req_out[x][y+1][South];
        assign floo_rsp_in[x][y][North] = floo_rsp_out[x][y+1][South];
        assign floo_wide_in[x][y][North] = floo_wide_out[x][y+1][South];
      end else begin
        assign floo_req_in[x][y][North] = '0;
        assign floo_rsp_in[x][y][North] = '0;
        assign floo_wide_in[x][y][North] = '0;
      end

    end
  end

  initial begin
    $timeformat(-9, 2, " ns", 20);
    wait(&end_of_sim_endpoints && mesh_end_of_sim);
    $display("[TB] All transactions verified by compare monitors. Draining for %0d cycles.",
             GraceCycles);
    repeat (GraceCycles) @(posedge clk);
    // Let same-edge monitor NBAs and the +TestTime timing strobe settle before
    // final fault classification runs at $finish.
    #(TestTime + 300ps);
    $display("[TB] Grace window complete. Stopping simulation.");
    $finish;
  end

endmodule