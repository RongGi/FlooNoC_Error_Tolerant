// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Chen Wu <chenwu@iis.ee.ethz.ch>

// This module unpack the reliable flit into handshake and payload
// It performs majority voting on triplicated handshakes and triplicated hdr 
// and Hsiao ECC decoding on payload
module relfloo_decoder import floo_pkg::*; 
#(
    type chan_t = logic,
    type rel_chan_t = logic
) (
    input logic [2:0] valid_i,
    input logic [2:0] ready_i,
    input rel_chan_t chan_i,
    output logic valid_o,
    output logic ready_o,
    output chan_t chan_o
);

  TMR_voter_fail i_valid_tmr (
    .a_i              ( valid_i[0] ),
    .b_i              ( valid_i[1] ),
    .c_i              ( valid_i[2] ),
    .majority_o       ( valid_o ),
    .fault_detected_o ( )
  );

  TMR_voter_fail i_ready_tmr (
    .a_i              ( ready_i[0] ),
    .b_i              ( ready_i[1] ),
    .c_i              ( ready_i[2] ),
    .majority_o       ( ready_o ),
    .fault_detected_o ( )
  );

  bitwise_TMR_voter_fail #(
    .DataWidth ( $bits(chan_o.generic.hdr) ),
    .VoterType ( 1 )
  ) i_hdr_tmr (
    .a_i              ( chan_i.generic.hdr[0] ),
    .b_i              ( chan_i.generic.hdr[1] ),
    .c_i              ( chan_i.generic.hdr[2] ),
    .majority_o       ( chan_o.generic.hdr ),
    .fault_detected_o ( )
  );

  localparam int unsigned PayloadTotalWidth = $bits(chan_i.generic.payload);
  localparam int unsigned NumChunks = (PayloadTotalWidth + MAX_ECC_DATA_BITS - 1) / MAX_ECC_DATA_BITS;

  for (genvar i = 0; i < NumChunks; i++) begin : gen_ecc_dec
    localparam int unsigned CurChunkWidth = (i == NumChunks - 1) 
                                          ? (PayloadTotalWidth - i * MAX_ECC_DATA_BITS) 
                                          : MAX_ECC_DATA_BITS;
    localparam int unsigned CurECCWidth = hsiao_ecc_pkg::min_ecc(CurChunkWidth);
    logic [CurECCWidth + CurChunkWidth -1:0] chunk_tmp;
    assign chunk_tmp = (CurECCWidth < ECC_BITS)
                      ? { chan_i.generic.ecc[i][CurECCWidth-1:0],
                          chan_i.generic.payload[ i * MAX_ECC_DATA_BITS +: CurChunkWidth ] }
                      : { chan_i.generic.ecc[i],
                          chan_i.generic.payload[ i * MAX_ECC_DATA_BITS +: CurChunkWidth ] };
    hsiao_ecc_dec #(
      .DataWidth ( CurChunkWidth )
    ) i_req_ecc_dec (
      .in    ( chunk_tmp ),
      .out   ( chan_o.generic.payload[ i * MAX_ECC_DATA_BITS +: CurChunkWidth ] ),
      .syndrome_o (),
      .err_o ()
    );
  end

endmodule