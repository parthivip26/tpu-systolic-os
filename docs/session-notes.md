# TPU Project — Full Session Notes

**Project:** 4×4 INT16 Output-Stationary Systolic Array TPU
**Target roles:** RTL / FPGA / DFT + AI
**Status as of last sync:** Step 2 complete (PE verified), Step 3 in progress (4×4 array)

---

## Table of Contents

1. [Project Overview & Resume Goal](#project-overview)
2. [Locked Architecture Spec](#locked-spec)
3. [Roadmap & Status](#roadmap)
4. [Step 1 — Architecture Decisions](#step1)
5. [Background Concepts](#concepts)
   - Systolic Arrays
   - Three Dataflows (WS / OS / IS)
   - Inference vs Training
   - Signed vs Unsigned Math
   - INT16 Representation
   - Flip-Flops & Registered Outputs
   - NBA Semantics & Simulator Scheduling
6. [Step 2 — Processing Element (PE)](#step2)
   - `pe.sv` (Output-Stationary)
   - Line-by-line Walkthrough
   - `tb_pe.sv`
   - TB Walkthrough
   - Why `tick`
   - Simulation Results
7. [Step 3 — 4×4 Array (`tpu_top.sv`)](#step3)
   - `tpu_top.sv`
   - `tb_tpu_top.sv`
   - Wiring Rules
   - Vivado Pin Count Issue
8. [Verification of Handwritten Notes](#notes)
9. [Resume Defense (50-word interview answer)](#defense)
10. [Next Steps](#next)

---

<a id="project-overview"></a>
## 1. Project Overview & Resume Goal

Build a parameterized 4×4 INT16 systolic array TPU in SystemVerilog, verify it in Vivado XSim, synthesize for Artix-7, and produce a resume bullet block with real numbers (GOPS, LUT/DSP utilization, Fmax).

**Resume bullet skeleton (will fill in with real numbers at Step 8):**

> **Systolic Array TPU Accelerator** — Verilog/SystemVerilog, INT16 | [GitHub]
> - Designed a parameterized 4×4 output-stationary systolic array TPU performing INT16 matrix multiplication, matching the NVIDIA Tensor Core dataflow
> - Implemented MAC pipeline with registered pass-throughs, achieving [X] GOPS at [Y] MHz on Artix-7
> - Verified correctness with self-checking SystemVerilog testbench against NumPy golden reference across [N] random matrices
> - Synthesized in Vivado; utilized [X] LUTs / [Y] DSPs / [Z] flops
> - [DFT bullet] Added scan chain insertion and generated ATPG patterns achieving [X]% stuck-at fault coverage

---

<a id="locked-spec"></a>
## 2. Locked Architecture Spec

```
N            = 4
DATAFLOW     = OUTPUT-STATIONARY
DATA_W       = 16  (INT16, signed)
ACC_W        = 32  (signed)
LANG         = SystemVerilog
SIM          = Vivado XSim
SYNTH        = Vivado (Artix-7 target)
RESET        = synchronous, active-high
INTERFACE    = testbench-only (no AXI yet)
DEMO         = 4×4 matmul → MNIST FC layer
REFERENCE    = NVIDIA Tensor Cores
```

---

<a id="roadmap"></a>
## 3. Roadmap & Status

| Step | Deliverable | Status |
|------|---|---|
| 1 — Architecture spec | Final spec locked | ✅ Done |
| 2 — PE module + TB | `pe.sv` + `tb_pe.sv` verified | ✅ Done — all 6 tests pass |
| 3 — 4×4 array top + TB | `tpu_top.sv` + `tb_tpu_top.sv` | 🟡 In progress |
| 4 — Python golden model | `golden.py` + hex generator | ⚪ Not started |
| 5 — Randomized regression TB | Random stress test, hundreds of matrices | ⚪ Not started |
| 6 — Vivado synthesis (real numbers) | Util/Fmax reports | ⚪ Not started |
| 7 — DFT add-on (scan + ATPG) | Scan chain + fault coverage | ⚪ Not started |
| 8 — Resume bullets with real numbers | Final 5-line bullet block | ⚪ Not started |

---

<a id="step1"></a>
## 4. Step 1 — Architecture Decisions (with defenses)

### Why 4×4
- Debuggable by hand (16 PEs traceable)
- Big enough to sound real on resume
- Parameterized — bump to 8×8 later by changing one line
- Fits on cheapest FPGAs (Basys3)

### Why Output-Stationary (final pick after evaluating both)
- Minimizes movement of widest signal (32-bit partial sum)
- No weight-load phase
- Matches NVIDIA Tensor Cores (AI-friendly reference for GPU/accelerator roles)
- Slightly fewer total cycles for single matmul (10 vs 14 for WS)

### Why INT16 signed
- Fits one DSP48 slice per MAC (Xilinx hard multiplier)
- Real production accelerators use INT8/INT16 (TPU, Coral, Hailo)
- "INT16 quantized inference" is a recognized phrase
- Must be **signed** — without it, negative weights become huge positives due to two's-complement interpretation

### Why 32-bit accumulator
- INT16 × INT16 → 32-bit product (fits cleanly)
- Sum of 4 such products bounded well under 2³² for N=4
- DSP48 native width

### Why Sim-only first (Vivado XSim)
- Don't let synthesis time block design iteration
- Synth/Impl saved for Step 6 (real numbers for resume)
- Sim runs in seconds vs minutes for synth

### Why SystemVerilog (not Verilog-2001)
- `logic` type removes reg/wire confusion
- `always_ff` catches accidental latches
- Industry uses SV; Verilog-2001 is legacy
- Cleaner TBs, supports SVA for DFT bullet later

### Why Synchronous, Active-High Reset
- Matches user's initial draft
- FPGA-friendly (Xilinx prefers sync reset)
- Locked for the whole design

---

<a id="concepts"></a>
## 5. Background Concepts

### What is a Systolic Array?
A 2D mesh of processing elements (PEs) where data flows through neighbors in synchronized waves. Like a heart pumping data through a vascular network — hence "systolic." Each PE does a small repeated operation (here: multiply-accumulate). The whole array completes a matrix multiply in O(N) cycles instead of O(N³) sequential.

### Three Dataflows

| Dataflow | What stays in PE | What moves | Famous chip |
|---|---|---|---|
| **Weight-Stationary (WS)** | Weight | Activations + Partial sums | Google TPU v1 |
| **Output-Stationary (OS)** | Accumulator | Activations + Weights | NVIDIA Tensor Cores |
| **Input-Stationary (IS)** | Activation | Weights + Partial sums | Rare |

**Rule:** keep stationary whatever you reuse most. Move whatever changes most. Data movement dominates energy in real chips; multiplies are cheap.

### Inference vs Training

| | Training | Inference |
|---|---|---|
| Goal | Learn the weights | Use the weights |
| Weights | Change every step | **Fixed** |
| Frequency | Once per model | Billions per day |
| Latency | Hours–weeks OK | Milliseconds |
| Precision | Float32 / bfloat16 | INT8 / INT16 |
| Best dataflow | OS (no weight reuse) | WS (high weight reuse) |

For this project: we're doing **inference** (MNIST classifier) but built **OS** for breadth/AI-friendliness. Both are defensible.

### Signed vs Unsigned Math

INT16 `-5` is stored as `0xFFFB` (two's-complement). Same bits, unsigned interpretation = `65531`.

```systemverilog
logic signed [15:0] w, a;    // (-5) × 3 = -15  ✓
logic        [15:0] w, a;    // 65531 × 3 = 196593  ✗ (treats bits as unsigned)
```

**Every** wire, register, port, and operand in the signed path needs the `signed` keyword. Mix one unsigned in and the whole expression converts to unsigned.

### INT16 Representation
- 16 bits per number, signed two's-complement
- Range: −32,768 to +32,767
- One `a_in` port = 16 parallel wires carrying one matrix element
- A 4×4 matrix = 16 elements × 16 bits = 256 bits total

### Flip-Flops & Registered Outputs

A flip-flop captures its input on the rising clock edge and holds it until the next edge. "Registered output" means the output only changes at clock edges, not when the input changes.

**Why register PE outputs:**
1. Real wires have settling time — registers wait for stable values
2. Makes timing predictable (max combinational depth = one PE, not all 4)
3. Creates the 1-cycle hop between PEs that the systolic wavefront depends on

Without registered pass-throughs, an activation would ripple through all 4 PEs in a row in a single cycle and the wavefront concept collapses.

### NBA Semantics & Simulator Scheduling

At every simulation timestep, the scheduler processes:
1. **Active region** — RHS evaluated, blocking assigns committed, `$display` schedules
2. **NBA region** — non-blocking (`<=`) assigns committed to LHS
3. **Postponed region** — `$monitor`, end-of-step reads

The TB's `@(posedge clk)` returns in the active region — BEFORE the NBA region. So reads done immediately after a `@(posedge clk)` see PRE-edge values. The `#1` after the edge advances to a new timestep where NBA updates have already drained, so reads see POST-edge values.

This is purely a simulator artifact, not a hardware behavior. In silicon, after clk-to-Q delay (~ns), the flop output is the new value.

---

<a id="step2"></a>
## 6. Step 2 — Processing Element (PE)

### `pe.sv` (Output-Stationary)

```systemverilog
// ============================================================
// pe.sv — Processing Element for OUTPUT-STATIONARY INT16 TPU
//   - Accumulator stays inside the PE
//   - Activations flow left -> right
//   - Weights flow top -> bottom
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
```

### Line-by-line walkthrough

| Line | What it does |
|---|---|
| `module pe #(...)` | Parameterized module — DATA_W, ACC_W set at instantiation |
| `input ... signed [DATA_W-1:0] a_in` | Signed 16-bit activation from left neighbor |
| `input ... signed [DATA_W-1:0] b_in` | Signed 16-bit weight from above neighbor |
| `output ... acc_out` | Combinational tap into the internal accumulator |
| `logic signed [ACC_W-1:0] acc_reg` | 32 signed flip-flops — the heart of OS |
| `assign acc_out = acc_reg` | Wire — `acc_out` mirrors `acc_reg` instantly |
| `always_ff @(posedge clk)` | All flip-flop updates fire on rising clock edge |
| `if (reset) ...` | Synchronous reset clears all three flops to 0 |
| `a_out <= a_in` | Registered pass-through right (creates 1-cycle skew) |
| `b_out <= b_in` | Registered pass-through down (creates 1-cycle skew) |
| `if (acc_clear) acc_reg <= '0` | Synchronous clear on accumulator (priority over MAC) |
| `else acc_reg <= acc_reg + (a_in * b_in)` | The MAC: signed multiply + accumulate |

### Hardware inferred per PE
- 16 flops for `a_out`
- 16 flops for `b_out`
- 32 flops for `acc_reg` (with sync clear)
- 1 DSP48 slice (multiply + add fused)
- **Total: ~64 flops + 1 DSP per PE**

### `tb_pe.sv` — Testbench

```systemverilog
`timescale 1ns/1ps

module tb_pe;

    logic                clk = 0;
    logic                reset;
    logic                acc_clear;
    logic signed [15:0]  a_in, b_in;
    logic signed [15:0]  a_out, b_out;
    logic signed [31:0]  acc_out;

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

    always #5 clk = ~clk;   // 100 MHz

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    initial begin
        reset = 1; acc_clear = 0; a_in = 0; b_in = 0;
        repeat (2) tick;
        reset = 0;
        tick;

        // TEST 1: reset clears acc_reg
        $display("[T1] acc_out after reset = %0d (expected 0)", acc_out);
        if (acc_out !== 32'sd0) $error("TEST 1 FAILED");

        // TEST 2: simple MAC
        a_in = 16'sd2; b_in = 16'sd3; tick;
        a_in = 16'sd4; b_in = 16'sd5; tick;
        a_in = -16'sd1; b_in = 16'sd6; tick;
        a_in = 0; b_in = 0; tick;
        $display("[T2] acc_out = %0d (expected 20)", acc_out);
        if (acc_out !== 32'sd20) $error("TEST 2 FAILED");

        // TEST 3: acc_clear priority
        acc_clear = 1; a_in = 16'sd99; b_in = 16'sd99; tick;
        acc_clear = 0; a_in = 0; b_in = 0; tick;
        $display("[T3] acc_out after clear = %0d (expected 0)", acc_out);
        if (acc_out !== 32'sd0) $error("TEST 3 FAILED");

        // TEST 4: 4-term dot product
        a_in = 16'sd1; b_in = 16'sd2; tick;
        a_in = 16'sd3; b_in = 16'sd4; tick;
        a_in = 16'sd5; b_in = 16'sd6; tick;
        a_in = 16'sd7; b_in = 16'sd8; tick;
        a_in = 0; b_in = 0; tick;
        $display("[T4] acc_out = %0d (expected 100)", acc_out);
        if (acc_out !== 32'sd100) $error("TEST 4 FAILED");

        // TEST 5: signed math coverage
        acc_clear = 1; tick;
        acc_clear = 0;
        a_in = -16'sd3; b_in = 16'sd4; tick;
        a_in = 16'sd5;  b_in = -16'sd2; tick;
        a_in = -16'sd1; b_in = -16'sd6; tick;
        a_in = 0; b_in = 0; tick;
        $display("[T5] acc_out = %0d (expected -16)", acc_out);
        if (acc_out !== -32'sd16) $error("TEST 5 FAILED");

        // TEST 6: pass-through 1-cycle delay
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
```

### What each test verifies

| Test | Verifies |
|---|---|
| T1 | Synchronous reset clears `acc_reg` to 0 |
| T2 | Basic MAC accumulation across multiple cycles (with one negative operand) |
| T3 | `acc_clear` has priority over the MAC path |
| T4 | Realistic 4-term dot product (the systolic core use case) |
| T5 | Full signed coverage — all sign combinations of multiplier |
| T6 | Pass-through registers have correct 1-cycle delay (systolic skew) |

### Why `tick`?

```systemverilog
task automatic tick;
    @(posedge clk);    // sync to rising edge
    #1;                // 1ns past edge — let NBA updates drain
endtask
```

- `@(posedge clk)` advances simulation to the next rising edge, putting us in the active region of that timestep
- `#1` advances past the NBA region so the TB reads see post-edge values
- Without `#1`, TB samples in the active region and reads stale (pre-edge) values → off-by-one bugs
- Wrapping in a task = cleaner test stimulus, one place to change cadence

### Simulation Results — All 6 Tests Pass ✅

```
[T1] acc_out after reset = 0 (expected 0)
[T2] acc_out = 20 (expected 20)
[T3] acc_out after clear = 0 (expected 0)
[T4] acc_out = 100 (expected 100)
[T5] acc_out = -16 (expected -16)
[T6a] a_out=42 (expected 42), b_out=7 (expected 7)

=== OS-PE TESTS DONE ===
$finish called at time : 206 ns
```

Clean compile, clean elaborate, no warnings. Simulation completed in 206 ns.

---

<a id="step3"></a>
## 7. Step 3 — 4×4 Array (`tpu_top.sv`)

### Wiring rules
1. `PE(i,j).a_in` = `PE(i,j-1).a_out` (or top-level `a_in[i]` for j=0)
2. `PE(i,j).b_in` = `PE(i-1,j).b_out` (or top-level `b_in[j]` for i=0)
3. `PE(i,j).acc_out` exposed as `acc_out[i][j]`

### `tpu_top.sv`

```systemverilog
// ============================================================
// tpu_top.sv — 4x4 Output-Stationary Systolic Array
//   Instantiates 16 PEs in a mesh.
//   Activations enter from LEFT edge, weights from TOP edge.
//   Each PE's accumulator is exposed.
// ============================================================
module tpu_top #(
    parameter int N      = 4,
    parameter int DATA_W = 16,
    parameter int ACC_W  = 32
) (
    input  logic                       clk,
    input  logic                       reset,
    input  logic                       acc_clear,

    input  logic signed [DATA_W-1:0]   a_in    [0:N-1],   // left edge, one per row
    input  logic signed [DATA_W-1:0]   b_in    [0:N-1],   // top edge,  one per col

    output logic signed [DATA_W-1:0]   a_out   [0:N-1],   // right edge spill
    output logic signed [DATA_W-1:0]   b_out   [0:N-1],   // bottom edge spill

    output logic signed [ACC_W-1:0]    acc_out [0:N-1][0:N-1]
);

    logic signed [DATA_W-1:0] a_wire [0:N-1][0:N];
    logic signed [DATA_W-1:0] b_wire [0:N][0:N-1];

    genvar i, j;

    // Left edge: top-level a_in feeds column 0
    generate
        for (i = 0; i < N; i++) begin : gen_left_edge
            assign a_wire[i][0] = a_in[i];
        end
    endgenerate

    // Top edge: top-level b_in feeds row 0
    generate
        for (j = 0; j < N; j++) begin : gen_top_edge
            assign b_wire[0][j] = b_in[j];
        end
    endgenerate

    // 16 PE instances
    generate
        for (i = 0; i < N; i++) begin : gen_row
            for (j = 0; j < N; j++) begin : gen_col
                pe #(
                    .DATA_W (DATA_W),
                    .ACC_W  (ACC_W)
                ) u_pe (
                    .clk       (clk),
                    .reset     (reset),
                    .acc_clear (acc_clear),
                    .a_in      (a_wire[i][j]),
                    .b_in      (b_wire[i][j]),
                    .a_out     (a_wire[i][j+1]),
                    .b_out     (b_wire[i+1][j]),
                    .acc_out   (acc_out[i][j])
                );
            end
        end
    endgenerate

    // Right edge & bottom edge spill
    generate
        for (i = 0; i < N; i++) begin : gen_right_edge
            assign a_out[i] = a_wire[i][N];
        end
        for (j = 0; j < N; j++) begin : gen_bottom_edge
            assign b_out[j] = b_wire[N][j];
        end
    endgenerate

endmodule
```

### `tb_tpu_top.sv`

```systemverilog
`timescale 1ns/1ps

module tb_tpu_top;

    parameter int N      = 4;
    parameter int DATA_W = 16;
    parameter int ACC_W  = 32;

    logic                       clk = 0;
    logic                       reset;
    logic                       acc_clear;
    logic signed [DATA_W-1:0]   a_in    [0:N-1];
    logic signed [DATA_W-1:0]   b_in    [0:N-1];
    logic signed [DATA_W-1:0]   a_out   [0:N-1];
    logic signed [DATA_W-1:0]   b_out   [0:N-1];
    logic signed [ACC_W-1:0]    acc_out [0:N-1][0:N-1];

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

    int A [0:N-1][0:N-1];
    int B [0:N-1][0:N-1];
    int C_expected [0:N-1][0:N-1];

    initial begin
        int errors;
        int k;

        // Build A = B = [[1..4],[5..8],[9..12],[13..16]]
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                A[i][j] = i*N + j + 1;
                B[i][j] = i*N + j + 1;
            end

        // Golden C = A * B
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                C_expected[i][j] = 0;
                for (k = 0; k < N; k++)
                    C_expected[i][j] += A[i][k] * B[k][j];
            end

        reset = 1; acc_clear = 0;
        for (int i = 0; i < N; i++) begin
            a_in[i] = 0;
            b_in[i] = 0;
        end
        repeat (2) tick;
        reset = 0;
        tick;

        acc_clear = 1; tick;
        acc_clear = 0;

        // Stream A from left, B from top with skew
        for (int t = 1; t <= 3*N; t++) begin
            for (int i = 0; i < N; i++) begin
                int idx = t - 1 - i;
                if (idx >= 0 && idx < N) a_in[i] = A[i][idx];
                else                     a_in[i] = 0;
            end
            for (int j = 0; j < N; j++) begin
                int idx = t - 1 - j;
                if (idx >= 0 && idx < N) b_in[j] = B[idx][j];
                else                     b_in[j] = 0;
            end
            tick;
        end

        for (int i = 0; i < N; i++) begin
            a_in[i] = 0;
            b_in[i] = 0;
        end
        repeat (3) tick;

        errors = 0;
        $display("\n--- Results ---");
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                $display("C[%0d][%0d] = %0d  (expected %0d) %s",
                    i, j, acc_out[i][j], C_expected[i][j],
                    (acc_out[i][j] === C_expected[i][j]) ? "OK" : "FAIL");
                if (acc_out[i][j] !== C_expected[i][j]) begin
                    $error("MISMATCH at C[%0d][%0d]", i, j);
                    errors++;
                end
            end

        if (errors == 0)
            $display("\n=== ALL 16 OUTPUTS CORRECT — 4x4 MATMUL VERIFIED ===");
        else
            $display("\n=== %0d ERRORS ===", errors);

        $finish;
    end

endmodule
```

### Test case (built into TB as golden)
```
A = B = [[ 1,  2,  3,  4],
         [ 5,  6,  7,  8],
         [ 9, 10, 11, 12],
         [13, 14, 15, 16]]

Expected C = A × A:
        [[ 90, 100, 110, 120],
         [202, 228, 254, 280],
         [314, 356, 398, 440],
         [426, 484, 542, 600]]
```

### Vivado Pin Count "Error" (Implementation phase)

When Implementation was accidentally run, it failed with:
```
[Place 30-415] IO Placement failed due to overutilization.
This design contains 771 I/O ports while target device 7k70t has 300 user I/O.
```

**This is expected and not a real problem.** Counting the pins:

| Port | Pins |
|---|---|
| clk + reset + acc_clear | 3 |
| a_in[0:3] × 16 | 64 |
| b_in[0:3] × 16 | 64 |
| a_out[0:3] × 16 | 64 |
| b_out[0:3] × 16 | 64 |
| **acc_out[0:3][0:3] × 32** | **512** |
| **Total** | **771** |

The `acc_out` 2D array alone uses 512 pins because we expose every accumulator for TB visibility. No real chip would do this — production would add an AXI interface or serializer.

**For Step 3 we only run Behavioral Simulation (XSim) — pin count doesn't matter.**
**For Step 6 (synthesis numbers), we either stop after synth or add a wrapper to mux outputs.**

---

<a id="notes"></a>
## 8. Verification of Handwritten Notes

Both PDFs in `Resume/` folder:

### `Systolic array.pdf` — Output-Stationary, 10 cycles
✅ All 10 cycles verified correct. Every PE expression matches expected partial sums. Wavefront pattern (1→3→6→10→12→12→10→6→3→1 active PEs) is exactly right. Total = 64 multiplies (= N³).

### `Systolic array weighted stationary.pdf` — Weight-Stationary, 11 cycles
✅ All 11 cycles verified correct. Setup correctly shows weights pre-loaded; activations entered in column-major order with proper skew. First output at T=4 (= N), last at T=11 (= 3N−1 in registered-output convention). Output emergence triangle matches theory.

**One minor flag:** the "Multiply = T" counter in both PDFs counts cycle index, not actual multiplications. Real multiply count per cycle = number of active PEs (the wavefront). Should be relabeled "active PEs" instead.

---

<a id="defense"></a>
## 9. Resume Defense (50-word interview answer)

> *"I built output-stationary because it minimizes movement of the widest data signal — the 32-bit partial sum stays inside each PE. This is the same dataflow NVIDIA Tensor Cores use in modern GPUs, and it avoids any weight-load phase entirely."*

**If asked why not WS:**
> *"Weight-stationary would be optimal for inference with batched inputs because weights are loaded once and reused. But for general matmul and training, output-stationary minimizes total data movement since the partial sum (the widest signal) never leaves the PE. NVIDIA Tensor Cores made the same choice for the same reason."*

---

<a id="next"></a>
## 10. Next Steps (after Step 3 verifies)

| Step | Plan |
|---|---|
| **4** — Python golden | NumPy-based reference that generates random INT16 matrices and computes expected C. Outputs hex files for Vivado to load. |
| **5** — Randomized regression | TB that loads hundreds of random matrices, runs through DUT, compares to golden. Edge cases: max/min INT16, all-zero rows, all-negative weights. |
| **6** — Vivado synthesis | Stop after synth (skip implementation due to pin issue). Capture LUT/DSP/flop utilization and estimated Fmax. Numbers go into resume bullet. |
| **7** — DFT add-on | Scan chain insertion via Vivado, generate ATPG patterns, measure stuck-at fault coverage. Adds the DFT bullet. |
| **8** — Final resume bullets | Replace [X]/[Y]/[Z] placeholders with real numbers from Step 6 & 7. |

---

## Files in this Project

```
C:\Users\parth\OneDrive\Desktop\Parthivi Claude folder\Resume\
├── Systolic array.pdf                      ← OS handwritten notes (verified)
├── Systolic array weighted stationary.pdf  ← WS handwritten notes (verified)
└── TPU_Session_Notes.md                    ← this file

C:\Xilinx Parthivi\TPU_04_26_2026\
├── TPU_04_26_2026.srcs\
│   ├── sources_1\new\
│   │   ├── pe.sv          ← OS Processing Element
│   │   └── tpu_top.sv     ← 4×4 array (Step 3 — pending verification)
│   └── sim_1\new\
│       ├── tb_pe.sv       ← PE testbench (verified)
│       └── tb_tpu_top.sv  ← Array testbench (pending run)
```

---

## Open Questions / TODOs

- [ ] Run `tb_tpu_top` in Vivado Behavioral Simulation
- [ ] Verify all 16 `C[i][j]` outputs match golden
- [ ] (Optional) Add waveform dump to inspect skew visually
- [ ] Decide whether to wrap `tpu_top` for synthesis pin reduction in Step 6
- [ ] Plan MNIST FC layer demo for Step 4

---

*Document generated from collaborative design session. Update as project progresses.*
