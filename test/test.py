# SPDX-License-Identifier: Apache-2.0
# cocotb tests for tt_um_ped_crossing_ctrl
#   RTL run  : short timing (FAST_SIM, 1 tick = 4 clocks) -> full behavioural tests
#   GL run   : (GATES=yes) real timing -> only the reset/start-up state is checked,
#              because full-size phases last millions of clock cycles.
# uo_out bits: 0 red, 1 yellow, 2 green, 3 walk, 4 clear, 5 stop, 6 wait, 7 emergency_active
# uio_out[2:0] = state_dbg: 0 ALLRED2, 1 GREEN, 2 YELLOW, 3 ALLRED1, 4 WALK, 5 CLEAR

import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

GL = os.environ.get("GATES") == "yes"
DIV = 4
RED, YEL, GRN, WALK, CLR, STOP, WAIT, EMG = (1 << i for i in range(8))
ALLRED2, GREEN, YELLOW, ALLRED1, WALKING, CLEARING = range(6)


def state(dut):
    return int(dut.uio_out.value) & 7


def outs(dut):
    return int(dut.uo_out.value)


def check_safe(dut):
    o = outs(dut)
    assert not ((o & (GRN | YEL)) and (o & (WALK | CLR))), f"CONFLICT uo_out={o:#04x}"
    assert bin(o & (RED | YEL | GRN)).count("1") == 1, f"vehicle lamps not one-hot {o:#04x}"
    assert bin(o & (WALK | CLR | STOP)).count("1") == 1, f"ped signals not one-hot {o:#04x}"


async def wait_state(dut, s, max_cycles):
    for _ in range(max_cycles):
        if state(dut) == s:
            return
        await ClockCycles(dut.clk, 1)
        check_safe(dut)
    raise AssertionError(f"timeout waiting for state {s}, now {state(dut)}")


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1


@cocotb.test()
async def test_reset_state(dut):
    """After reset: all vehicles red, pedestrians stop, no wait / emergency, FSM in ALLRED2."""
    await reset(dut)
    await ClockCycles(dut.clk, 3)
    assert outs(dut) == (RED | STOP), f"reset outputs {outs(dut):#04x}"
    assert state(dut) == ALLRED2
    assert int(dut.uio_oe.value) == 0x07


if not GL:

    @cocotb.test()
    async def test_startup_goes_green(dut):
        await reset(dut)
        await wait_state(dut, GREEN, 2 * DIV + 4)
        assert outs(dut) == (GRN | STOP)

    @cocotb.test()
    async def test_pedestrian_cycle(dut):
        await reset(dut)
        await wait_state(dut, GREEN, 30)
        await ClockCycles(dut.clk, 20 * DIV + 3)          # satisfy minimum green
        dut.ui_in.value = 0b01                            # press button
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 2)
        assert outs(dut) & WAIT, "ped_wait must light after the press"
        await wait_state(dut, YELLOW, 10)
        assert outs(dut) == (YEL | STOP | WAIT)
        await wait_state(dut, ALLRED1, 3 * DIV + 4)
        await wait_state(dut, WALKING, 2 * DIV + 4)
        assert outs(dut) == (RED | WALK), "ped_wait must clear when WALK starts"
        await wait_state(dut, CLEARING, 7 * DIV + 4)
        assert outs(dut) == (RED | CLR)
        await wait_state(dut, ALLRED2, 10 * DIV + 4)
        await wait_state(dut, GREEN, 2 * DIV + 4)
        assert outs(dut) == (GRN | STOP)

    @cocotb.test()
    async def test_emergency_holds_green_and_keeps_request(dut):
        await reset(dut)
        await wait_state(dut, GREEN, 30)
        await ClockCycles(dut.clk, 20 * DIV + 3)
        dut.ui_in.value = 0b11                            # ped + emergency together
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0b10                            # emergency stays asserted
        for _ in range(30 * DIV):
            await ClockCycles(dut.clk, 1)
            assert state(dut) == GREEN, "emergency must hold GREEN, never skip the safe sequence"
        assert outs(dut) & EMG and outs(dut) & WAIT
        dut.ui_in.value = 0                               # emergency over
        await wait_state(dut, YELLOW, 10)                 # kept request is now served
        await wait_state(dut, GREEN, 60 * DIV)

    @cocotb.test()
    async def test_emergency_cuts_walk_but_not_clearance(dut):
        await reset(dut)
        await wait_state(dut, GREEN, 30)
        await ClockCycles(dut.clk, 20 * DIV + 3)
        dut.ui_in.value = 0b01
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0
        await wait_state(dut, WALKING, 40 * DIV)
        await ClockCycles(dut.clk, 3)
        dut.ui_in.value = 0b10
        await ClockCycles(dut.clk, 5)
        assert state(dut) == CLEARING, "WALK must end in CLEAR when emergency arrives"
        dut.ui_in.value = 0
        await wait_state(dut, ALLRED2, 10 * DIV + 4)
        await wait_state(dut, GREEN, 2 * DIV + 4)

    @cocotb.test()
    async def test_reset_mid_cycle(dut):
        await reset(dut)
        await wait_state(dut, GREEN, 30)
        await ClockCycles(dut.clk, 20 * DIV + 3)
        dut.ui_in.value = 0b01
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0
        await wait_state(dut, ALLRED1, 40 * DIV)
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 2)
        assert outs(dut) == (RED | STOP), "reset must force all-red and clear ped_wait"
        dut.rst_n.value = 1
        await wait_state(dut, GREEN, 4 * DIV)
        await ClockCycles(dut.clk, 30 * DIV)
        assert state(dut) == GREEN, "no stale request after reset"
