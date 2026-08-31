// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Michael Rogenmoser <michaero@iis.ee.ethz.ch>
// Raphael Roth <raroth@student.ethz.ch>

`include "common_cells/registers.svh"
`include "floo_noc/registers.svh"

module relfloo_route_select
  import floo_pkg::*;
#(
  /// Number of output ports
  parameter int unsigned NumRoutes        = 0,
  /// Routing algorithm
  parameter route_algo_e RouteAlgo        = IdTable,
  /// Enable wormhole routing i.e. locking the direction
  /// until the `last` flag is received
  parameter bit          LockRouting      = 1'b1,
  /// Id Width, only used for `XYRouting` and `IdTable`
  parameter int unsigned IdWidth          = 0,
  /// Number of address rules, only used for `IdTable`
  parameter int unsigned NumAddrRules     = 0,
  /// Width of port index, only used for `SrcRouting`
  parameter int unsigned RouteSelWidth    = $clog2(NumRoutes),
  /// Enable multicast routing, currently only supported for `XYRouting`
  parameter bit          EnMultiCast      = 1'b0,
  /// Various types used in the routing algorithm
  parameter type         flit_t           = logic,
  parameter type         addr_rule_t      = logic,
  parameter type         id_t             = logic[IdWidth-1:0],
  /// Inversed SRC / DST if we want to support Multicast on the B response
  parameter bit          InversedSrcDst       = 1'b0
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          test_enable_i,

  input  id_t [2:0]                          xy_id_i,
  input  addr_rule_t [2:0][cc_pkg::iomsb(NumAddrRules):0] id_route_map_i,

  input  flit_t                         channel_i,
  input  logic [2:0]                         valid_i,
  input  logic [2:0]                         ready_i,
  output flit_t                         channel_o,
  output logic [2:0][NumRoutes-1:0]          route_sel_o,
  output logic [2:0][RouteSelWidth-1:0]      route_sel_id_o,
  output logic                               faults_o                        
);

  // Selected route defined by th alg.
  logic [2:0][NumRoutes-1:0] route_sel;
  logic [2:0][RouteSelWidth-1:0] route_sel_id;
  logic [3:0]TMR_faults;

  assign faults_o = |TMR_faults;

  // We need to calc the multicast and the unicast route in parallel
  // and mux them depending on the flit header!

  if (RouteAlgo == IdTable) begin : gen_id_table
    // Routing based on an ID table passed into the router (TBD parameter or signal)
    // Assumes an ID field present in the flit_t

    relfloo_route_idtable #(
      .NumRoutes        (NumRoutes),
      .IdWidth          (IdWidth),
      .NumAddrRules     (NumAddrRules),
      .RouteSelWidth    (RouteSelWidth),
      .flit_t           (flit_t),
      .addr_rule_t      (addr_rule_t),
      .id_t             (id_t)
    ) i_route_idtable (
      .clk_i,
      .rst_ni,
      .id_route_map_i,
      .channel_i,
      .channel_o,
      .route_sel_o(route_sel),
      .route_sel_id_o(route_sel_id)
    );

  end else if (RouteAlgo == SourceRouting) begin : gen_consumption
    // Routing based on a consumable header in the flit
    always_comb begin : proc_route_sel
      for (int unsigned i = 0; i < 3; i++) begin
        route_sel_id[i] = channel_i.hdr[i].dst_id[RouteSelWidth-1:0];
        route_sel[i] = '0;
        route_sel[i][route_sel_id[i]] = 1'b1;
        channel_o = channel_i;
        channel_o.hdr[i].dst_id = channel_i.hdr[i].dst_id >> RouteSelWidth;
      end
    end

  end else if (RouteAlgo == XYRouting || RouteAlgo == YXRouting) begin : gen_dor_routing
    
    relfloo_route_xy_yxrouting #(
      .NumRoutes        (NumRoutes),
      .RouteAlgo        (RouteAlgo),
      .IdWidth          (IdWidth),
      .RouteSelWidth    (RouteSelWidth),
      .EnMultiCast      (EnMultiCast),
      .flit_t           (flit_t),
      .addr_rule_t      (addr_rule_t),
      .id_t             (id_t)
    ) i_route_idtable (
      .clk_i,
      .rst_ni,
      .xy_id_i,
      .channel_i,
      .channel_o,
      .route_sel_o(route_sel),
      .route_sel_id_o(route_sel_id),
      .TMR_faults_o(TMR_faults[3])
    );

  end else begin : gen_err
    // Unknown or unimplemented routing otherwise
    initial begin
      $fatal(1, "Routing algorithm unknown");
    end
  end

  if (LockRouting) begin : gen_lock
    logic [2:0] locked_route_d, locked_route_q;


    always_comb begin : proc_lock_d
      locked_route_d = '0;
      for (int unsigned i = 0; i < 3; i++) begin
        locked_route_d[i] = locked_route_q[i];
        if (ready_i[i] && valid_i[i]) begin
          locked_route_d[i] = ~channel_i.hdr[i].last;
        end
      end
    end

    logic [2:0][NumRoutes-1:0] route_sel_q;
    logic [2:0][RouteSelWidth-1:0] route_sel_id_q;

    // Use previous route selection if locked
    assign route_sel_o = locked_route_q ? route_sel_q : route_sel;
    assign route_sel_id_o = locked_route_q ? route_sel_id_q : route_sel_id;

    `TMRFF(locked_route_q, locked_route_d, TMR_faults[0], '0)
    `TMRFFL(route_sel_q, route_sel, TMR_faults[1], ~locked_route_q, '0)
    `TMRFFL(route_sel_id_q, route_sel_id, TMR_faults[2], ~locked_route_q, '0)

    `ifndef TARGET_SYNTHESIS
      for (genvar i = 0; i < 3; i++) begin : gen_warn
        always @(posedge clk_i) begin
          if (ready_i[i] && valid_i[i] && locked_route_q[i] &&
                  ((route_sel_id_q[i] != route_sel_id[i]) || (route_sel_q[i] != route_sel[i])))
            $warning("Mismatch in route selection!");
        end
      end
    `endif
  end else begin : gen_no_lock
    assign route_sel_o = route_sel;
    assign route_sel_id_o = route_sel_id;
  end

endmodule
