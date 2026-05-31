`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/25/2026 07:58:52 PM
// Design Name: 
// Module Name: tb_tpu_top
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


module tb_tpu_top;

    parameter int N      = 16;
    parameter int DATA_W = 16;
    parameter int ACC_W  = 32;

    logic                            clk = 0;
    logic                            reset;
    logic                            acc_clear;
    logic signed [N*DATA_W-1:0]      a_in;
    logic signed [N*DATA_W-1:0]      b_in;
    logic signed [N*DATA_W-1:0]      a_out;
    logic signed [N*DATA_W-1:0]      b_out;
    logic signed [N*N*ACC_W-1:0]     acc_out;

    tpu_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .reset(reset), .acc_clear(acc_clear),
        .a_in(a_in), .b_in(b_in),
        .a_out(a_out), .b_out(b_out),
        .acc_out(acc_out)
    );

    always #5 clk = ~clk;

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    // Watchdog - if anything hangs, exit at 2 us
    initial begin
        #2000;
        $display("=== WATCHDOG TIMEOUT at %0t ===", $time);
        $finish;
    end

    initial begin
        int A       [0:N-1][0:N-1];
        int B       [0:N-1][0:N-1];
        int C_exp   [0:N-1][0:N-1];
        int errors;
        logic signed [ACC_W-1:0] got;

        $display("[%0t] TB started", $time);

        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                A[i][j] = i*N + j + 1;
                B[i][j] = i*N + j + 1;
            end

        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                C_exp[i][j] = 0;
                for (int k = 0; k < N; k++)
                    C_exp[i][j] += A[i][k] * B[k][j];
            end

        reset = 1; acc_clear = 0;
        a_in = '0; b_in = '0;
        repeat (2) tick;
        reset = 0;
        tick;
        $display("[%0t] Reset released", $time);

        acc_clear = 1; tick;
        acc_clear = 0;
        $display("[%0t] Accumulators cleared", $time);

        for (int t = 1; t <= 3*N; t++) begin
            logic signed [N*DATA_W-1:0] na;
            logic signed [N*DATA_W-1:0] nb;
            na = '0;
            nb = '0;
            for (int i = 0; i < N; i++) begin
                int idx = t - 1 - i;
                if (idx >= 0 && idx < N)
                    na[(i+1)*DATA_W-1 -: DATA_W] = A[i][idx][DATA_W-1:0];
            end
            for (int j = 0; j < N; j++) begin
                int idx = t - 1 - j;
                if (idx >= 0 && idx < N)
                    nb[(j+1)*DATA_W-1 -: DATA_W] = B[idx][j][DATA_W-1:0];
            end
            a_in = na;
            b_in = nb;
            tick;
        end
        $display("[%0t] Streaming done", $time);

        a_in = '0; b_in = '0;
        repeat (3) tick;
        $display("[%0t] Flush done - checking results", $time);

        errors = 0;
        $display("\n--- Results ---");
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                got = acc_out[(i*N+j+1)*ACC_W-1 -: ACC_W];
                $display("C[%0d][%0d] = %0d  (expected %0d) %s",
                    i, j, got, C_exp[i][j],
                    (got === C_exp[i][j]) ? "OK" : "FAIL");
                if (got !== C_exp[i][j]) errors++;
            end
        end

        if (errors == 0)
            $display("\n=== ALL %0d OUTPUTS CORRECT - %0dx%0d MATMUL VERIFIED ===", N*N, N, N);
        else
            $display("\n=== %0d ERRORS ===", errors);
        // =================================================================
        // PERFORMANCE SUMMARY
        // =================================================================
        $display("\n=== PERFORMANCE SUMMARY ===");
        $display("Configuration:");
        $display("  Array size              : %0d x %0d   (%0d PEs)", N, N, N*N);
        $display("  Datatype                : signed INT%0d  (INT%0d accumulator)", DATA_W, ACC_W);
        $display("  Simulation clock        : 100 MHz  (10 ns period)");
        $display("");
        $display("Per-matmul timing (OS systolic theory):");
        $display("  Total MACs per matmul   : %0d   (= N^3)", N*N*N);
        $display("  Cycles to first output  : %0d   (= N)", N);
        $display("  Cycles to last output   : %0d   (= 3N-1)", 3*N-1);
        $display("  Time per matmul @100MHz : %0d ns", (3*N-1)*10);
        $display("");
        $display("Throughput (steady state):");
        $display("  Peak MACs/cycle         : %0d   (all PEs active = 100%% PE util)", N*N);
        $display("  Avg MACs/cycle          : %0d   (over full matmul)", (N*N*N)/(3*N-1));
        $display("  Avg PE utilization      : %0d%%   (= N/(3N-1))", (100*N)/(3*N-1));
        $display("");
        $display("Throughput @ 100 MHz sim clock:");
        $display("  Peak MMACs/sec          : %0d", N*N*100);
        $display("  Peak GOPS               : %0d.%03d  (2 ops per MAC)",
                 (2*N*N*100)/1000, (2*N*N*100)%1000);
        $display("  Sustained MMACs/sec     : %0d", (N*N*N*100)/(3*N-1));
        $display("  Sustained GOPS          : %0d.%03d",
                 (2*N*N*N*100)/(3*N-1)/1000, ((2*N*N*N*100)/(3*N-1))%1000);
        $display("");
        $display("Observed sim time at $finish: %0t ps", $time);
        $display("============================\n");
        
        $finish;
    end

endmodule