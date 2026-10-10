<!---
Datasheet text for Tiny Tapeout.
-->

## How it works

A demand-responsive pedestrian crossing controller (educational design). A finite state machine sequences the vehicle lamps (red / yellow / green) and the pedestrian signals (walk / clear / stop). A prescaler divides the 10 MHz clock to a 1 s tick, and a tick counter times each phase.

* The push button (`ui[0]`) is synchronized, edge-detected and **latched**. `uo[6]` (`ped_wait`) lights until WALK starts.
* Vehicles always get a minimum green of 20 s before the request is served: YELLOW (3 s), all-red (2 s), WALK (7 s), CLEAR (10 s), all-red (2 s), GREEN.
* The emergency input (`ui[1]`) never gives an immediate green. In GREEN it holds green (a pending request is kept); in WALK it ends the walk early but the clearance phase is still shown.
* Vehicle go and pedestrian permission can never be on at the same time.
* After reset the controller shows all-red for 2 s, then GREEN.

Output pins: `uo[0]` red, `uo[1]` yellow, `uo[2]` green, `uo[3]` walk, `uo[4]` clear, `uo[5]` stop, `uo[6]` wait, `uo[7]` emergency active. `uio[2:0]` is the FSM state (debug output): 0 all-red(2), 1 green, 2 yellow, 3 all-red(1), 4 walk, 5 clear.

Full specification: `docs/SPEC.md`.

## How to test

Drive a 10 MHz clock, pulse `rst_n` low, then:
1. Wait about 2 s → `uo[2]` (green) goes high.
2. After 20 s of green, press `ui[0]` → `uo[6]` lights, then yellow, all-red, walk, clear, all-red, green.
3. Hold `ui[1]` high during green with a pending request → green is held until it is released.

Simulation (short timing): `make sim` in the repository root, and `cd test && make` for the cocotb tests.

## External hardware

None required. LEDs on `uo[7:0]` show the signals. A debounced push button on `ui[0]` and a switch on `ui[1]`.
