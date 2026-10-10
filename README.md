![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

# Pedestrian Crossing Controller with Safe Emergency Preemption

RTL design, verification, synthesis and RTL-to-GDS implementation (Sky130) of a **demand-responsive pedestrian crossing signal controller** in Verilog.

> **Educational design.** Not suitable for real traffic infrastructure. Simulation does not prove physical correctness.

## Problem and solution

At a mid-block crossing, a fixed-timer signal stops vehicles even when nobody is waiting, while no signal is unsafe for pedestrians. This chip stops traffic **only when a pedestrian asks**, after vehicles have had a **minimum green**; a pedestrian request is **latched and acknowledged** (`ped_wait`); an **emergency request never gives an instant green** — it holds green or ends WALK early, always through the safe all-red / clearance sequence. Vehicle and pedestrian permissions can never overlap.

* Sequential logic: 6-state Moore FSM, clock prescaler + tick counter, 2-FF / 3-FF input synchronizers with edge detection, request latch.
* Inputs: `clk`, `rst_n`, `ped_req`, `emergency_req`. Outputs: vehicle R/Y/G, ped walk / clear / stop, `ped_wait`, `emergency_active`, `state_dbg[2:0]`.
* Full specification, FSM diagram, request rules and verification plan: [`docs/SPEC.md`](docs/SPEC.md).

## Repository layout

| Path | Content |
|---|---|
| `src/ped_crossing_ctrl.v` | the design (RTL) |
| `src/project.v` | Tiny Tapeout pin wrapper `tt_um_ped_crossing_ctrl` |
| `verification/tb_ped_crossing_ctrl.v` | self-checking testbench (Icarus) |
| `verification/mutation_test.sh` | injects 16 deliberate bugs; testbench must fail for each |
| `verification/tb_fullsize_smoke.v` | smoke test with the real 10 MHz timing |
| `test/` | cocotb tests of the wrapper (RTL + gate level in CI) |
| `synthesis/` | Yosys scripts (generic + Sky130 mapped) and reports |
| `docs/SPEC.md` | specification, FSM, verification plan, limitations |
| `info.yaml`, `src/config.json` | Tiny Tapeout / LibreLane flow configuration |

## Reproduce

**No local install needed:** push to GitHub; the `verify` workflow runs everything below in the cloud and uploads the logs (Actions → `verify` → Summary / Artifacts).

```bash
sudo apt install iverilog yosys verilator          # Ubuntu / WSL
make sim      # self-checking testbench  -> prints "ALL TESTS PASSED", non-zero exit on failure
make lint     # Verilator -Wall
make mutate   # bug-injection check of the testbench
make synth    # Yosys: generic + Sky130-mapped reports in synthesis/
make wave     # +vcd run and open GTKWave
cd test && pip install -r requirements.txt && make     # cocotb tests
```

## Results (all numbers come from tool runs)

| Item | Result | Where |
|---|---|---|
| Self-checking testbench (Icarus Verilog 12.0) | 400,038 checks, 0 errors | `verification/sim_log.txt` |
| Bug-injection (mutation) test | 16 / 16 injected bugs detected | `verification/mutation_results.txt` |
| cocotb tests (wrapper, RTL) | 6 / 6 pass | `test/` |
| Verilator `-Wall` lint | clean | `make lint` |
| Production-timing smoke test | start-up all-red = 20,000,000 clocks (2 s @ 10 MHz) | `verification/tb_fullsize_smoke.v` |
| Yosys (Sky130 HD, tt corner), before placement | 177 cells, 39 flip-flops, 0 latches, cell area 1796.7 µm² | `synthesis/stat_sky130.txt` |
| Yosys generic gate-level | 288 gates | `synthesis/stat_generic.txt` |
| GDS, timing, DRC/LVS | **fill in from the GitHub Actions `gds` run** | Actions → artifacts |

The synthesis area is Yosys' sum of cell areas **before** placement, clock-tree and routing; it is not a layout result. Post-layout area, timing (slack) and DRC/LVS results come from the GDS workflow and must be quoted from its reports.

## Limitations

Educational controller: no independent conflict monitor, no lamp-failure detection, no flashing-mode fallback, no certified timing values. Input push button assumed debounced; pulses shorter than one clock may be missed; reset release assumed synchronous to `clk`. Simulation covers the tested scenarios, not all input sequences (formal verification would be the next step).
