`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/10/2026 05:33:10 PM
// Design Name: 
// Module Name: pe
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// ============================================================
// pe.sv - Processing Element for OUTPUT-STATIONARY INT16 TPU
//   - Accumulator stays inside the PE
//   - Activations flow left?right
//   - Weights flow top?bottom
//   - Both pass-throughs are registered (1-cycle delay = systolic skew)
// ============================================================
module pe #(
    parameter int DATA_W = 16,
    parameter int ACC_W  = 32
) (
    input  logic                       clk,
    input  logic                       reset,       // synchronous, active-high (full reset)
    input  logic                       acc_clear,   // synchronous, clears accumulator only

    input  logic signed [DATA_W-1:0]   a_in,        // activation from left
    input  logic signed [DATA_W-1:0]   b_in,        // weight from above

    output logic signed [DATA_W-1:0]   a_out,       // activation to right (registered)
    output logic signed [DATA_W-1:0]   b_out,       // weight to below   (registered)
    output logic signed [ACC_W-1:0]    acc_out      // current accumulator value (registered)
);

    logic signed [ACC_W-1:0] acc_reg;

    // acc_out is just the registered acc_reg
    assign acc_out = acc_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            acc_reg <= '0;
            a_out   <= '0;
            b_out   <= '0;
        end else begin
            // ---- Pass-throughs: a moves right, b moves down (1-cycle delay) ----
            a_out <= a_in;
            b_out <= b_in;

            // ---- Accumulator ----
            // acc_clear takes priority: lets us start a fresh matmul without full reset
            if (acc_clear) acc_reg <= '0;
            else           acc_reg <= acc_reg + (a_in * b_in);
        end
    end

endmodule
