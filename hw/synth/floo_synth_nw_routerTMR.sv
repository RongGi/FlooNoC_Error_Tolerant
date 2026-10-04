// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Tim Fischer <fischeti@iis.ee.ethz.ch>

module floo_synth_nw_routerTMR
  import floo_pkg::*;
  import floo_synth_params_pkg::*;
  import floo_synth_nw_pkg::*;
#(
  parameter int unsigned NumPorts = int'(floo_pkg::NumDirections)
) (
  input  logic clk_iA,
  input  logic clk_iB,
  input  logic clk_iC,
  input  logic rst_niA,
  input  logic rst_niB,
  input  logic rst_niC,
`ifndef TARGET_STMR
  input  logic test_enable_iA,
  input  logic test_enable_iB,
  input  logic test_enable_iC,

  input  id_t id_iA,
  input  id_t id_iB,
  input  id_t id_iC,
  input  logic id_route_map_iA,
  input  logic id_route_map_iB,
  input  logic id_route_map_iC,

  input  floo_req_t [NumPorts-1:0] floo_req_iA,
  input  floo_req_t [NumPorts-1:0] floo_req_iB,
  input  floo_req_t [NumPorts-1:0] floo_req_iC,
  input  floo_rsp_t [NumPorts-1:0] floo_rsp_iA,
  input  floo_rsp_t [NumPorts-1:0] floo_rsp_iB,
  input  floo_rsp_t [NumPorts-1:0] floo_rsp_iC,
  output floo_req_t [NumPorts-1:0] floo_req_oA,
  output floo_req_t [NumPorts-1:0] floo_req_oB,
  output floo_req_t [NumPorts-1:0] floo_req_oC,
  output floo_rsp_t [NumPorts-1:0] floo_rsp_oA,
  output floo_rsp_t [NumPorts-1:0] floo_rsp_oB,
  output floo_rsp_t [NumPorts-1:0] floo_rsp_oC,
  input  floo_wide_t [NumPorts-1:0] floo_wide_iA,
  input  floo_wide_t [NumPorts-1:0] floo_wide_iB,
  input  floo_wide_t [NumPorts-1:0] floo_wide_iC,
  output floo_wide_t [NumPorts-1:0] floo_wide_oA,
  output floo_wide_t [NumPorts-1:0] floo_wide_oB,
  output floo_wide_t [NumPorts-1:0] floo_wide_oC
  `ifdef TARGET_FTMR
    , .tmrErrorA       ( tmrErrorA             )
    , .tmrErrorB       ( tmrErrorB             )
    , .tmrErrorC       ( tmrErrorC             )
  `endif
`else
  // For STMR, the wrapper exposes single-copy I/O (no replica signals exist).
  input  logic test_enable_i,
  input  id_t id_i,
  input  logic id_route_map_i,
  input  floo_req_t [NumPorts-1:0] floo_req_i,
  input  floo_rsp_t [NumPorts-1:0] floo_rsp_i,
  output floo_req_t [NumPorts-1:0] floo_req_o,
  output floo_rsp_t [NumPorts-1:0] floo_rsp_o,
  input  floo_wide_t [NumPorts-1:0] floo_wide_i,
  output floo_wide_t [NumPorts-1:0] floo_wide_o,
  output tmrError
`endif
);

  floo_nw_routerTMR #(
    .AxiCfgN      ( AxiCfgN             ),
    .AxiCfgW      ( AxiCfgW             ),
    .RouteAlgo    ( RouteCfg.RouteAlgo  ),
    .NumRoutes    ( NumPorts            ),
    .NumAddrRules ( 1                   ),
    .InFifoDepth  ( InFifoDepth         ),
    .OutFifoDepth ( OutFifoDepth        ),
    .XYRouteOpt   ( 1'b1                ),
    .id_t         ( id_t                ),
    .hdr_t        ( hdr_t               ),
    .floo_req_t   ( floo_req_t          ),
    .floo_rsp_t   ( floo_rsp_t          ),
    .floo_wide_t  ( floo_wide_t         )
  ) i_floo_nw_router (
    .clk_iA          ( clk_iA          ),
    .clk_iB          ( clk_iB          ),
    .clk_iC          ( clk_iC          ),
    .rst_niA         ( rst_niA         ),
    .rst_niB         ( rst_niB         ),
    .rst_niC         ( rst_niC         ),
    `ifndef TARGET_STMR
      .test_enable_iA  ( test_enable_iA  ),
      .test_enable_iB  ( test_enable_iB  ),
      .test_enable_iC  ( test_enable_iC  ),
      .id_iA           ( id_iA           ),
      .id_iB           ( id_iB           ),
      .id_iC           ( id_iC           ),
      .id_route_map_iA ( id_route_map_iA ),
      .id_route_map_iB ( id_route_map_iB ),
      .id_route_map_iC ( id_route_map_iC ),
      .floo_req_iA     ( floo_req_iA      ),
      .floo_req_iB     ( floo_req_iB      ),
      .floo_req_iC     ( floo_req_iC      ),
      .floo_rsp_iA     ( floo_rsp_iA      ),
      .floo_rsp_iB     ( floo_rsp_iB      ),
      .floo_rsp_iC     ( floo_rsp_iC      ),
      .floo_req_oA     ( floo_req_oA      ),
      .floo_req_oB     ( floo_req_oB      ),
      .floo_req_oC     ( floo_req_oC      ),
      .floo_rsp_oA     ( floo_rsp_oA      ),
      .floo_rsp_oB     ( floo_rsp_oB      ),
      .floo_rsp_oC     ( floo_rsp_oC      ),
      .floo_wide_iA    ( floo_wide_iA     ),
      .floo_wide_iB    ( floo_wide_iB     ),
      .floo_wide_iC    ( floo_wide_iC     ),
      .floo_wide_oA    ( floo_wide_oA     ),
      .floo_wide_oB    ( floo_wide_oB     ),
      .floo_wide_oC    ( floo_wide_oC     )
      `ifdef TARGET_FTMR
      , .tmrErrorA       (              )
      , .tmrErrorB       (              )
      , .tmrErrorC       (              )
      `endif
    `else
      .test_enable_i   ( test_enable_i   ),
      .id_i            ( id_i            ),
      .id_route_map_i  ( id_route_map_i  ),
      .floo_req_i      ( floo_req_i      ),
      .floo_rsp_i      ( floo_rsp_i      ),
      .floo_req_o      ( floo_req_o      ),
      .floo_rsp_o      ( floo_rsp_o      ),
      .floo_wide_i     ( floo_wide_i     ),
      .floo_wide_o     ( floo_wide_o     ),
      .tmrError        ( tmrError        )
    `endif
  );

endmodule