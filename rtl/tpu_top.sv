`timescale 1ns/1ps

// ============================================================
// tpu_top.sv - 4x4 Output-Stationary Systolic Array (packed I/O)
// ============================================================
module tpu_top #(
    parameter int N      = 16,
    parameter int DATA_W = 16,
    parameter int ACC_W  = 32
) (
    input  logic                            clk,
    input  logic                            reset,
    input  logic                            acc_clear,

    input  logic signed [N*DATA_W-1:0]      a_in,
    input  logic signed [N*DATA_W-1:0]      b_in,
    output logic signed [N*DATA_W-1:0]      a_out,
    output logic signed [N*DATA_W-1:0]      b_out,
    output logic signed [N*N*ACC_W-1:0]     acc_out
);

    logic signed [DATA_W-1:0] a_in_arr   [0:N-1];
    logic signed [DATA_W-1:0] b_in_arr   [0:N-1];
    logic signed [DATA_W-1:0] a_out_arr  [0:N-1];
    logic signed [DATA_W-1:0] b_out_arr  [0:N-1];
    logic signed [ACC_W-1:0]  acc_arr    [0:N-1][0:N-1];

    logic signed [DATA_W-1:0] a_wire [0:N-1][0:N];
    logic signed [DATA_W-1:0] b_wire [0:N][0:N-1];

    genvar i, j;

    generate
        for (i = 0; i < N; i++) begin : g_unpack_in
            assign a_in_arr[i] = a_in[(i+1)*DATA_W-1 -: DATA_W];
            assign b_in_arr[i] = b_in[(i+1)*DATA_W-1 -: DATA_W];
        end
        for (i = 0; i < N; i++) begin : g_left_edge
            assign a_wire[i][0] = a_in_arr[i];
        end
        for (j = 0; j < N; j++) begin : g_top_edge
            assign b_wire[0][j] = b_in_arr[j];
        end
    endgenerate

    generate
        for (i = 0; i < N; i++) begin : g_row
            for (j = 0; j < N; j++) begin : g_col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk       (clk),
                    .reset     (reset),
                    .acc_clear (acc_clear),
                    .a_in      (a_wire[i][j]),
                    .b_in      (b_wire[i][j]),
                    .a_out     (a_wire[i][j+1]),
                    .b_out     (b_wire[i+1][j]),
                    .acc_out   (acc_arr[i][j])
                );
            end
        end
    endgenerate

    generate
        for (i = 0; i < N; i++) begin : g_right_edge
            assign a_out_arr[i] = a_wire[i][N];
        end
        for (j = 0; j < N; j++) begin : g_bottom_edge
            assign b_out_arr[j] = b_wire[N][j];
        end
        for (i = 0; i < N; i++) begin : g_pack_ab_out
            assign a_out[(i+1)*DATA_W-1 -: DATA_W] = a_out_arr[i];
            assign b_out[(i+1)*DATA_W-1 -: DATA_W] = b_out_arr[i];
        end
        for (i = 0; i < N; i++) begin : g_pack_acc
            for (j = 0; j < N; j++) begin : g_pack_acc_inner
                assign acc_out[(i*N+j+1)*ACC_W-1 -: ACC_W] = acc_arr[i][j];
            end
        end
    endgenerate

endmodule