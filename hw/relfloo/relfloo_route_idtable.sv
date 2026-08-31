
// Routing based on an ID table passed into the router (TBD parameter or signal)
// Assumes an ID field present in the flit_t

module relfloo_route_idtable
  import floo_pkg::*;
#(
  /// Number of output ports
  parameter int unsigned NumRoutes        = 0,
  /// Id Width, only used for `XYRouting` and `IdTable`
  parameter int unsigned IdWidth          = 0,
  /// Number of address rules, only used for `IdTable`
  parameter int unsigned NumAddrRules     = 0,
  /// Width of port index, only used for `SrcRouting`
  parameter int unsigned RouteSelWidth    = $clog2(NumRoutes),
  /// Various types used in the routing algorithm
  parameter type         flit_t           = logic,
  parameter type         addr_rule_t      = logic,
  parameter type         id_t             = logic[IdWidth-1:0]
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  addr_rule_t [2:0][cc_pkg::iomsb(NumAddrRules):0] id_route_map_i,

  input  flit_t                         channel_i,
  output flit_t                         channel_o,
  output logic [2:0][NumRoutes-1:0]          route_sel_o,
  output logic [2:0][RouteSelWidth-1:0]      route_sel_id_o
);
    

    logic [2:0][RouteSelWidth-1:0] id_table_result;
    assign channel_o = channel_i;

    for (genvar i = 0; i < 3; i++) begin : gen_tmr_part
        cc_addr_decode #(
            .NoIndices ( NumRoutes    ),
            .NoRules   ( NumAddrRules ),
            .addr_t    ( id_t         ),
            .rule_t    ( addr_rule_t  ),
            .Napot     ( 0            )
        ) i_id_decode (
            .addr_i           ( channel_i.hdr[i].dst_id  ),
            .addr_map_i       ( id_route_map_i[i]    ),
            .idx_o            ( id_table_result[i]   ),
            .dec_valid_o      (),
            .dec_error_o      (),
            .default_idx_i    ('0),
            .en_default_idx_i ('0)
        );
    end

    // One-hot encoding of the decoded route
    for (genvar i = 0; i < 3; i++) begin : id_assign
        assign route_sel_id_o [i] = id_table_result[i];
    end

    always_comb begin : proc_route_sel
        int unsigned i;
        route_sel_o = '0;
        for (i = 0; i < 3; i++) begin
            route_sel_o[i][id_table_result[i]] = 1'b1;
        end
    end

endmodule