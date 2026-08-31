// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Chen Wu <chenwu@iis.ee.ethz.ch>

module floo_mesh_monitor #(
  parameter bit Verbose = 0,
  parameter int unsigned NumX = 3,
  parameter int unsigned NumY = 3,
  parameter type floo_req_t = logic,
  parameter type floo_rsp_t = logic,
  parameter type floo_wide_t = logic,
  parameter type floo_axi_narrow_aw_flit_t = logic,
  parameter type floo_axi_narrow_w_flit_t = logic,
  parameter type floo_axi_narrow_ar_flit_t = logic,
  parameter type floo_axi_wide_ar_flit_t = logic,
  parameter type floo_axi_narrow_b_flit_t = logic,
  parameter type floo_axi_narrow_r_flit_t = logic,
  parameter type floo_axi_wide_b_flit_t = logic,
  parameter type floo_axi_wide_aw_flit_t = logic,
  parameter type floo_axi_wide_w_flit_t = logic,
  parameter type floo_axi_wide_r_flit_t = logic
) (
  input logic clk_i,
  input floo_req_t [NumX-1:0][NumY-1:0] floo_req_in_i,
  input floo_req_t [NumX-1:0][NumY-1:0] floo_req_out_i,
  input floo_rsp_t [NumX-1:0][NumY-1:0] floo_rsp_in_i,
  input floo_rsp_t [NumX-1:0][NumY-1:0] floo_rsp_out_i,
  input floo_wide_t [NumX-1:0][NumY-1:0] floo_wide_in_i,
  input floo_wide_t [NumX-1:0][NumY-1:0] floo_wide_out_i,
  output logic end_of_sim_o
);

  import floo_pkg::*;

floo_axi_narrow_aw_flit_t aw_narrow_queue [NumX-1:0][NumY-1:0][$];
floo_axi_narrow_w_flit_t w_narrow_queue [NumX-1:0][NumY-1:0][$];
floo_axi_narrow_ar_flit_t ar_narrow_queue [NumX-1:0][NumY-1:0][$];
floo_axi_wide_ar_flit_t ar_wide_queue [NumX-1:0][NumY-1:0][$];
floo_axi_narrow_b_flit_t b_narrow_queue [NumX-1:0][NumY-1:0][$];
floo_axi_narrow_r_flit_t r_narrow_queue [NumX-1:0][NumY-1:0][$];
floo_axi_wide_b_flit_t b_wide_queue [NumX-1:0][NumY-1:0][$];
floo_axi_wide_aw_flit_t aw_wide_queue [NumX-1:0][NumY-1:0][$];
floo_axi_wide_w_flit_t w_wide_queue [NumX-1:0][NumY-1:0][$];
floo_axi_wide_r_flit_t r_wide_queue [NumX-1:0][NumY-1:0][$];

  floo_axi_narrow_aw_flit_t aw_narrow_pending_queue [NumX-1:0][NumY-1:0][$];
  floo_axi_wide_aw_flit_t   aw_wide_pending_queue   [NumX-1:0][NumY-1:0][$];
  floo_axi_narrow_ar_flit_t ar_narrow_pending_queue [NumX-1:0][NumY-1:0][$];
  floo_axi_wide_ar_flit_t   ar_wide_pending_queue   [NumX-1:0][NumY-1:0][$];

  always_ff @(posedge clk_i) begin : send_req_narrow
    for (int x = 0; x < NumX; x++) begin
      for (int y = 0; y < NumY; y++) begin
        if (floo_req_in_i[x][y].valid && floo_req_out_i[x][y].ready) begin
          automatic nw_ch_e ch = floo_req_in_i[x][y].req.generic.hdr.axi_ch;
          unique case (ch)
            NarrowAw: begin
              automatic floo_axi_narrow_aw_flit_t flit = floo_req_in_i[x][y].req.narrow_aw;
              aw_narrow_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
              if (Verbose) $display("[MON %0t] node (%0d,%0d) send AW to node (%0d,%0d), len %0d",
                       $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, flit.payload.len);
            end
            NarrowW: begin
              automatic floo_axi_narrow_w_flit_t flit = floo_req_in_i[x][y].req.narrow_w;
              if ((aw_narrow_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].size() == 0) &&
                  (aw_narrow_pending_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].size() == 0)) begin
                $error("No AW for W narrow dst (%0d,%0d)", flit.hdr.dst_id.x, flit.hdr.dst_id.y);
              end
              w_narrow_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
              if (Verbose) $display("[MON %0t] node (%0d,%0d) send W to node (%0d,%0d), data %0h",
                       $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, floo_req_in_i[x][y].req.generic.payload);
            end
            NarrowAr: begin
              automatic floo_axi_narrow_ar_flit_t flit = floo_req_in_i[x][y].req.narrow_ar;
              ar_narrow_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
              if (Verbose) $display("[MON %0t] node (%0d,%0d) send AR to node (%0d,%0d), len %0d",
                       $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, flit.payload.len);
            end
            WideAr: begin
              automatic floo_axi_wide_ar_flit_t flit = floo_req_in_i[x][y].req.wide_ar;
              ar_wide_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
              if (Verbose) $display("[MON %0t] node (%0d,%0d) send wide AR to node (%0d,%0d), len %0d",
                       $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, flit.payload.len);
            end
            default: ;
          endcase
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin : send_req_wide
    for (int x = 0; x < NumX; x++) begin
      for (int y = 0; y < NumY; y++) begin
        if (floo_wide_in_i[x][y].valid && floo_wide_out_i[x][y].ready) begin
          automatic nw_ch_e ch = floo_wide_in_i[x][y].wide.generic.hdr.axi_ch;
          unique case (ch)
            WideAw: begin
              automatic floo_axi_wide_aw_flit_t flit = floo_wide_in_i[x][y].wide.wide_aw;
              aw_wide_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
              if (Verbose) $display("[MON %0t] node (%0d,%0d) send wide AW to node (%0d,%0d), len %0d",
                       $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, flit.payload.len);
            end
            WideW: begin
              automatic floo_axi_wide_w_flit_t flit = floo_wide_in_i[x][y].wide.wide_w;
              if ((aw_wide_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].size() == 0) &&
                  (aw_wide_pending_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].size() == 0)) begin
                $error("No AW for W wide dst (%0d,%0d)", flit.hdr.dst_id.x, flit.hdr.dst_id.y);
              end
              w_wide_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
              if (Verbose) $display("[MON %0t] node (%0d,%0d) send wide W to node (%0d,%0d), data %0h",
                       $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, floo_wide_in_i[x][y].wide.generic.payload);
            end
            WideR: begin
              automatic floo_axi_wide_r_flit_t flit = floo_wide_in_i[x][y].wide.wide_r;
              if (ar_wide_pending_queue[x][y].size() == 0) begin
                $error("No AR for wide R send from (%0d,%0d)", x, y);
              end
              r_wide_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
              if (flit.payload.last) void'(ar_wide_pending_queue[x][y].pop_front());
              if (Verbose) $display("[MON %0t] node (%0d,%0d) send wide R to node (%0d,%0d), data %0h",
                       $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, floo_wide_in_i[x][y].wide.generic.payload);
            end
            default: ;
          endcase
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin : recv_req_narrow
    for (int x = 0; x < NumX; x++) begin
      for (int y = 0; y < NumY; y++) begin
        if (floo_req_out_i[x][y].valid && floo_req_in_i[x][y].ready) begin
          automatic nw_ch_e ch = floo_req_out_i[x][y].req.generic.hdr.axi_ch;
          unique case (ch)
            NarrowAw: begin
              automatic int match_idx = -1;
              for (int i = 0; i < aw_narrow_queue[x][y].size(); i++) begin
                if (aw_narrow_queue[x][y][i] === floo_req_out_i[x][y].req.narrow_aw) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No AW queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_narrow_aw_flit_t exp = aw_narrow_queue[x][y][match_idx];
                aw_narrow_queue[x][y].delete(match_idx);
                aw_narrow_pending_queue[x][y].push_back(exp);
                if(Verbose) $display("[MON %0t] node (%0d,%0d) recv AW from node (%0d,%0d), len %0d",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, exp.payload.len);
              end
            end
            NarrowW: begin
              automatic int match_idx = -1;
              for (int i = 0; i < w_narrow_queue[x][y].size(); i++) begin
                if (w_narrow_queue[x][y][i] === floo_req_out_i[x][y].req.narrow_w) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No W queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_narrow_w_flit_t exp = w_narrow_queue[x][y][match_idx];
                w_narrow_queue[x][y].delete(match_idx);
                if (aw_narrow_pending_queue[x][y].size() == 0) begin
                  $error("No AW for W at (%0d,%0d)", x, y);
                end
                if(Verbose) $display("[MON %0t] node (%0d,%0d) recv W from node (%0d,%0d), data %0h",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, floo_req_out_i[x][y].req.generic.payload);
              end
            end
            NarrowAr: begin
              automatic int match_idx = -1;
              for (int i = 0; i < ar_narrow_queue[x][y].size(); i++) begin
                if (ar_narrow_queue[x][y][i] === floo_req_out_i[x][y].req.narrow_ar) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No AR queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_narrow_ar_flit_t exp = ar_narrow_queue[x][y][match_idx];
                ar_narrow_queue[x][y].delete(match_idx);
                ar_narrow_pending_queue[x][y].push_back(exp);
                if(Verbose) $display("[MON %0t] node (%0d,%0d) recv AR from node (%0d,%0d), len %0d",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, exp.payload.len);
              end
            end
            WideAr: begin
              automatic int match_idx = -1;
              for (int i = 0; i < ar_wide_queue[x][y].size(); i++) begin
                if (ar_wide_queue[x][y][i] === floo_req_out_i[x][y].req.wide_ar) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No wide AR queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_wide_ar_flit_t exp = ar_wide_queue[x][y][match_idx];
                ar_wide_queue[x][y].delete(match_idx);
                ar_wide_pending_queue[x][y].push_back(exp);
                if(Verbose) $display("[MON %0t] node (%0d,%0d) recv wide AR from node (%0d,%0d), len %0d",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, exp.payload.len);
              end
            end
            default: ;
          endcase
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin : recv_req_wide
    for (int x = 0; x < NumX; x++) begin
      for (int y = 0; y < NumY; y++) begin
        if (floo_wide_out_i[x][y].valid && floo_wide_in_i[x][y].ready) begin
          automatic nw_ch_e ch = floo_wide_out_i[x][y].wide.generic.hdr.axi_ch;
          unique case (ch)
            WideAw: begin
              automatic int match_idx = -1;
              for (int i = 0; i < aw_wide_queue[x][y].size(); i++) begin
                if (aw_wide_queue[x][y][i] === floo_wide_out_i[x][y].wide.wide_aw) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No wide AW queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_wide_aw_flit_t exp = aw_wide_queue[x][y][match_idx];
                aw_wide_queue[x][y].delete(match_idx);
                aw_wide_pending_queue[x][y].push_back(exp);
                if(Verbose) $display("[MON %0t] node (%0d,%0d) recv wide AW from node (%0d,%0d), len %0d",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, exp.payload.len);
              end
            end
            WideW: begin
              automatic int match_idx = -1;
              for (int i = 0; i < w_wide_queue[x][y].size(); i++) begin
                if (w_wide_queue[x][y][i] === floo_wide_out_i[x][y].wide.wide_w) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No wide W queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_wide_w_flit_t exp = w_wide_queue[x][y][match_idx];
                w_wide_queue[x][y].delete(match_idx);
                if (aw_wide_pending_queue[x][y].size() == 0) begin
                  $error("No AW for wide W at (%0d,%0d)", x, y);
                end
                if(Verbose) $display("[MON %0t] node (%0d,%0d) recv wide W from node (%0d,%0d), data %0h",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, floo_wide_out_i[x][y].wide.generic.payload);
              end
            end
            WideR: begin
              automatic floo_axi_wide_r_flit_t exp;
              automatic int match_idx = -1;
              for (int i = 0; i < r_wide_queue[x][y].size(); i++) begin
                if (r_wide_queue[x][y][i] === floo_wide_out_i[x][y].wide.wide_r) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No wide R queued for recv at (%0d,%0d)", x, y);
              end else begin
                exp = r_wide_queue[x][y][match_idx];
                r_wide_queue[x][y].delete(match_idx);
                if(Verbose) $display("[MON %0t] node (%0d,%0d) recv wide R from node (%0d,%0d), data %0h",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, floo_wide_out_i[x][y].wide.generic.payload);
              end
            end
            default: ;
          endcase
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin : send_rsp
    for (int x = 0; x < NumX; x++) begin
      for (int y = 0; y < NumY; y++) begin
        if (floo_rsp_in_i[x][y].valid && floo_rsp_out_i[x][y].ready) begin
          automatic nw_ch_e ch = floo_rsp_in_i[x][y].rsp.generic.hdr.axi_ch;
          unique case (ch)
            NarrowB: begin
              if (aw_narrow_pending_queue[x][y].size() == 0) begin
                $error("No AW for B at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_narrow_b_flit_t flit = floo_rsp_in_i[x][y].rsp.narrow_b;
                b_narrow_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
                void'(aw_narrow_pending_queue[x][y].pop_front());
                if (Verbose) $display("[MON %0t] node (%0d,%0d) send B to node (%0d,%0d), resp %0h",
                         $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, floo_rsp_in_i[x][y].rsp.generic.payload);
              end
            end
            NarrowR: begin
              if (ar_narrow_pending_queue[x][y].size() == 0) begin
                $error("No AR for R at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_narrow_r_flit_t flit = floo_rsp_in_i[x][y].rsp.narrow_r;
                r_narrow_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
                if (flit.payload.last) void'(ar_narrow_pending_queue[x][y].pop_front());
                if (Verbose) $display("[MON %0t] node (%0d,%0d) send R to node (%0d,%0d), resp %0h",
                         $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, floo_rsp_in_i[x][y].rsp.generic.payload);
              end
            end
            WideB: begin
              if (aw_wide_pending_queue[x][y].size() == 0) begin
                $error("No AW for wide B at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_wide_b_flit_t flit = floo_rsp_in_i[x][y].rsp.wide_b;
                b_wide_queue[flit.hdr.dst_id.x][flit.hdr.dst_id.y].push_back(flit);
                void'(aw_wide_pending_queue[x][y].pop_front());
                if (Verbose) $display("[MON %0t] node (%0d,%0d) send wide B to node (%0d,%0d), resp %0h",
                         $time, x, y, flit.hdr.dst_id.x, flit.hdr.dst_id.y, floo_rsp_in_i[x][y].rsp.generic.payload);
              end
            end
            default: ;
          endcase
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin : recv_rsp
    for (int x = 0; x < NumX; x++) begin
      for (int y = 0; y < NumY; y++) begin
        if (floo_rsp_out_i[x][y].valid && floo_rsp_in_i[x][y].ready) begin
          automatic nw_ch_e ch = floo_rsp_out_i[x][y].rsp.generic.hdr.axi_ch;
          unique case (ch)
            NarrowB: begin
              automatic int match_idx = -1;
              for (int i = 0; i < b_narrow_queue[x][y].size(); i++) begin
                if (b_narrow_queue[x][y][i] === floo_rsp_out_i[x][y].rsp.narrow_b) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No B queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_narrow_b_flit_t exp = b_narrow_queue[x][y][match_idx];
                b_narrow_queue[x][y].delete(match_idx);
                if (Verbose) $display("[MON %0t] node (%0d,%0d) recv B from node (%0d,%0d), data %0h",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, floo_rsp_out_i[x][y].rsp.generic.payload);
              end
            end
            NarrowR: begin
              automatic int match_idx = -1;
              for (int i = 0; i < r_narrow_queue[x][y].size(); i++) begin
                if (r_narrow_queue[x][y][i] === floo_rsp_out_i[x][y].rsp.narrow_r) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No R queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_narrow_r_flit_t exp = r_narrow_queue[x][y][match_idx];
                r_narrow_queue[x][y].delete(match_idx);
                if (Verbose) $display("[MON %0t] node (%0d,%0d) recv R from node (%0d,%0d), data %0h",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, floo_rsp_out_i[x][y].rsp.generic.payload);
              end
            end
            WideB: begin
              automatic int match_idx = -1;
              for (int i = 0; i < b_wide_queue[x][y].size(); i++) begin
                if (b_wide_queue[x][y][i] === floo_rsp_out_i[x][y].rsp.wide_b) begin
                  match_idx = i;
                  break;
                end
              end
              if (match_idx < 0) begin
                $error("No wide B queued for recv at (%0d,%0d)", x, y);
              end else begin
                automatic floo_axi_wide_b_flit_t exp = b_wide_queue[x][y][match_idx];
                b_wide_queue[x][y].delete(match_idx);
                if (Verbose) $display("[MON %0t] node (%0d,%0d) recv wide B from node (%0d,%0d), data %0h",
                         $time, x, y, exp.hdr.src_id.x, exp.hdr.src_id.y, floo_rsp_out_i[x][y].rsp.generic.payload);
              end
            end
            default: ;
          endcase
        end
      end
    end
  end

  logic end_of_sim_d;

  always_ff @(posedge clk_i) begin
    end_of_sim_d = 1'b1;
    for (int x = 0; x < NumX; x++) begin
      for (int y = 0; y < NumY; y++) begin
        end_of_sim_d &= (aw_narrow_queue[x][y].size() == 0);
        end_of_sim_d &= (w_narrow_queue[x][y].size() == 0);
        end_of_sim_d &= (ar_narrow_queue[x][y].size() == 0);
        end_of_sim_d &= (ar_wide_queue[x][y].size() == 0);
        end_of_sim_d &= (b_narrow_queue[x][y].size() == 0);
        end_of_sim_d &= (r_narrow_queue[x][y].size() == 0);
        end_of_sim_d &= (b_wide_queue[x][y].size() == 0);
        end_of_sim_d &= (aw_wide_queue[x][y].size() == 0);
        end_of_sim_d &= (w_wide_queue[x][y].size() == 0);
        end_of_sim_d &= (r_wide_queue[x][y].size() == 0);
        end_of_sim_d &= (aw_narrow_pending_queue[x][y].size() == 0);
        end_of_sim_d &= (aw_wide_pending_queue[x][y].size() == 0);
        end_of_sim_d &= (ar_narrow_pending_queue[x][y].size() == 0);
        end_of_sim_d &= (ar_wide_pending_queue[x][y].size() == 0);
      end
    end
    end_of_sim_o <= end_of_sim_d;
  end

endmodule