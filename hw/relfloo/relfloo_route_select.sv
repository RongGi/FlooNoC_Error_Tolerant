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
  logic dummy_fault;
  logic [2:0] TMR_err;
  //xy routing
  logic [2:0][NumRoutes-1:0] route_sel_multicast;
  logic [2:0][NumRoutes-1:0] route_sel_unicast;

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
    assign TMR_faults[3] = 1'b0;

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
    assign TMR_faults[3] = 1'b0;

  end else if (RouteAlgo == XYRouting || RouteAlgo == YXRouting) begin : gen_dor_routing
    
    if (EnMultiCast) begin : gen_mcast_route_sel
    floo_route_xymask #(
      .NumRoutes     ( NumRoutes        ),
      .flit_t        ( flit_t           ),
      .id_t          ( id_t             ),
      .FwdMode       ( 1'b1             ),
      .RouteAlgo     ( RouteAlgo        )
    ) i_route_xymask (
      .channel_i   ( channel_i ),
      .xy_id_i     ( xy_id_i   ),
      .route_sel_o ( route_sel_multicast )
    );
  end else begin : gen_no_mcast
    assign route_sel_multicast = '0;  // No MCast supported
  end

  if (RouteAlgo == XYRouting) begin : gen_xy_routing
    // Routing based on simple XY routing (X dimension resolved first, then Y)
    // Calculate here the unicast output mask
    id_t [2:0] id_in;
    for (genvar i = 0; i < 3; i++) begin : tmr_xy
      assign id_in[i] = id_t'(channel_i.hdr[i].dst_id);
    end
    always_comb begin
      route_sel_unicast = '0;
      for (int unsigned i = 0; i < 3; i++) begin
        route_sel_id[i] = East;
        if (id_in[i].x == xy_id_i[i].x && id_in[i].y == xy_id_i[i].y) begin
          route_sel_id[i] = Eject + channel_i.hdr[i].dst_id.port_id;
        end else if (id_in[i].x == xy_id_i[i].x) begin
          if (id_in[i].y < xy_id_i[i].y) begin
            route_sel_id[i] = South;
          end else begin
            route_sel_id[i] = North;
          end
        end else begin
          if (id_in[i].x < xy_id_i[i].x) begin
            route_sel_id[i] = West;
          end else begin
            route_sel_id[i] = East;
          end
        end
        route_sel_unicast[i][route_sel_id[i]] = 1'b1;
      end
    end
  end else begin : gen_yx_routing
    // Routing based on simple YX routing (Y dimension resolved first, then X)
    id_t[2:0] id_in;
    for (genvar i = 0; i < 3; i++) begin : tmr_yx
      assign id_in[i] = id_t'(channel_i.hdr[i].dst_id);
    end
    always_comb begin
      route_sel_unicast = '0;
      for (int unsigned i = 0; i < 3; i++) begin
        route_sel_id[i] = North;
        if (id_in[i].x == xy_id_i[i].x && id_in[i].y == xy_id_i[i].y) begin
          route_sel_id[i] = Eject + channel_i.hdr[i].dst_id.port_id;
        end else if (id_in[i].y == xy_id_i[i].y) begin
          // Y matches — now route along X
          if (id_in[i].x < xy_id_i[i].x) begin
            route_sel_id[i] = West;
          end else begin
            route_sel_id[i] = East;
          end
        end else begin
          // Route along Y first
          if (id_in[i].y < xy_id_i[i].y) begin
            route_sel_id[i] = South;
          end else begin
            route_sel_id[i] = North;
          end
        end
        route_sel_unicast[i][route_sel_id[i]] = 1'b1;
      end
    end
  end

  // Depending on the flit header choose the correct route
  if(EnMultiCast) begin: gen_mcast_out_sel
    logic [2:0]selector;
    logic [2:0]selected;
    for (genvar i = 0; i < 3; i++) begin : tmr_selector
      assign selector[i]=(channel_i.hdr[i].collective_op == Multicast);
    end
    for (genvar i = 0; i < 3; i++) begin : tmr_selected
      TMR_voter_fail i_select_tmr (
          .a_i              ( selector[0] ),
          .b_i              ( selector[1] ),
          .c_i              ( selector[2] ),
          .majority_o       ( selected[i] ),
          .fault_detected_o ( TMR_err[i])
      );
      assign route_sel[i] = (selected[i]) ?
                        route_sel_multicast[i] : route_sel_unicast[i];
    end
  end else begin: gen_unicast_route_sel
    assign route_sel = route_sel_unicast;
    assign TMR_err = '0;
  end

  assign TMR_faults[3] = |TMR_err;
  assign channel_o = channel_i;

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
    for (genvar i = 0; i < 3; i++) begin : tmr_muliplexer 
      assign route_sel_o[i] = locked_route_q[i] ? route_sel_q[i] : route_sel[i];
      assign route_sel_id_o[i] = locked_route_q[i] ? route_sel_id_q[i] : route_sel_id[i];
    end

    `TMRFF(locked_route_q, locked_route_d, TMR_faults[0], '0)
    `TMRFFL(route_sel_q, route_sel, TMR_faults[1], ~locked_route_q, '0)
    `TMRFFL(route_sel_id_q, route_sel_id, dummy_fault, ~locked_route_q, '0)
    assign TMR_faults[2]= 1'b0;

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
