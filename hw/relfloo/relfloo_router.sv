// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Michael Rogenmoser <michaero@iis.ee.ethz.ch>
// Lorenzo Leone <lleone@iis.ee.ethz.ch>
// Raphael Roth <raroth@student.ethz.ch>

`include "common_cells/assertions.svh"
`include "common_cells/registers.svh"
`include "floo_noc/registers.svh"

/// A simple router with configurable number of ports, physical and virtual channels, and input/output buffers
module relfloo_router
  import floo_pkg::*;
#(
  /// Number of ports
  parameter int unsigned NumRoutes            = 0,
  /// More fine-grained control over number of input ports
  parameter int unsigned NumInput             = NumRoutes,
  /// More fine-grained control over number of output ports
  parameter int unsigned NumOutput            = NumRoutes,
  /// Number of virtual channels
  parameter int unsigned NumVirtChannels      = 0,
  /// Number of physical channels
  parameter int unsigned NumPhysChannels      = 1,
  /// Depth of input FIFOs
  parameter int unsigned InFifoDepth          = 0,
  /// Depth of output FIFOs
  parameter int unsigned OutFifoDepth         = 0,
  /// Routing algorithm
  parameter route_algo_e RouteAlgo            = IdTable,
  /// Parameters, only used for ID-based and XY routing
  parameter int unsigned IdWidth              = 0,
  parameter type         id_t                 = logic[IdWidth-1:0],
  /// Used for ID-based routing
  parameter int unsigned NumAddrRules         = 1,
  /// Configuration parameters for special network topologies
  /// Disables Y->X connections in XYRouting
  parameter bit          XYRouteOpt           = 1'b1,
  /// Disables loopback connections
  parameter bit          NoLoopback           = 1'b1,
  /// Select VC implementation
  parameter floo_pkg::vc_impl_e VcImpl        = floo_pkg::VcNaive,
  /// Parameter for the reduction configuration
  parameter collect_op_be_cfg_t CollectiveCfg    = CollectiveSupportDefaultCfg,
  parameter reduction_cfg_t     RedCfg           = '0,
  /// AXI configurations
  parameter axi_cfg_t    AxiCfgOffload        = '0,
  parameter axi_cfg_t    AxiCfgParallel       = '0,
  /// Various types
  parameter type         addr_rule_t          = logic,
  parameter type         flit_t               = logic,
  parameter type         hdr_t                = logic,
  /// Offload reduction  interface
  parameter type red_req_t                     = logic,
  parameter type red_rsp_t                     = logic
) (
  input  logic                                       clk_i,
  input  logic                                       rst_ni,
  input  logic                                       test_enable_i,
  /// Only used for `XYRouting`, tie to '0 otherwise
  input  id_t [2:0]                                       xy_id_i,
  /// Only used for `IdTable` routing, tie to '0 otherwise
  input  addr_rule_t [2:0][cc_pkg::iomsb(NumAddrRules):0]              id_route_map_i,
  /// Input channels
  input  logic  [NumInput-1:0][NumVirtChannels-1:0][2:0]  valid_i,
  output logic  [NumInput-1:0][NumVirtChannels-1:0][2:0]  ready_o,
  input  flit_t [NumInput-1:0][NumPhysChannels-1:0]  data_i,
  output logic  [NumInput-1:0][NumVirtChannels-1:0]  credit_o,
  /// Output channels
  output logic  [NumOutput-1:0][NumVirtChannels-1:0][2:0] valid_o,
  input  logic  [NumOutput-1:0][NumVirtChannels-1:0][2:0] ready_i,
  output flit_t [NumOutput-1:0][NumPhysChannels-1:0] data_o,
  input  logic  [NumOutput-1:0][NumVirtChannels-1:0] credit_i,
  /// Interface towards reduction offload unit
  output  red_req_t                 offload_req_o,
  input   red_rsp_t                 offload_rsp_i,
  /// error report:  bit 1 detected and corrected, bit 1 detected and uncorrectable
  output logic [1:0]                faults_o
);

  // TODO MICHAERO: assert NumPhysChannels <= NumVirtChannels

  // Generate some local parameters to understand which type of collective support
  // is required in the specific router instance
  localparam bit EnSequentialReduction = en_sequential_support(CollectiveCfg);
  localparam bit EnParallelReduction   = en_parallel_support(CollectiveCfg);
  localparam bit EnMultiCast = en_multicast_support(CollectiveCfg);
  localparam bit EnCollective = (EnSequentialReduction | EnParallelReduction | EnMultiCast);

  // When a offloadable reduction is dedected then the data will be brunched off infront
  // of the router crossbar. The reduction logic will reduce the incoming flits and deliver
  // a single flit instead. When finished the result will be merged as an extra port into
  // the output arbiter.
  // Generate local Number of routes
  localparam int unsigned LocalNumInputs = NumInput + EnSequentialReduction;
  localparam int unsigned NumParallelRedRoutes = (EnParallelReduction) ? NumInput : 0 ;

  // Generate the vars to handle the input of the router
  flit_t [NumInput-1:0][NumVirtChannels-1:0] in_data, in_routed_data;
  logic  [NumInput-1:0][NumVirtChannels-1:0][2:0] in_valid, in_ready;
  logic  [NumInput-1:0][NumVirtChannels-1:0][2:0][NumOutput-1:0] route_mask;

  // Credit generation for virtual channel support
  logic [NumInput-1:0][NumVirtChannels-1:0] credit_gnt_q, credit_gnt_d;

  // Signals to connect input only virtual channel 0 to offload reduction logic
  logic  [NumInput-1:0] red_offload_valid_in, red_offload_ready_in;
  flit_t [NumInput-1:0] red_offload_data_in;
  logic  [NumInput-1:0][NumOutput-1:0] red_offload_route_selected;
  logic  [NumInput-1:0][NumInput-1:0] red_offload_expected_in_route_loopback;

  // SIgnals top connect offload reduction logic to output virtual channel 0
  logic  [NumOutput-1:0] red_offload_valid_out, red_offload_ready_out;
  flit_t [NumOutput-1:0] red_offload_data_out;

  //fault reporting
  logic [3:0] faults_corrected;
  logic [1:0] faults_uncorrected;

  logic [1:0][NumInput-1:0][NumVirtChannels-1:0] faults_inputs_corrected;
  logic [NumInput-1:0][NumVirtChannels-1:0] faults_inputs_uncorrected;

  // Router input part
  for (genvar in = 0; in < NumInput; in++) begin : gen_input
    for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt_input

      logic [cc_pkg::idx_width(NumPhysChannels)-1:0] in_p;
      if (NumPhysChannels == 1) begin : gen_single_phys
        assign in_p = '0;
      end else if (NumPhysChannels == NumVirtChannels) begin : gen_virt_eq_phys
        assign in_p = v;
      end else begin : gen_odd_phys
        $fatal(1, "unimplemented");
      end

      (* ungroup *)
      relfloo_stream_fifo_optimal_wrap #(
        .Depth  ( InFifoDepth ),
        .data_t ( flit_t      )
      ) i_stream_fifo (
        .clk_i      ( clk_i         ),
        .rst_ni     ( rst_ni        ),
        .testmode_i ( test_enable_i ),
        .flush_i    ( 1'b0  ),
        .usage_o    (       ),
        .data_i     ( data_i  [in][in_p] ),
        .valid_i    ( valid_i [in][v]    ),
        .ready_o    ( ready_o [in][v]    ),
        .data_o     ( in_data [in][v]    ),
        .valid_o    ( in_valid[in][v]    ),
        .ready_i    ( in_ready[in][v]    ),
        .fault_o    ( {faults_inputs_corrected[0][in][v],faults_inputs_uncorrected[in][v]})
      );

      relfloo_route_select #(
        .NumRoutes        ( NumOutput        ),
        .flit_t           ( flit_t           ),
        .RouteAlgo        ( RouteAlgo        ),
        .IdWidth          ( IdWidth          ),
        .id_t             ( id_t             ),
        .NumAddrRules     ( NumAddrRules     ),
        .addr_rule_t      ( addr_rule_t      ),
        .EnMultiCast      ( EnMultiCast      )
      ) i_route_select (
        .clk_i,
        .rst_ni,
        .test_enable_i,
        .xy_id_i        ( xy_id_i               ),
        .id_route_map_i ( id_route_map_i        ),
        .channel_i      ( in_data       [in][v] ),
        .valid_i        ( in_valid      [in][v] ),
        .ready_i        ( in_ready      [in][v] ),
        .channel_o      ( in_routed_data[in][v] ),
        .route_sel_o    ( route_mask    [in][v] ),
        .route_sel_id_o (                       ),
        .faults_o       ( faults_inputs_corrected[1][in][v]   )
      );

      // Credit count generation. Assign 1 upon any handshake
      if (VcImpl == floo_pkg::VcCredit) begin: gen_credit_support
        assign credit_o[in][v] = credit_gnt_q[in][v];
        assign credit_gnt_d[in][v] = in_valid[in][v] & in_ready[in][v];
        `FF(credit_gnt_q[in][v], credit_gnt_d[in][v], 1'b0);
      end else begin: gen_no_credit
        assign credit_o[in][v] = 1'b1;
      end
    end
  end

  assign faults_corrected[0] = |faults_inputs_corrected;
  assign faults_uncorrected[0] = |faults_inputs_uncorrected;


  // Var for the "normal" dataflow without any reduction
  logic  [NumInput-1:0][NumVirtChannels-1:0][2:0] cross_valid, cross_ready;

  // Vars to branch the reduction off the main path (No virtual channel support for reduction)
  logic  [NumInput-1:0][NumVirtChannels-1:0] red_valid_in, red_ready_in;
  logic  [NumInput-1:0][NumVirtChannels-1:0][NumOutput-1:0] red_route_selected;
  flit_t [NumInput-1:0][NumVirtChannels-1:0] red_data_in;

  // Vars for the data coming from the reduction
  logic  [NumOutput-1:0][NumVirtChannels-1:0] red_valid_out, red_ready_out;
  flit_t [NumOutput-1:0][NumVirtChannels-1:0] red_data_out;

  // Vars to separate reductions with only one member
  logic [NumInput-1:0][NumVirtChannels-1:0][NumInput-1:0] red_expected_in_route;
  logic [NumInput-1:0][NumVirtChannels-1:0][$clog2(NumInput):0] red_how_many_participants;
  logic [NumInput-1:0][NumVirtChannels-1:0] red_single_member, offload_reduction;

  // If we support offload reduction and a reduction is detected then we split the signal and forward it to the reduction
  if(EnSequentialReduction) begin : gen_offload_reduction_demux
    for (genvar in = 0; in < NumInput; in++) begin : gen_input
      for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt_input
        // Generate the mask for all inputs to determint if we have a reduction with only one member.
        // Any reduction with one member will be directly forwarded to its destination without reduction!
        floo_route_xymask #(
          .NumRoutes    (NumInput),
          .flit_t       (flit_t),
          .id_t         (id_t),
          .FwdMode      (0),
          .RouteAlgo    (RouteAlgo)
        ) i_gen_route_xymask (
          .channel_i    (in_routed_data[in][v]),
          .xy_id_i      (xy_id_i),
          .route_sel_o  (red_expected_in_route[in][v])
        );

        // onehot decoding of the input direction
        // bypass the reduction if only one input member is selected
        // (if none is selected then bypass too [should never occurred but to avoid deadlocks])
        cc_popcount #(
          .InputWidth  (NumInput)
        ) i_red_list_counter (
          .data_i       (red_expected_in_route[in][v]),
          .popcount_o   (red_how_many_participants[in][v])
        );
        assign red_single_member[in][v] = (red_how_many_participants[in][v] <= 1);

        // Generate the handshaking
        // Outoput 0: unicast
        // Output 1: reduction
        assign offload_reduction[in][v] = (~red_single_member[in][v]) &
                            (is_seq_reduction_op(in_routed_data[in][v].hdr.collective_op));
        cc_stream_demux #(
          .NumOup             (2)
        ) i_stream_demux (
          .inp_valid_i        (in_valid[in][v]),
          .inp_ready_o        (in_ready[in][v]),
          .oup_sel_i          (offload_reduction[in][v]),
          .oup_valid_o        ({red_valid_in[in][v], cross_valid[in][v]}),
          .oup_ready_i        ({red_ready_in[in][v], cross_ready[in][v]})
        );
        // Assign the data
        assign red_data_in[in][v] = in_routed_data[in][v];
        assign red_route_selected[in][v] = route_mask[in][v];
      end
    end
  end else begin: gen_no_red_offload
    assign cross_valid = in_valid;
    assign in_ready = cross_ready;
    assign red_valid_in = '0;
    assign red_data_in = '0;
    assign red_route_selected = '0;
    assign red_expected_in_route = '0;
  end

  // To support reduction, there is need for virtual channels,
  // or decoupled write/read streams to avoid deadlock.

  // Reduction logic
  if(EnSequentialReduction) begin : gen_reduction_logic
    for (genvar in = 0; in < NumInput; in++) begin: gen_vc_reduction
        assign red_offload_valid_in[in] = red_valid_in[in][0];
        assign red_ready_in[in][0]      = red_offload_ready_in[in];
        assign red_offload_data_in[in]  = red_data_in[in][0];
        assign red_offload_route_selected[in]   = red_route_selected[in][0];
        assign red_offload_expected_in_route_loopback[in] = red_expected_in_route[in][0];
    end
    if (NumVirtChannels > 1) begin: gen_vc_red_ready_tied
      for (genvar in = 0; in < NumInput; in++) begin: gen_vc1_tied
        assign red_ready_in[in][1]  = '0; // Tied to zero the ready from offload unit to VC1
      end
    end

    typedef logic [AxiCfgOffload.DataWidth-1:0] RdData_t;
    floo_reduction_unit #(
      .NumInputs                  (NumInput),
      .NumOutputs                 (NumOutput),
      .flit_t                     (flit_t),
      .hdr_t                      (hdr_t),
      .id_t                       (id_t),
      .reduction_data_t           (RdData_t),
      .RedCfg                     (RedCfg),
      .AxiCfg                     (AxiCfgOffload)
    ) i_reduction_unit (
      .clk_i                      (clk_i),
      .rst_ni                     (rst_ni),
      .xy_id_i                    (xy_id_i),
      .valid_i                    (red_offload_valid_in),
      .ready_o                    (red_offload_ready_in),
      .data_i                     (red_offload_data_in),
      .routed_out_mask_i          (red_offload_route_selected),
      .in_mask_i                  (red_offload_expected_in_route_loopback),
      .valid_o                    (red_offload_valid_out),
      .ready_i                    (red_offload_ready_out),
      .data_o                     (red_offload_data_out),
      .operation_o                (offload_req_o.req.op),
      .operand1_o                 (offload_req_o.req.operand1),
      .operand2_o                 (offload_req_o.req.operand2),
      .operands_valid_o           (offload_req_o.valid),
      .operands_ready_i           (offload_rsp_i.ready),
      .result_i                   (offload_rsp_i.rsp.result),
      .result_valid_i             (offload_rsp_i.valid),
      .result_ready_o             (offload_req_o.ready)
    );

    for (genvar out = 0; out < NumOutput; out++) begin : gen_output_virt_sel
      // Data path
      assign red_data_out[out][0] = red_offload_data_out[out];
      assign red_valid_out[out][0] = red_offload_valid_out[out];
      assign red_offload_ready_out[out] = red_ready_out[out][0];
    end

    // Tie down all unused signals
    if(NumVirtChannels > 1) begin: gen_vc_red_val_tied
      for (genvar out = 0; out < NumOutput; out++) begin: gen_out
        assign red_data_out[out][1] = '0;
        assign red_valid_out[out][1] = '0;
      end
    end
  end else begin: gen_red_tied
    assign red_offload_valid_in = '0;
    assign red_offload_ready_in = '0;
    assign red_offload_data_in = '0;
    assign red_offload_route_selected = '0;
    assign red_offload_expected_in_route_loopback = '0;
    assign red_offload_valid_out = '0;
    assign red_offload_ready_out = '0;
    assign red_offload_data_out = '0;
    assign red_data_out = '0;
    assign red_valid_out = '0;
    assign offload_req_o = '0;
  end

  // Normal crossbar between all in / out routes
  logic [NumOutput-1:0][NumVirtChannels-1:0][2:0][NumInput-1:0] masked_valid, masked_ready;
  logic [NumInput-1:0][NumVirtChannels-1:0][2:0][NumOutput-1:0] masked_valid_transposed;
  logic [NumInput-1:0][NumVirtChannels-1:0][2:0][NumOutput-1:0] masked_ready_transposed;
  logic [NumInput-1:0][NumVirtChannels-1:0][2:0][NumOutput-1:0] past_handshakes_q, past_handshakes_d;
  logic [NumInput-1:0][NumVirtChannels-1:0][2:0][NumOutput-1:0] current_handshakes, all_handshakes;
  logic [NumInput-1:0][NumVirtChannels-1:0][2:0][NumOutput-1:0] ignore_routes, expected_handshakes;

  flit_t [NumOutput-1:0][NumVirtChannels-1:0][NumInput-1:0] masked_data;

  for (genvar in = 0; in < NumInput; in++) begin : gen_hs_input
    for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_hs_virt
      for (genvar out = 0; out < NumOutput; out++) begin : gen_hs_output
        // In case of loopback connections (to itself) and Y->X connections in XYRouting,
        // we tie the handshake & data signals to 0, to optimize them away during synthesis
        if((NoLoopback && (in == out)) ||
           ((RouteAlgo == XYRouting) && XYRouteOpt &&
            (in == South || in == North) && (out == East || out == West)) ||
           ((RouteAlgo == YXRouting) && XYRouteOpt &&
            (in == East || in == West)  && (out == North || out == South)))
        begin : gen_no_conn
          for (genvar i = 0; i < 3; i++) begin : tmr_masked
            assign masked_ready_transposed[in][v][i][out] = '0;
            assign masked_valid[out][v][i][in]     = '0;
          end
          assign masked_data[out][v][in]      = '0;
        end else begin : gen_conn
          for (genvar i = 0; i < 3; i++) begin : tmr_masked
            assign masked_ready_transposed[in][v][i][out] = masked_ready[out][v][i][in];
            assign masked_valid[out][v][i][in]     = cross_valid[in][v][i] & route_mask[in][v][i][out] &
                                                  (!EnMultiCast || ~past_handshakes_q[in][v][i][out]);
          end
          assign masked_data[out][v][in]      = in_routed_data[in][v];
        end
        for (genvar i = 0; i < 3; i++) begin : tmr_masked
          assign masked_valid_transposed[in][v][i][out] = masked_valid[out][v][i][in];
        end
      end
      if (!EnMultiCast) begin : gen_unicast
        for (genvar i = 0; i < 3; i++) begin : tmr_cross
          assign cross_ready[in][v][i] = |(masked_ready_transposed[in][v][i] & route_mask[in][v][i]);
        end
      end else begin : gen_multicast
        for (genvar i = 0; i < 3; i++) begin : tmr_cross
          // In the case of multicast transactions, each destination can assert the ready signal
          // independently and potentially at different clock cycles. This logic ensures that
          // the upstream sender is only acknowledged when all selected downstream destinations
          // have successfully completed their handshake (valid & ready).
          //
          // Handshake received in current cycle
          assign current_handshakes[in][v][i] = masked_valid_transposed[in][v][i] &
                                            masked_ready_transposed[in][v][i];
          // Handhsake received in previous cycles
          assign past_handshakes_d[in][v][i] = (cross_ready[in][v][i] & cross_valid[in][v][i]) ? '0 :
                                              (past_handshakes_q[in][v][i] | current_handshakes[in][v][i]);
          // History of handshake received (past + present)
          assign all_handshakes[in][v][i] = past_handshakes_q[in][v][i] | current_handshakes[in][v][i];

          // Handshake are excepeted on all selected routes except the loopback
          assign ignore_routes[in][v][i] = NoLoopback ? (1 << in) : '0;
          assign expected_handshakes[in][v][i] = route_mask[in][v][i] & ~ignore_routes[in][v][i];

          // Send ready upstream only when all expected downstream handshakes have been received
          assign cross_ready[in][v][i] = &(all_handshakes[in][v][i] | ~expected_handshakes[in][v][i]);
        end
      end
    end
  end

  // TODO (lleone): Move the following FF inside the multicast
  logic [NumInput-1:0][NumVirtChannels-1:0] handshake_faults;
  for (genvar in = 0; in < NumInput; in++) begin : gen_hs_input_ff
    for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_hs_virt_ff
      `TMRFF(past_handshakes_q[in][v], past_handshakes_d[in][v], handshake_faults[in][v], '0);
    end
  end
  assign faults_corrected[1]=|handshake_faults;

  // We merge the data from the reduction module as an additional input of our output arbiter.
  logic [NumOutput-1:0][NumVirtChannels-1:0][2:0][LocalNumInputs-1:0] merged_valid, merged_ready;
  flit_t [NumOutput-1:0][NumVirtChannels-1:0][LocalNumInputs-1:0] merged_data;

  if(EnSequentialReduction) begin : gen_assign_data_output
    for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_con_virt
      for (genvar out = 0; out < NumOutput; out++) begin : gen_con_output
        assign merged_data[out][v] = {red_data_out[out][v], masked_data[out][v]};
        assign merged_valid[out][v] = {red_valid_out[out][v], masked_valid[out][v]};
        assign masked_ready[out][v] = merged_ready[out][v][LocalNumInputs-2:0];
        assign red_ready_out[out][v] = merged_ready[out][v][LocalNumInputs-1];
      end
    end
  end else begin: gen_byp_mask
    assign merged_data = masked_data;
    assign merged_valid = masked_valid;
    assign masked_ready = merged_ready;
  end

  // Vars to handle the output of the arbiter and the optional fifos
  flit_t [NumOutput-1:0][NumVirtChannels-1:0] out_data, out_buffered_data;
  logic  [NumOutput-1:0][NumVirtChannels-1:0][2:0] out_valid, out_ready;
  logic  [NumOutput-1:0][NumVirtChannels-1:0][2:0] out_buffered_valid, out_buffered_ready;

  logic  [NumOutput-1:0][NumVirtChannels-1:0] faults_outputs_uncorrected;
  logic  [1:0][NumOutput-1:0][NumVirtChannels-1:0] faults_outputs_corrected;
  logic  [NumOutput-1:0]  faults_vs_arb_corrected;

  for (genvar out = 0; out < NumOutput; out++) begin : gen_output

    // arbitrate input fifos per virtual channel
    for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt_output
      // Output arbiter
      relfloo_output_arbiter #(
        .NumRoutes            ( LocalNumInputs            ),
        .NumParallelRedRoutes ( NumParallelRedRoutes      ),
        .CollectOpCfg         ( CollectiveCfg             ),
        .RouteAlgo            ( RouteAlgo                  ),
        .flit_t               ( flit_t                    ),
        .hdr_t                ( hdr_t                     ),
        .id_t                 ( id_t                      ),
        .AxiCfg               ( AxiCfgParallel            )
      ) i_output_arbiter (
        .clk_i,
        .rst_ni,

        .valid_i  ( merged_valid[out][v] ),
        .ready_o  ( merged_ready[out][v] ),
        .data_i   ( merged_data [out][v] ),
        .xy_id_i  ( xy_id_i              ),

        .valid_o ( out_valid[out][v] ),
        .ready_i ( out_ready[out][v] ),
        .data_o  ( out_data [out][v] ),
        .faults_o( faults_outputs_corrected[0][out][v])
      );

      if (OutFifoDepth > 0) begin : gen_out_fifo
        (* ungroup *)
        relfloo_stream_fifo_optimal_wrap #(
          .Depth  ( OutFifoDepth ),
          .data_t ( flit_t      )
        ) i_stream_fifo (
          .clk_i      ( clk_i         ),
          .rst_ni     ( rst_ni        ),
          .testmode_i ( test_enable_i ),
          .flush_i    ( 1'b0  ),
          .usage_o    (       ),
          .data_i     ( out_data          [out][v] ),
          .valid_i    ( out_valid         [out][v] ),
          .ready_o    ( out_ready         [out][v] ),
          .data_o     ( out_buffered_data [out][v] ),
          .valid_o    ( out_buffered_valid[out][v] ),
          .ready_i    ( out_buffered_ready[out][v] ),
          .fault_o    ({faults_outputs_corrected[1][out][v],faults_outputs_uncorrected[out][v]})
        );
      end else begin : gen_no_out_fifo
        assign out_buffered_data [out][v] = out_data          [out][v];
        assign out_buffered_valid[out][v] = out_valid         [out][v];
        assign out_ready         [out][v] = out_buffered_ready[out][v];
        assign faults_outputs_corrected[1][out][v] = '0;
        assign faults_outputs_uncorrected[out][v] = '0;
      end
    end

    // At the end point, we cannot make valid dependent on ready.
    // However, this is the case in the `floo_vc_arbiter`.
    // For this reason, there must be cuts at the input of the endpoint.
    
    relfloo_vc_arbiter #(
      .NumVirtChannels  ( NumVirtChannels  ),
      .flit_t           ( flit_t           ),
      .NumPhysChannels  ( NumPhysChannels  ),
      .VcImpl ( VcImpl )
    ) i_vc_arbiter (
      .clk_i,
      .rst_ni,
      .valid_i  ( out_buffered_valid[out] ),
      .ready_o  ( out_buffered_ready[out] ),
      .data_i   ( out_buffered_data [out] ),
      .ready_i  ( ready_i  [out] ),
      .valid_o  ( valid_o  [out] ),
      .data_o   ( data_o   [out] ),
      .credit_i ( credit_i[out] ),
      .faults_o (faults_vs_arb_corrected[out])
    );
  end
  assign faults_corrected[2] = |faults_outputs_corrected;
  assign faults_uncorrected[1] = |faults_outputs_uncorrected;
  assign faults_corrected[3] = |faults_vs_arb_corrected;

  assign faults_o[0] = |faults_corrected;
  assign faults_o[1] = |faults_uncorrected; 

  if (VcImpl != VcPreemptValid) begin: gen_stbl_valin_assert
    for (genvar i = 0; i < NumInput; i++) begin : gen_input_assert
      for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt_assert
        // Assert that the input data is stable when valid is asserted
        // `ASSERT(StableDataIn, valid_i[i][v] && !ready_o[i][v] |=> $stable(data_i[i][v]))
        // Assert that valid is stable when ready is not asserted
        `ASSERT(StableValidIn, valid_i[i][v] && !ready_o[i][v] |=> $stable(valid_i[i][v]))
      end
    end
  end

  if (VcImpl != VcPreemptValid) begin: gen_stbl_valout_assert
    for (genvar o = 0; o < NumOutput; o++) begin : gen_output_assert
      for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt_assert
        // Assert that valid is stable when ready is not asserted
        `ASSERT(StableValidOut, valid_o[o][v] && !ready_i[o][v] |=> $stable(valid_o[o][v]))
      end
    end
  end

  // If XYRouting optimization is enabled, assert that not Y->X routing occurs
  if ((RouteAlgo == XYRouting) && XYRouteOpt) begin : gen_xy_opt_assert
    for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt
      for (genvar i = 0; i < 2; i++) begin
        `ASSERT(XYDirectionNotAllowed,
            !(in_valid[South][v][i] && route_mask[South][v][i][East]) &&
            !(in_valid[South][v][i] && route_mask[South][v][i][West]) &&
            !(in_valid[North][v][i] && route_mask[North][v][i][East]) &&
            !(in_valid[North][v][i] && route_mask[North][v][i][West]))
      end    
    end
  end

  // If YXRouting optimization is enabled, assert that not X->Y routing occurs
  if ((RouteAlgo == YXRouting) && XYRouteOpt) begin : gen_yx_opt_assert
    for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt
      for (genvar i = 0; i < 2; i++) begin
        `ASSERT(YXDirectionNotAllowed,
            !(in_valid[East][v][i] && route_mask[East][v][i][North]) &&
            !(in_valid[East][v][i] && route_mask[East][v][i][South]) &&
            !(in_valid[West][v][i] && route_mask[West][v][i][North]) &&
            !(in_valid[West][v][i] && route_mask[West][v][i][South]))
      end
    end
  end

  // If `NoLoopback` is enabled, assert that no loopback occurs
  if (NoLoopback) begin: gen_no_loopback_assert
    for (genvar in = 0; in < NumInput; in++) begin : gen_input
      for (genvar v = 0; v < NumVirtChannels; v++) begin : gen_virt
        for (genvar i = 0; i < 2; i++) begin : tmr
        `ASSERT(NoLoopback, !(in_valid[in][v][i] && route_mask[in][v][i][in] &&
                            (in_data[in][v].hdr[i].collective_op == Unicast)))
        end
      end
    end
  end

  // If you have offload reduction and more than one virtual channel,
  // the reduction traffic must arrive from Virtual Channel 0
  if (EnSequentialReduction && (NumVirtChannels > 1)) begin: gen_vc_red
    for (genvar in = 0; in < NumInput; in++) begin: gen_red_vc_idx_assert
        `ASSERT(CollOpReceivedOnWrongVirtChannel, !red_valid_in[in][1])
    end
  end

  // Multicast is currently only supported for `XYRouting`
  `ASSERT_INIT(NoMultiCastSupport, !(EnMultiCast &&
              (RouteAlgo != XYRouting && RouteAlgo != YXRouting)))
  // We only support symmetrical configuration for the FP reduction
  `ASSERT_INIT(NoSymConfig, !(EnSequentialReduction && (NumInput != NumOutput)))
  // We can not support collective without loopback active
  `ASSERT_INIT(SupportLoopback, !(EnCollective && NoLoopback))

endmodule
