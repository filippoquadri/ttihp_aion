/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Placeholder logic to exercise the CI flow: a bank of NUM_GEN independent
  // 32-bit Fibonacci LFSRs. Structurally trivial, but ~2.5k flops of area.
  localparam integer NUM_GEN = 32;
  localparam integer LFSR_W  = 32;

  wire [7:0] seed = ui_in ^ uio_in;

  // One folded byte per generator.
  wire [8*NUM_GEN-1:0] fold;

  genvar i;
  generate
    for (i = 0; i < NUM_GEN; i = i + 1) begin : g_lfsr
      localparam [7:0] IDX = i;

      reg [LFSR_W-1:0] state;
      reg [7:0] fold_q;

      // x^32 + x^22 + x^2 + x + 1 -> maximal length sequence
      wire feedback = state[31] ^ state[21] ^ state[1] ^ state[0];

      // Fold the 32-bit state into a byte, locally to this generator.
      wire [7:0] fold_d = state[7:0] ^ state[15:8] ^ state[23:16] ^ state[31:24];

      always @(posedge clk) begin
        if (!rst_n) begin
          // The trailing 8'h01 keeps every seed non-zero (LFSR lock-up state).
          state  <= {seed, 8'hA5, IDX, 8'h01};
          fold_q <= 8'h00;
        end else if (ena) begin
          state  <= {state[LFSR_W-2:0], feedback};
          fold_q <= fold_d;
        end
      end

      assign fold[8*i+:8] = fold_q;
    end
  endgenerate

  // XOR the whole bank down to a single byte.
  reg [7:0] mix_c;
  integer k;
  always @* begin
    mix_c = 8'h00;
    for (k = 0; k < NUM_GEN; k = k + 1) mix_c = mix_c ^ fold[8*k+:8];
  end

  reg [7:0] mix_q;
  always @(posedge clk) begin
    if (!rst_n) mix_q <= 8'h00;
    else if (ena) mix_q <= mix_c ^ ui_in;
  end

  // Unchanged behaviour on the dedicated outputs, so the shipped test still passes.
  assign uo_out  = ui_in + uio_in;
  assign uio_out = mix_q;
  assign uio_oe  = 8'h00;

endmodule
