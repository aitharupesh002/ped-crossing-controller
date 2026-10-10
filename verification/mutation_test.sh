#!/bin/bash
# Mutation test: inject deliberate bugs into a copy of the RTL and confirm the
# testbench FAILS for each one. A surviving mutant means a hole in the testbench.
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
run() {  # name  sed-expression
  sed -e "$2" src/ped_crossing_ctrl.v > $TMP/$1.v
  if cmp -s $TMP/$1.v src/ped_crossing_ctrl.v; then echo "$1: MUTATION DID NOT APPLY"; return; fi
  iverilog -g2012 -o $TMP/$1.vvp $TMP/$1.v verification/tb_ped_crossing_ctrl.v 2>/dev/null
  out=$(timeout 120 vvp $TMP/$1.vvp 2>&1)
  if echo "$out" | grep -q "ALL TESTS PASSED"; then echo "$1: SURVIVED  <-- testbench hole"; else echo "$1: caught"; fi
}
run m01_no_minimum_green        's/green_met  = (cnt >= T_GREEN\[5:0\])/green_met  = 1'"'"'b1/'
run m02_emergency_ignored_green 's/if (ped_pending \&\& !emerg \&\& green_met)/if (ped_pending \&\& green_met)/'
run m03_walk_not_cut_short      's/if (emerg || phase_done) state_next = S_CLEAR/if (phase_done) state_next = S_CLEAR/'
run m04_allred1_ignores_emerg   's/state_next = emerg ? S_GREEN : S_WALK/state_next = S_WALK/'
run m05_level_not_edge          's/wire ped_rise = ped_s2 \& ~ped_s3/wire ped_rise = ped_s2/'
run m06_press_in_walk_latched   's/ped_rise \&\& !in_walk_or_clear/ped_rise/'
run m07_pending_never_cleared   's/else if (start_walk)                 ped_pending <= 1.b0;/else if (1'"'"'b0) ped_pending <= 1'"'"'b0;/'
run m08_yellow_one_tick_short   's/S_YELLOW:  dur = T_YELLOW\[5:0\]/S_YELLOW:  dur = T_YELLOW[5:0] - 6'"'"'d1/'
run m09_bad_illegal_recovery    's/default:   state_next = S_ALLRED2;   \/\/ illegal-state recovery/default:   state_next = S_GREEN;/'
run m10_clearance_skipped       's/S_CLEAR:   if (phase_done) state_next = S_ALLRED2/S_CLEAR:   if (phase_done | emerg) state_next = S_ALLRED2/'
run m11_walk_during_yellow      's/S_YELLOW: begin v_r = 1.b0; v_y = 1.b1; end/S_YELLOW: begin v_r = 1'"'"'b0; v_y = 1'"'"'b1; p_w = 1'"'"'b1; p_s = 1'"'"'b0; end/'
run m12_reset_state_is_green    's/if (!rst_n) state <= S_ALLRED2;/if (!rst_n) state <= S_GREEN;/'
run m13_pending_survives_reset  's/if (!rst_n)                          ped_pending <= 1.b0;/if (!rst_n) ped_pending <= ped_pending;/'
run m14_emergency_unsynchronised 's/assign emergency_active = emerg;/assign emergency_active = emergency_req;/'
run m15_prescaler_not_restarted 's/pre <= {PRE_W{1.b0}};       \/\/ every phase starts with a fresh tick/pre <= pre;/'
run m16_green_without_request   's/if (ped_pending \&\& !emerg \&\& green_met)/if (!emerg \&\& green_met)/'
rm -rf $TMP
