`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/10/2026 05:36:27 PM
// Design Name: 
// Module Name: tb_pe
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


module tb_pe;

    // ---- DUT signals ----
    logic                clk = 0;
    logic                reset;
    logic                acc_clear;
    logic signed [15:0]  a_in, b_in;
    logic signed [15:0]  a_out, b_out;
    logic signed [31:0]  acc_out;

    // ---- DUT ----
    pe #(.DATA_W(16), .ACC_W(32)) dut (
        .clk        (clk),
        .reset      (reset),
        .acc_clear  (acc_clear),
        .a_in       (a_in),
        .b_in       (b_in),
        .a_out      (a_out),
        .b_out      (b_out),
        .acc_out    (acc_out)
    );

    // ---- Clock: 10 ns period = 100 MHz ----
    always #5 clk = ~clk;

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    initial begin
        // -------- Init --------
        reset = 1; acc_clear = 0; a_in = 0; b_in = 0;
        repeat (2) tick;
        reset = 0;
        tick;

        // -------- TEST 1: clear accumulator --------
        // After reset, acc_out should already be 0.
        $display("[T1] acc_out after reset = %0d (expected 0)", acc_out);
        if (acc_out !== 32'sd0) $error("TEST 1 FAILED");

        // -------- TEST 2: simple MAC --------
        // a=2, b=3 -> acc = 6
        // a=4, b=5 -> acc = 6 + 20 = 26
        // a=-1, b=6 -> acc = 26 - 6 = 20
        a_in = 16'sd2; b_in = 16'sd3; tick;       // acc <= 0 + 2*3 = 6
        a_in = 16'sd4; b_in = 16'sd5; tick;       // acc <= 6 + 4*5 = 26
        a_in = -16'sd1; b_in = 16'sd6; tick;      // acc <= 26 + (-1)*6 = 20
        a_in = 0; b_in = 0; tick;                 // acc <= 20 + 0 = 20 (idle)
        $display("[T2] acc_out = %0d (expected 20)", acc_out);
        if (acc_out !== 32'sd20) $error("TEST 2 FAILED");

        // -------- TEST 3: acc_clear --------
        acc_clear = 1; a_in = 16'sd99; b_in = 16'sd99; tick;  // acc <= 0 (clear wins)
        acc_clear = 0; a_in = 0; b_in = 0; tick;
        $display("[T3] acc_out after clear = %0d (expected 0)", acc_out);
        if (acc_out !== 32'sd0) $error("TEST 3 FAILED");

        // -------- TEST 4: 4-term dot product (matches a real systolic accumulation) --------
        // Compute: 1*2 + 3*4 + 5*6 + 7*8 = 2 + 12 + 30 + 56 = 100
        a_in = 16'sd1; b_in = 16'sd2; tick;       // acc <= 0 + 2 = 2
        a_in = 16'sd3; b_in = 16'sd4; tick;       // acc <= 2 + 12 = 14
        a_in = 16'sd5; b_in = 16'sd6; tick;       // acc <= 14 + 30 = 44
        a_in = 16'sd7; b_in = 16'sd8; tick;       // acc <= 44 + 56 = 100
        a_in = 0; b_in = 0; tick;                 // acc <= 100 + 0 = 100
        $display("[T4] acc_out = %0d (expected 100)", acc_out);
        if (acc_out !== 32'sd100) $error("TEST 4 FAILED");

        // -------- TEST 5: signed math (mix of positive and negative) --------
        acc_clear = 1; tick;
        acc_clear = 0;
        // Compute: -3*4 + 5*-2 + -1*-6 = -12 + -10 + 6 = -16
        a_in = -16'sd3; b_in = 16'sd4; tick;
        a_in = 16'sd5;  b_in = -16'sd2; tick;
        a_in = -16'sd1; b_in = -16'sd6; tick;
        a_in = 0; b_in = 0; tick;
        $display("[T5] acc_out = %0d (expected -16)", acc_out);
        if (acc_out !== -32'sd16) $error("TEST 5 FAILED");

        // -------- TEST 6: pass-through delay (a_out = a_in delayed by 1 cycle) --------
        acc_clear = 1; tick;
        acc_clear = 0;
        a_in = 16'sd42; b_in = 16'sd7;
        tick;
        $display("[T6a] a_out=%0d (expected 42), b_out=%0d (expected 7)", a_out, b_out);
        if (a_out !== 16'sd42) $error("TEST 6 a_out FAILED");
        if (b_out !== 16'sd7)  $error("TEST 6 b_out FAILED");

        $display("\n=== OS-PE TESTS DONE ===");
        $finish;
    end

endmodule