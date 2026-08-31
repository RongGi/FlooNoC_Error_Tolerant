// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Chen Wu <chenwu@iis.ee.ethz.ch>

// A tile consisting of a narrow AXI test node, a wide AXI test node, a nw_router, and a network interface.
module floo_nw_tile #(
  parameter int unsigned DELAY = 0,
  parameter time ApplTime = 2ns,
  parameter time TestTime = 8ns,
  parameter int unsigned NarrowNumReads = 0,
  parameter int unsigned NarrowNumWrites = 0,
  parameter int unsigned WideNumReads = 0,
  parameter int unsigned WideNumWrites = 0,
  parameter int unsigned NumAddrRegions  = 0,
  parameter type node_addr_region_t = logic,
  parameter node_addr_region_t [NumAddrRegions-1:0] AddrRegions = '0,

  parameter type id_t = logic,
  parameter type hdr_t = logic,

  parameter type axi_narrow_in_req_t = logic,
  parameter type axi_narrow_in_rsp_t = logic,
  parameter type axi_narrow_out_req_t = logic,
  parameter type axi_narrow_out_rsp_t = logic,
  parameter type axi_wide_in_req_t = logic,
  parameter type axi_wide_in_rsp_t = logic,
  parameter type axi_wide_out_req_t = logic,
  parameter type axi_wide_out_rsp_t = logic,

  parameter type floo_req_t = logic,
  parameter type floo_rsp_t = logic,
  parameter type floo_wide_t = logic
) (
  input logic clk_i,
  input logic rst_ni,

  input id_t id_i,

  /// Input and output links
  input   floo_req_t [floo_pkg::West:floo_pkg::North] floo_req_i,
  input   floo_rsp_t [floo_pkg::West:floo_pkg::North] floo_rsp_i,
  output  floo_req_t [floo_pkg::West:floo_pkg::North] floo_req_o,
  output  floo_rsp_t [floo_pkg::West:floo_pkg::North] floo_rsp_o,
  input   floo_wide_t [floo_pkg::West:floo_pkg::North] floo_wide_i,
  output  floo_wide_t [floo_pkg::West:floo_pkg::North] floo_wide_o,

  output floo_req_t floo_req_Eject_in_o,
  output floo_req_t floo_req_Eject_out_o,
  output floo_rsp_t floo_rsp_Eject_in_o,
  output floo_rsp_t floo_rsp_Eject_out_o,
  output floo_wide_t floo_wide_Eject_in_o,
  output floo_wide_t floo_wide_Eject_out_o,

  output logic [1:0] end_of_sim
);

  axi_narrow_in_req_t chimney_narrow_in_req;
  axi_narrow_in_rsp_t chimney_narrow_in_rsp;
  axi_narrow_out_req_t chimney_narrow_out_req;
  axi_narrow_out_rsp_t chimney_narrow_out_rsp;
  axi_wide_in_req_t chimney_wide_in_req;
  axi_wide_in_rsp_t chimney_wide_in_rsp;
  axi_wide_out_req_t chimney_wide_out_req;
  axi_wide_out_rsp_t chimney_wide_out_rsp;

  floo_req_t [floo_pkg::Eject:floo_pkg::North] floo_req_out, floo_req_in;
  floo_rsp_t [floo_pkg::Eject:floo_pkg::North] floo_rsp_out, floo_rsp_in;
  floo_wide_t [floo_pkg::Eject:floo_pkg::North] floo_wide_out, floo_wide_in;

  floo_axi_test_node #(
    .DELAY ( DELAY*2 ),
    .AxiCfg         ( floo_test_pkg::AxiCfgN  ),
    .mst_req_t      ( axi_narrow_in_req_t     ),
    .mst_rsp_t      ( axi_narrow_in_rsp_t     ),
    .slv_req_t      ( axi_narrow_out_req_t    ),
    .slv_rsp_t      ( axi_narrow_out_rsp_t    ),
    .ApplTime       ( ApplTime                ),
    .TestTime       ( TestTime                ),
    // .Atops          ( floo_test_pkg::AtopSupport ),
    .NumAddrRegions ( NumAddrRegions          ),
    .rule_t         ( node_addr_region_t      ),
    .AddrRegions    ( AddrRegions             ),
    .AxiMaxBurstLen ( 4                       ),
    .NumReads       ( NarrowNumReads          ),
    .NumWrites      ( NarrowNumWrites         )
  ) i_narrow_test_node (
    .clk_i,
    .rst_ni,
    .slv_port_req_i   ( chimney_narrow_out_req ),
    .slv_port_rsp_o   ( chimney_narrow_out_rsp ),
    .mst_port_req_o   ( chimney_narrow_in_req  ),
    .mst_port_rsp_i   ( chimney_narrow_in_rsp  ),
    .end_of_sim       ( end_of_sim[0]          )
  );

  floo_axi_test_node #(
    .DELAY ( DELAY*2+1 ),
    .AxiCfg         ( floo_test_pkg::AxiCfgW  ),
    .mst_req_t      ( axi_wide_in_req_t       ),
    .mst_rsp_t      ( axi_wide_in_rsp_t       ),
    .slv_req_t      ( axi_wide_out_req_t      ),
    .slv_rsp_t      ( axi_wide_out_rsp_t      ),
    .ApplTime       ( ApplTime                ),
    .TestTime       ( TestTime                ),
    // .Atops          ( floo_test_pkg::AtopSupport ),
    .NumAddrRegions ( NumAddrRegions          ),
    .rule_t         ( node_addr_region_t      ),
    .AddrRegions    ( AddrRegions             ),
    .AxiMaxBurstLen ( 4                       ),
    .NumReads       ( WideNumReads            ),
    .NumWrites      ( WideNumWrites           )
  ) i_wide_test_node (
    .clk_i,
    .rst_ni,
    .slv_port_req_i   ( chimney_wide_out_req ),
    .slv_port_rsp_o   ( chimney_wide_out_rsp ),
    .mst_port_req_o   ( chimney_wide_in_req  ),
    .mst_port_rsp_i   ( chimney_wide_in_rsp  ),
    .end_of_sim       ( end_of_sim[1]        )
  );

  floo_nw_chimney #(
    .AxiCfgN              ( floo_test_pkg::AxiCfgN         ),
    .AxiCfgW              ( floo_test_pkg::AxiCfgW         ),
    .ChimneyCfgN          ( floo_test_pkg::ChimneyCfg      ),
    .ChimneyCfgW          ( floo_test_pkg::ChimneyCfg      ),
    .RouteCfg             ( floo_test_pkg::RouteCfg        ),
    // .AtopSupport          ( floo_test_pkg::AtopSupport     ),
    // .MaxAtomicTxns        ( 1'b1   ),
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
    .clk_i,
    .rst_ni,
    .test_enable_i  ( 1'b0 ),
    .id_i,
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
    .floo_req_o           ( floo_req_in[floo_pkg::Eject]      ),
    .floo_rsp_o           ( floo_rsp_in[floo_pkg::Eject]      ),
    .floo_wide_o          ( floo_wide_in[floo_pkg::Eject]     ),
    .floo_req_i           ( floo_req_out[floo_pkg::Eject]     ),
    .floo_rsp_i           ( floo_rsp_out[floo_pkg::Eject]     ),
    .floo_wide_i          ( floo_wide_out[floo_pkg::Eject]    )
  );

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
  ) i_floo_nw_router (
    .clk_i,
    .rst_ni,
    .test_enable_i  ( 1'b0 ),
    .id_i,
    .id_route_map_i ( '0             ),
    .floo_req_i     ( floo_req_in    ),
    .floo_rsp_i     ( floo_rsp_in    ),
    .floo_req_o     ( floo_req_out   ),
    .floo_rsp_o     ( floo_rsp_out   ),
    .floo_wide_i    ( floo_wide_in   ),
    .floo_wide_o    ( floo_wide_out  ),
    .offload_wide_req_o(),
    .offload_wide_rsp_i(),
    .offload_narrow_req_o(),
    .offload_narrow_rsp_i()
  );

  assign floo_req_in[floo_pkg::West:floo_pkg::North] = floo_req_i;
  assign floo_rsp_in[floo_pkg::West:floo_pkg::North] = floo_rsp_i;
  assign floo_wide_in[floo_pkg::West:floo_pkg::North] = floo_wide_i;
  assign floo_req_o = floo_req_out;
  assign floo_rsp_o = floo_rsp_out;
  assign floo_wide_o = floo_wide_out;

  assign floo_req_Eject_in_o = floo_req_in[floo_pkg::Eject];
  assign floo_req_Eject_out_o = floo_req_out[floo_pkg::Eject];
  assign floo_rsp_Eject_in_o = floo_rsp_in[floo_pkg::Eject];
  assign floo_rsp_Eject_out_o = floo_rsp_out[floo_pkg::Eject];
  assign floo_wide_Eject_in_o = floo_wide_in[floo_pkg::Eject];
  assign floo_wide_Eject_out_o = floo_wide_out[floo_pkg::Eject];

endmodule