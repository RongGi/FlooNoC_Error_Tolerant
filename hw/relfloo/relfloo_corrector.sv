// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Rong Gi Ye <rongye@student.ethz.ch>

// passthought corrector, correcting data from input to output
module relfloo_corrector  import floo_pkg::*;
#(
  parameter type chan_t      = logic
) (
    input  logic clk_i   ,
    input  logic rst_ni  ,

    input  chan_t      chan_i,
    output chan_t      chan_o,
    output logic [1:0] fault_o
);

    // ECC Var calc
    localparam int unsigned PayloadTotalWidth = $bits(chan_i.payload);
    localparam int unsigned NumChunks = (PayloadTotalWidth + MAX_ECC_DATA_BITS - 1) / MAX_ECC_DATA_BITS;

    //fault report gen
    logic [2:0]     voter_errs;
    logic            voter_errs_red;
    logic [NumChunks-1:0][1:0]      hsiao_errs;
    logic [1:0][NumChunks-1:0] hsiao_errs_transpose;
    logic [1:0]      hsiao_errs_transpose_red;

    for (genvar i = 0; i < 1; i++) begin : gen_hsiao_errs_transpose
        for (genvar j = 0; j < NumChunks; j++) begin : gen_hsiao_errs_transpose_inner
            assign hsiao_errs_transpose[i][j] = hsiao_errs[j][i];
        end
         assign hsiao_errs_transpose_red[i] = |hsiao_errs_transpose[i];
    end

    assign voter_errs_red = |voter_errs;
    assign fault_o[0] = voter_errs_red | hsiao_errs_transpose_red[0];
    assign fault_o[1] = hsiao_errs_transpose_red[1];

    //TMR
    for (genvar i = 0; i < 3; i++) begin : gen_tmr_part
        
        bitwise_TMR_voter_fail #(
            .DataWidth ( $bits(chan_i.hdr)/3 ),
            .VoterType ( 1 )
        ) i_hdr_tmr (
            .a_i              ( chan_i.hdr[0] ),
            .b_i              ( chan_i.hdr[1] ),
            .c_i              ( chan_i.hdr[2] ),
            .majority_o       ( chan_o.hdr[i] ),
            .fault_detected_o ( voter_errs[i])
        );
    end




    //ECC
    for (genvar i = 0; i < NumChunks; i++) begin : gen_ecc_dec
        localparam int unsigned CurChunkWidth = (i == NumChunks - 1) 
                                            ? (PayloadTotalWidth - i * MAX_ECC_DATA_BITS) 
                                            : MAX_ECC_DATA_BITS;
        localparam int unsigned CurECCWidth = hsiao_ecc_pkg::min_ecc(CurChunkWidth);
        logic [CurECCWidth + CurChunkWidth -1:0] chunk_tmp_in, chunk_tmp_out;
        assign chunk_tmp_in = (CurECCWidth < ECC_BITS)
                        ? { chan_i.ecc[i][CurECCWidth-1:0],
                            chan_i.payload[ i * MAX_ECC_DATA_BITS +: CurChunkWidth ] }
                        : { chan_i.ecc[i],
                            chan_i.payload[ i * MAX_ECC_DATA_BITS +: CurChunkWidth ] };

        // assign chunk_tmp_out = (CurECCWidth < ECC_BITS)
        //                 ? { chan_o.ecc[i][CurECCWidth-1:0],
        //                     chan_o.payload[ i * MAX_ECC_DATA_BITS +: CurChunkWidth ] }
        //                 : { chan_o.ecc[i],
        //                     chan_o.payload[ i * MAX_ECC_DATA_BITS +: CurChunkWidth ] };
        hsiao_ecc_cor #(
        .DataWidth ( CurChunkWidth )
        ) i_req_ecc_cor (
        .in    ( chunk_tmp_in  ),
        .out   ( chunk_tmp_out ),
        .syndrome_o (),
        .err_o (hsiao_errs[i])
        );

        assign chan_o.payload[i * MAX_ECC_DATA_BITS +: CurChunkWidth] =
            chunk_tmp_out[CurChunkWidth-1:0];
        assign chan_o.ecc[i] = (CurECCWidth < ECC_BITS)
                                    ? { { (ECC_BITS - CurECCWidth) {1'b0} },
                                        chunk_tmp_out[CurChunkWidth + CurECCWidth - 1 : CurChunkWidth] }
                                    : chunk_tmp_out[CurChunkWidth + CurECCWidth - 1 : CurChunkWidth];
    end

endmodule