// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Tim Fischer <fischeti@iis.ee.ethz.ch>

module relfloo_synth_nw_router
  import floo_pkg::*;
  import floo_synth_params_pkg::*;
  import relfloo_synth_nw_pkg::*;
  import floo_synth_collective_pkg::*;
#(
  parameter int unsigned           NumPorts      = int'(floo_pkg::NumDirections),
  parameter collective_cfg_idx_e   CollectCfgIdx = CollectNone
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic test_enable_i,

  input  id_t id_i,
  input logic id_route_map_i,

  input  relfloo_req_t [NumPorts-1:0] floo_req_i,
  input  relfloo_rsp_t [NumPorts-1:0] floo_rsp_i,
  output relfloo_req_t [NumPorts-1:0] floo_req_o,
  output relfloo_rsp_t [NumPorts-1:0] floo_rsp_o,
  input  relfloo_wide_t   [NumPorts-1:0] floo_wide_i,
  output relfloo_wide_t   [NumPorts-1:0] floo_wide_o,
  /// Wide interface towards the offload logic
  output red_wide_req_t   offload_wide_req_o,
  input  red_wide_rsp_t   offload_wide_rsp_i,
  /// Narrow interface towards the offload logic
  output red_narrow_req_t offload_narrow_req_o,
  input  red_narrow_rsp_t offload_narrow_rsp_i,

  output logic [1:0] faults_o
);

// Build a CollectiveCfg derived from CollectRouteCfg but with OpCfg selected by CollectCfgIdx
localparam floo_pkg::collective_cfg_t ActiveCollectiveCfg = '{
  OpCfg:      CollectOpCfgList[CollectCfgIdx],
  NarrRedCfg: CollectRouteCfg.CollectiveCfg.NarrRedCfg,
  WideRedCfg: CollectRouteCfg.CollectiveCfg.WideRedCfg
};

relfloo_nw_router #(
  .AxiCfgN        ( AxiCfgN             ),
  .AxiCfgW        ( AxiCfgW             ),
  .RouteAlgo      ( RouteCfg.RouteAlgo  ),
  .NumRoutes      ( NumPorts            ),
  .NumAddrRules   ( 1                   ),
  .InFifoDepth    ( InFifoDepth         ),
  .OutFifoDepth   ( OutFifoDepth        ),
  .XYRouteOpt     ( 1'b0                ),
  .WideRwDecouple ( WideRwDecouple      ),
  .VcImpl         ( VcImpl              ),
  .NoLoopback     ( 1'b0                ),
  .CollectiveCfg  ( ActiveCollectiveCfg ),
  .id_t             ( id_t             ),
  .hdr_t            ( hdr_t            ),
  .floo_req_t       ( relfloo_req_t       ),
  .floo_rsp_t       ( relfloo_rsp_t       ),
  .floo_wide_t      ( relfloo_wide_t      ),
  .red_wide_req_t   ( red_wide_req_t   ),
  .red_wide_rsp_t   ( red_wide_rsp_t   ),
  .red_narrow_req_t ( red_narrow_req_t ),
  .red_narrow_rsp_t ( red_narrow_rsp_t )
) i_floo_nw_router (
  .clk_i          ( clk_i           ),
  .rst_ni         ( rst_ni          ),
  .test_enable_i  ( test_enable_i   ),
  .id_i           ( {id_i,id_i,id_i}      ),
  .id_route_map_i ( {3{id_route_map_i}}   ),
  .floo_req_i     ( floo_req_i      ),
  .floo_rsp_i     ( floo_rsp_i      ),
  .floo_req_o     ( floo_req_o      ),
  .floo_rsp_o     ( floo_rsp_o      ),
  .floo_wide_i    ( floo_wide_i     ),
  .floo_wide_o    ( floo_wide_o     ),
  // Wide Reduction offload port
  .offload_wide_req_o   ( offload_wide_req_o ),
  .offload_wide_rsp_i   ( offload_wide_rsp_i ),
  // Narrow Reduction offload port
  .offload_narrow_req_o ( offload_narrow_req_o ),
  .offload_narrow_rsp_i ( offload_narrow_rsp_i ),
  .faults_o (faults_o)
);


endmodule
