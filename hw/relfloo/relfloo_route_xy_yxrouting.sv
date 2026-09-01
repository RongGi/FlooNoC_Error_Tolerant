module relfloo_route_xy_yxrouting
  import floo_pkg::*;
#(
  /// Number of output ports
  parameter int unsigned NumRoutes        = 0,
  /// Routing algorithm
  parameter route_algo_e RouteAlgo        = IdTable,
  /// Id Width, only used for `XYRouting` and `IdTable`
  parameter int unsigned IdWidth          = 0,
  /// Width of port index, only used for `SrcRouting`
  parameter int unsigned RouteSelWidth    = $clog2(NumRoutes),
  /// Enable multicast routing, currently only supported for `XYRouting`
  parameter bit          EnMultiCast      = 1'b0,
  /// Various types used in the routing algorithm
  parameter type         flit_t           = logic,
  parameter type         addr_rule_t      = logic,
  parameter type         id_t             = logic[IdWidth-1:0]
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  id_t [2:0]                          xy_id_i,

  input  flit_t                         channel_i,
  output flit_t                         channel_o,
  output logic [2:0][NumRoutes-1:0]          route_sel_o,
  output logic [2:0][RouteSelWidth-1:0]      route_sel_id_o,
  output logic                            TMR_faults_o
);

  // Routing based on simple XY routing
  // Assumes an even-bit ID field in the flit_t used for xy
  // assert ((IdWidth/2)*2 == IdWidth);
  // assert (NumRoutes == 5);

  // Port map:
  //   - 0: target/destination
  //   - 1: upper bits decreasing (South)
  //   - 2: lower bits decreasing (West )
  //   - 3: upper bits increasing (North)
  //   - 4: lower bits increasing (East )

  // One-hot encoding of the decoded route
  logic [2:0][NumRoutes-1:0] route_sel;
  logic [2:0][RouteSelWidth-1:0] route_sel_id;
  // If we enable multicast then generate the output routes here seperatly
  // We need to calc the multicast and the unicast route in parallel
  // and mux them depending on the flit header!
  logic [2:0][NumRoutes-1:0] route_sel_multicast;
  logic [2:0][NumRoutes-1:0] route_sel_unicast;

  // TMR error bits
  logic [2:0] TMR_err;
  
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

  for (genvar i = 0; i < 3; i++) begin : id_assign
        assign route_sel_id_o [i] = route_sel_id[i];
    end
  for (genvar i = 0; i < 3; i++) begin : tmr_index
    for (genvar out = 0; out < NumRoutes; out++) begin : routes
      assign route_sel_o[i][out] = route_sel[i][out];
    end
  end

  // Assign the data directly to the output
  assign TMR_faults_o = |TMR_err;
  assign channel_o = channel_i;
endmodule