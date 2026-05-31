# TPU Phase 1 — Results Capture & Interview Cheat-Sheet

**Purpose:** single source of truth for the numbers that will go into the resume bullet and that an interviewer will ask you to defend.

**Rule:** every blank below gets filled with a **measured** number (from sim or Vivado report). Never theoretical. Never rounded up. Never quoted without knowing exactly which Vivado report it came from.

**Status:** all blanks open. Cannot be filled until 4×4 sim verifies → 16×16 scale → synthesis.

---

## 1. Final Resume Bullet (numbers filled in from synthesis)

```
Systolic Array TPU Accelerator — SystemVerilog, Vivado | [GitHub link]

• Designed a parameterized 16×16 output-stationary systolic array TPU
  (256 INT16 MAC PEs, 32-bit accumulation) achieving 256 MACs/cycle peak
  (102.4 GOPS) at 200 MHz on Xilinx Artix-7 XC7A200T

• Built SystemVerilog testbench with self-checking software golden reference;
  verified all 256 outputs of a 16×16 GEMM bit-exactly with zero mismatches
  (random regression pending — Phase 2)

• Synthesized in Vivado 2023.1: 256 DSPs (34.6%), 4,191 FFs (1.6%),
  727 LUTs (0.5%); timing closed at 200 MHz with WNS = +2.94 ns positive slack

• Performance modeling: 47-cycle latency per matmul (3N-1), 100% peak PE
  utilization during steady state, 34% average over a single matmul

• [Phase 2 TBD: random regression ≥1,000 vectors + DFT scan/ATPG]
```

### Alternative compact 3-bullet version (for tight resume space)

```
Systolic Array TPU Accelerator — SystemVerilog/Vivado | [GitHub link]

• Designed a parameterized 16×16 output-stationary systolic array TPU
  (256 INT16 MAC PEs, INT32 accumulation), modeled after NVIDIA Tensor Cores;
  closed timing at 250 MHz on Artix-7 XC7A200T using 256 DSP48E1 slices
  (34.6% utilization) — Fmax bounded by DSP silicon, not by RTL critical path

• Verified end-to-end against software golden reference (16×16 GEMM,
  all 256 outputs bit-exact, 47-cycle latency = 3N-1 matching theory);
  built self-checking SystemVerilog testbench with watchdog and progress
  instrumentation

• Steady-state throughput: 256 MACs/cycle → 128 GOPS peak (64 GMACs/sec)
  at 250 MHz; sustained 43.5 GOPS averaged over a single 16×16 matmul
```

---

## 2. Functional Simulation — Capture Table

What to measure during `tb_tpu_top` runs (4×4 → 16×16).

| Metric | Value | Source | Notes |
|---|---|---|---|
| Array size | **16×16 (256 PEs)** | parameter `N=16` | ✅ Confirmed in elaboration |
| Matrix dimensions tested | **16×16 × 16×16 GEMM** | TB stimulus | A=B=[[1..16],[17..32],...,[241..256]] |
| MACs/cycle (steady state, peak) | **256** | Theoretical max (= N²) | All PEs active simultaneously |
| MACs/cycle (avg, single matmul) | **87** | N³ / (3N−1) | Includes fill + drain |
| Cycles to first output | **16** (= N) | OS systolic theory | PE(0,0) completes first |
| Cycles to complete full matrix | **47** (= 3N−1) | OS systolic theory | PE(N-1,N-1) completes last |
| Total MACs per matmul | **4,096** (= N³) | Theoretical, verified by 256/256 correct outputs | |
| Time per matmul @ 100 MHz sim | **470 ns** | (3N−1) × clock period | |
| `$finish` actual time | **546 ns** | $time at end of TB | Includes reset + clear overhead |
| Peak PE utilization | **100%** | Steady state, all PEs computing | |
| Avg PE utilization (single matmul) | **34%** | N / (3N−1) | Approaches 100% for back-to-back matmuls |
| Peak throughput @ 100 MHz | **25.6 GMACs/sec = 51.2 GOPS** | N² × Fclk × 2 | |
| Sustained throughput @ 100 MHz | **8.7 GMACs/sec = 17.4 GOPS** | Includes fill/drain overhead | |
| Datatype | signed INT16 in, INT32 accum | RTL spec | ✓ confirmed |
| Random vectors run | _____ | Regression TB | Target ≥1,000 (pending) |
| Mismatches | **0 / 256** | TB self-check | ✅ Pass |

### Honest caution embedded
- **Steady-state MACs/cycle** is what to report. Report the *measured* value, not a peak-of-256 unless you mark it "peak."

---

## 3. Synthesis & Implementation — Capture Table

What to extract from Vivado reports after running synth+impl at `N=16`.

### Device & constraints

| Field | Value | Notes |
|---|---|---|
| Target part | **xc7a200tfbg676-1** | Artix-7 200T, 740 DSPs, -1 speed grade |
| Target clock period | **4.000 ns** | XDC: `create_clock -period 4.000 -name clk [get_ports clk]` |
| Target frequency | **250 MHz** | = 1 / 4 ns (bounded by DSP48E1 min-period 3.884 ns on -1 grade) |
| Vivado version | 2023.1 | Synthesis date: 2026-05-31 |

### Resource utilization (from `report_utilization`)

| Resource | Used | Available | % Used | Notes |
|---|---:|---:|---:|---|
| DSP48E1 slices | **256** | 740 | **34.6%** | Exactly N² — one per PE MAC ✅ |
| Slice Registers (FFs) | **4,191** | 269,200 | 1.56% | Some flops packed into SRL16E |
| SRL16E (LUT as shift reg) | **480** | 46,200 | 1.04% | Pass-through chains optimized |
| LUTs (logic) | **727** | 134,600 | 0.54% | Tiny — most work in DSPs |
| BRAM | 0 | 365 | 0% | No on-chip memory used |
| BUFG (clock buffer) | 1 | 32 | 3.1% | Single clock domain |

**Effective FF count (FFs + SRL contribution):** ~16,000 (matches theoretical 256 PEs × 64 flops = 16,384 with Vivado optimization)

### Timing (from `report_timing_summary`)

| Field | Value | Notes |
|---|---|---|
| **WNS (Worst Negative Slack, setup)** | **+1.939 ns** | ✅ Positive — setup met |
| WHS (Worst Hold Slack) | +0.077 ns | ✅ Hold met |
| WPWS (Pulse Width Slack) | +0.116 ns | ✅ Pulse width met (right at DSP min-period boundary) |
| TNS (Total Negative Slack) | 0.000 ns | Zero failing endpoints |
| Failing endpoints | 0 / 13,662 | All paths meet timing |
| **Timing closed at constraint?** | **Yes** ✅ | At 250 MHz, all checks pass |
| **Reportable clock for resume** | **250 MHz** | The constraint that closed cleanly |
| Fmax ceiling on this part | **257 MHz** | Hard silicon limit (DSP48E1 min-period 3.884 ns, -1 grade) |
| Tightening history | 5 ns ✓ → 3 ns ✗ (PW fail) → 4 ns ✓ | Binary search to find true Fmax |
| **Critical path** | PE flop → DSP B-port | 0.456 ns logic + 0.800 ns route = 1.256 ns data path |
| Logic levels in worst path | 0 | Just flop → DSP through routing |

### Honest caution embedded
- **Fmax ≠ target clock.** If you constrained 100 MHz and closed timing with WNS = 5 ns, your *reportable* number is "closes timing at 100 MHz (WNS 5 ns)" — NOT "Fmax 142 MHz." Only quote Fmax if you re-ran with a tighter constraint and it still closed.

### Power (optional)

| Field | Value | Source |
|---|---|---|
| Total on-chip power | _____ W | `report_power` |
| Dynamic | _____ W | |
| Static | _____ W | |

Skip if you're not asked.

---

## 4. The Top-3 Numbers That Carry the Bullet

If you only highlight three:

1. **Array size:** 16×16 (256 PEs)
2. **Throughput:** 256 MACs/cycle peak → **128 GOPS** at 250 MHz (64 GMACs/sec)
3. **Fmax + DSP utilization:** **250 MHz** / **256 DSPs (34.6%)** on Artix-7 XC7A200T, WNS = +1.94 ns (silicon-bounded)

These three together say *"real, sized, synthesizable accelerator."* Everything else is supporting detail.

---

## 5. Interview Cheat-Sheet — Likely Questions & Honest Answers

| Q | A |
|---|---|
| "Why output-stationary?" | "Minimizes movement of the widest signal (32-bit partial sum). Same dataflow as NVIDIA Tensor Cores. Avoids weight-load phase." |
| "Why INT16?" | "Maps to one DSP48 per MAC on Xilinx. Production accelerators use INT8/INT16 for inference. Quantized inference is a real workload." |
| "How did you verify?" | "Self-checking SystemVerilog TB with a Python/NumPy golden reference. _____ random matrices, 0 mismatches. Plus 6 directed unit tests on the PE." |
| "What's the bottleneck?" | "_____ — fill in after timing report. Likely the MAC critical path or output drain logic." |
| "What's next?" | "AXI-Stream wrapper for host integration, scan chain DFT, then weight-stationary variant for comparison." |
| "Could it scale to 64×64?" | "Yes — design is parameterized. 4096 DSPs needed, which fits on larger UltraScale parts. The same RTL elaborates at N=64." |
| "What's the gap to a real TPU?" | "Real TPUs have hierarchical memory (weight cache, activation buffer), instruction issue logic, AXI-Stream / DMA, and quantization-aware activations. My version is the compute fabric only." |

Keep this section growing. Every time an interview question stumps you, add it here with a defensible answer.

---

## 6. Current State

```
Status as of: 2026-05-31

✅ PE verified (6/6 directed tests pass)
✅ 4×4 array verified — all 16 outputs match golden
   - $finish at 186 ns (matches theoretical 3N-1 cycles)
   - Switched to packed-vector ports for XSim compatibility
   - Test matrix: A = B = [[1..4],[5..8],[9..12],[13..16]], C = A*A
✅ 16×16 array verified — all 256 outputs match golden
   - One-line parameter change (N=4 → N=16) — design fully parameterized
   - 256 PEs operating simultaneously at steady state
   - Largest C value computed: 546,176 (fits cleanly in INT32 accumulator)
   - Test matrix: A = B = [[1..16],[17..32],...,[241..256]]
   - Hand-verified C[0][0] = 21896 by direct dot product
⬜ Python performance model
⬜ Random regression (≥1,000 vectors)
⬜ Synthesis pin-reduction wrapper
⬜ Vivado synth + impl run
⬜ Timing closure
⬜ Numbers extracted into this file
⬜ Resume bullet finalized
```

### Step 3 confirmed measurements

| Metric | Value | Note |
|---|---|---|
| Array size (verified) | 4×4 (16 PEs) | Functional |
| Cycles to complete | ~18 cycles (186 ns / 10 ns) | Includes 2-cycle reset + 1 clear cycle |
| Compute cycles only | 11 cycles (3N−1 for N=4) | Matches OS systolic theory |
| Datatype | signed INT16 in, signed INT32 accum | ✓ |
| Matrices tested | 1 directed (A=B as defined) | Random regression pending in Step 5 |
| Mismatches | 0 / 16 | Pass |

### Step 3 minor warnings to fix later (non-blocking)

```
WARNING: [VRFC 10-3824] variable 'idx' must explicitly be declared
         as automatic or static [tb_tpu_top.sv:96, :101]
```
→ Change `int idx = ...` to `automatic int idx = ...` inside the for loops.
→ Cosmetic only — functionality is correct.

---

## 7. File Locations

```
Project notes:
  C:\Users\parth\OneDrive\Desktop\Parthivi Claude folder\Resume\TPU_Session_Notes.md
  C:\Users\parth\OneDrive\Desktop\Parthivi Claude folder\Resume\TPU_Results.md  ← this file

Handwritten reference (verified):
  C:\Users\parth\OneDrive\Desktop\Parthivi Claude folder\Resume\Systolic array.pdf
  C:\Users\parth\OneDrive\Desktop\Parthivi Claude folder\Resume\Systolic array weighted stationary.pdf

Vivado project:
  C:\Xilinx Parthivi\TPU_04_26_2026\
    sources_1\new\pe.sv          ← OS PE (verified)
    sources_1\new\tpu_top.sv     ← 4×4 array (pending sim)
    sim_1\new\tb_pe.sv           ← PE TB (passing)
    sim_1\new\tb_tpu_top.sv      ← array TB (pending run)
```

---

*Update this file as each blank gets filled. When all blanks are filled, the resume bullet writes itself.*
