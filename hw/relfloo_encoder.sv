// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Chen Wu <chenwu@iis.ee.ethz.ch>

// This module packs handshake and payload into a reliable flit
// with handshakes triplicated and payload protected by Hsiao ECC
module relfloo_encoder import floo_pkg::*; 
#(
    parameter type chan_t = logic,
    parameter type rel_chan_t = logic
) (
    input logic valid_i,
    input logic ready_i,
    input chan_t chan_i,
    output logic [2:0] valid_o,
    output logic [2:0] ready_o,
    output rel_chan_t chan_o
);

  assign valid_o = {3{valid_i}}; // triplicate valid
  assign ready_o = {3{ready_i}}; // triplicate ready
  assign chan_o.generic.hdr = '{default: chan_i.generic.hdr}; // triplicate hdr
  assign chan_o.generic.payload = chan_i.generic.payload;

  localparam int unsigned PayloadTotalWidth = $bits(chan_i.generic.payload);
  localparam int unsigned NumChunks = (PayloadTotalWidth + MAX_ECC_DATA_BITS - 1) / MAX_ECC_DATA_BITS;

  for (genvar i = 0; i < NumChunks; i++) begin : gen_ecc_enc
    localparam int unsigned CurChunkWidth = (i == NumChunks - 1) 
                                          ? (PayloadTotalWidth - i * MAX_ECC_DATA_BITS) 
                                          : MAX_ECC_DATA_BITS;
    localparam int unsigned CurECCWidth = hsiao_ecc_pkg::min_ecc(CurChunkWidth);
    logic [CurECCWidth-1:0] ecc_tmp;
    hsiao_ecc_enc #(
      .DataWidth ( CurChunkWidth )
    ) i_ecc_enc (
      .in   ( chan_i.generic.payload[i*MAX_ECC_DATA_BITS +: CurChunkWidth] ),
      .out  ( ),
      .codes( ecc_tmp )
    );
    assign chan_o.generic.ecc[i] = (CurECCWidth < ECC_BITS)
                                    ? { { (ECC_BITS - CurECCWidth) {1'b0} }, ecc_tmp }
                                    : ecc_tmp;
  end

endmodule