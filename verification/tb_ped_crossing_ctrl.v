`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Self-checking testbench for ped_crossing_ctrl.
// Short timing parameters are used so simulation is fast:
//   one tick = 4 clocks; phase lengths in clocks:
//   GREEN(min)=20, YELLOW=8, ALLRED1=12, WALK=16, CLEAR=20, ALLRED2=8
// Run:  iverilog -g2012 -o sim/tb.vvp rtl/ped_crossing_ctrl.v tb/tb_ped_crossing_ctrl.v
//       vvp sim/tb.vvp [+vcd]
// -----------------------------------------------------------------------------
module tb_ped_crossing_ctrl;

    localparam DIV = 4, PRE_W = 3;
    localparam TG = 5, TY = 2, TA1 = 3, TW = 4, TC = 5, TA2 = 2;

    localparam [2:0] S_AR2 = 3'd0, S_G = 3'd1, S_Y = 3'd2,
                     S_AR1 = 3'd3, S_W = 3'd4, S_C = 3'd5;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ped_req = 1'b0;
    reg emergency_req = 1'b0;

    wire vr, vy, vg, pw, pc, ps, pwait, eact;
    wire [2:0] st;

    ped_crossing_ctrl #(
        .CLK_DIV(DIV), .PRE_W(PRE_W),
        .T_GREEN(TG), .T_YELLOW(TY), .T_ALLRED1(TA1),
        .T_WALK(TW), .T_CLEAR(TC), .T_ALLRED2(TA2)
    ) dut (
        .clk(clk), .rst_n(rst_n), .ped_req(ped_req), .emergency_req(emergency_req),
        .vehicle_red(vr), .vehicle_yellow(vy), .vehicle_green(vg),
        .ped_walk(pw), .ped_clear(pc), .ped_stop(ps), .ped_wait(pwait),
        .emergency_active(eact), .state_dbg(st)
    );

    always #5 clk = ~clk;   // 100 MHz in simulation (period is irrelevant to the logic)

    // ------------------------------------------------------------ bookkeeping
    integer errors = 0;
    integer checks = 0;
    reg     mon_en = 1'b0;

    task automatic check(input cond, input [8*72-1:0] msg);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("[FAIL] t=%0t ns : %0s", $time, msg);
            end
        end
    endtask

    function legal(input [2:0] a, input [2:0] b);
        begin
            case (a)
                3'd0:    legal = (b == 3'd1);
                3'd1:    legal = (b == 3'd2);
                3'd2:    legal = (b == 3'd3);
                3'd3:    legal = (b == 3'd4) || (b == 3'd1);
                3'd4:    legal = (b == 3'd5);
                3'd5:    legal = (b == 3'd0);
                default: legal = (b == 3'd0);      // illegal states recover to ALLRED2
            endcase
        end
    endfunction

    // ----------------------------------------------- monitor 1: every negedge
    reg [2:0] prev_st = 3'd0;
    integer   age = 0;
    reg       prev_em = 1'b0, prev_pw = 1'b0, em_seen = 1'b0;
    reg       skip_trans = 1'b0, no_age = 1'b1;
    reg [5:0] exp_out;
    integer   wait_cnt = 0;

    always @(negedge rst_n) begin   // a reset event: next state change is not a "transition"
        skip_trans = 1'b1;
        no_age     = 1'b1;
    end

    always @(negedge clk) if (mon_en) begin
        // no X/Z on any output
        check((^{vr, vy, vg, pw, pc, ps, pwait, eact, st}) !== 1'bx, "X/Z on an output");

        // Moore output decode for the current state (illegal states -> all red / ped stop)
        case (st)
            S_G:     exp_out = 6'b001_001;
            S_Y:     exp_out = 6'b010_001;
            S_W:     exp_out = 6'b100_100;
            S_C:     exp_out = 6'b100_010;
            default: exp_out = 6'b100_001;
        endcase
        check({vr, vy, vg, pw, pc, ps} === exp_out, "output pattern does not match state");

        // safety rules (checked independently of the decode table)
        check(!((vg | vy) & (pw | pc)),   "CONFLICT: vehicle go/caution together with ped walk/clear");
        check((vr + vy + vg) == 1,        "vehicle lamps not exactly one-hot");
        check((pw + pc + ps) == 1,        "pedestrian signals not exactly one-hot");
        check(!(vg && ped_walk_any(pw, pc)), "green with ped permission");

        // state-change checks
        if (st !== prev_st) begin
            if (!skip_trans) begin
                check(legal(prev_st, st), "illegal state transition");
                if (!no_age) begin
                    case (prev_st)
                        S_Y:   check(age == TY  * DIV, "YELLOW duration wrong");
                        S_AR1: check(age == TA1 * DIV, "ALLRED1 duration wrong");
                        S_C:   check(age == TC  * DIV, "CLEAR duration wrong");
                        S_AR2: check(age == TA2 * DIV, "ALLRED2 duration wrong");
                        S_W:   if (em_seen) check(age <= TW * DIV, "WALK longer than allowed");
                               else         check(age == TW * DIV, "WALK duration wrong");
                        default: ;
                    endcase
                end
                if (prev_st == S_G) begin
                    check(age >= TG * DIV, "minimum green violated");
                    check(!prev_em,        "left GREEN while emergency active");
                    check(prev_pw,         "left GREEN without a pending request");
                end
                if (prev_st == S_AR1)
                    check(prev_em ? (st == S_G) : (st == S_W), "ALLRED1 exit wrong for emergency state");
                if (prev_st == S_W && age < TW * DIV)
                    check(prev_em, "WALK cut short without emergency");
                if (prev_st == S_W)
                    check(st == S_C, "WALK must be followed by CLEAR");
                no_age = 1'b0;
            end
            age     = 1;
            em_seen = 1'b0;
        end else begin
            age = age + 1;
        end
        skip_trans = 1'b0;

        // liveness: a pending request with no emergency must be served promptly
        if (st == S_G && pwait && !eact && !prev_em && age > TG * DIV) begin
            wait_cnt = wait_cnt + 1;
            check(wait_cnt < 3, "pending request not served after minimum green");
        end else
            wait_cnt = 0;

        em_seen = em_seen | eact;
        prev_em = eact;
        prev_pw = pwait;
        prev_st = st;
    end

    function ped_walk_any(input w, input c);
        ped_walk_any = w | c;
    endfunction

    // ------------------- monitor 2: ped_wait scoreboard (independent 2-FF model)
    reg       m1 = 1'b0, m2 = 1'b0, m3 = 1'b0, exp_pend = 1'b0, rise_b;
    reg [2:0] st_b, st_a;

    always @(negedge rst_n) begin
        m1 = 0; m2 = 0; m3 = 0; exp_pend = 0;
    end

    always @(posedge clk) if (mon_en) begin
        st_b   = st;
        rise_b = m2 & ~m3;
        m3 = m2; m2 = m1; m1 = ped_req;
        #1;
        st_a = st;
        if (!rst_n) begin
            m1 = 0; m2 = 0; m3 = 0; exp_pend = 0;
        end else if (st_b == S_AR1 && st_a == S_W) begin
            exp_pend = 1'b0;                                  // cleared when WALK starts
        end else if (rise_b && !(st_b == S_W || st_b == S_C)) begin
            exp_pend = 1'b1;                                  // captured (not while walking/clearing)
        end
        check(pwait === exp_pend, "ped_wait differs from request scoreboard");
    end

    // ------------------------------------------------------- stimulus helpers
    task cyc(input integer n);
        begin repeat (n) @(negedge clk); end
    endtask

    // press: button high for w clock periods, edges NOT aligned with clk
    task press(input integer w);
        begin
            @(negedge clk); #2 ped_req = 1'b1;
            repeat (w) @(negedge clk);
            #2 ped_req = 1'b0;
        end
    endtask

    task press_ns(input integer o, input integer w);
        begin
            @(negedge clk); #(o) ped_req = 1'b1;
            #(w) ped_req = 1'b0;
        end
    endtask

    task set_em(input v);
        begin @(negedge clk); #2 emergency_req = v; end
    endtask

    task wait_state(input [2:0] s, input integer maxc);
        integer i;
        begin
            i = 0;
            while (st !== s && i < maxc) begin @(negedge clk); i = i + 1; end
            if (st !== s) begin
                $display("[FAIL] t=%0t ns : timeout waiting for state %0d (now %0d)", $time, s, st);
                errors = errors + 1;
                summary_and_finish;
            end
        end
    endtask

    task ensure_green_steady;
        begin
            wait_state(S_G, 600);
            cyc(TG * DIV + 3);
        end
    endtask

    // drive the controller into state s starting from steady GREEN
    task go(input [2:0] s);
        begin
            ensure_green_steady;
            if (s != S_G) begin
                press(1);
                wait_state(S_Y, 60);
                if (s != S_Y) begin
                    wait_state(S_AR1, 60);
                    if (s != S_AR1) begin
                        wait_state(S_W, 60);
                        if (s != S_W) begin
                            wait_state(S_C, 60);
                            if (s != S_C) wait_state(S_AR2, 60);
                        end
                    end
                end
            end
        end
    endtask

    task settle_green;         // no inputs active: system must return to idle GREEN
        begin
            cyc(320);
            check(st == S_G && !pwait && !eact, "did not settle to idle GREEN");
        end
    endtask

    task hold_green(input integer n, input msgsel);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                check(st == S_G && vg, "GREEN must be held");
            end
        end
    endtask

    task summary_and_finish;
        begin
            $display("------------------------------------------------------------");
            $display("checks executed : %0d", checks);
            $display("errors          : %0d", errors);
            if (errors == 0) begin
                $display("RESULT: ALL TESTS PASSED");
                $finish;
            end else begin
                $display("RESULT: FAILED");
                $fatal(1, "testbench failed");
            end
        end
    endtask

    // watchdog
    initial begin
        #20_000_000;
        $display("[FAIL] watchdog timeout");
        errors = errors + 1;
        summary_and_finish;
    end

    initial #8 mon_en = 1'b1;

    // ------------------------------------------------------------------ tests
    integer n, j, k;
    reg [2:0] sx;

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("sim/ped_ctrl.vcd");
            $dumpvars(0, tb_ped_crossing_ctrl);
        end

        // ---------------- T01: reset state and start-up all-red phase
        $display("T01 reset values and start-up all-red phase");
        cyc(3);
        check(st == S_AR2 && vr && ps && !pwait && !eact, "T01 reset-state outputs");
        @(negedge clk); #1 rst_n = 1'b1;
        n = 0;
        while (st !== S_G) begin @(negedge clk); n = n + 1; end
        check(n == TA2 * DIV, "T01 start-up ALLRED2 duration");

        // ---------------- T02: idle - no request keeps GREEN
        $display("T02 idle GREEN with no requests");
        hold_green(3 * TG * DIV, 0);

        // ---------------- T03: one normal pedestrian cycle
        $display("T03 normal pedestrian cycle");
        ensure_green_steady;
        press(1);
        cyc(3);
        check(pwait, "T03 ped_wait should be high after press");
        check(st == S_G || st == S_Y, "T03 still green/yellow right after press");
        wait_state(S_Y, 20);  check(vy && pwait, "T03 yellow with ped_wait");
        wait_state(S_AR1, 20); check(vr && ps && pwait, "T03 all-red before walk");
        wait_state(S_W, 30);   check(pw && !pwait && !vg && !vy, "T03 walk clears ped_wait");
        wait_state(S_C, 30);   check(pc && vr, "T03 clearance");
        wait_state(S_AR2, 30); check(vr && ps, "T03 all-red after clearance");
        wait_state(S_G, 20);   check(vg && ps && !pwait, "T03 vehicles resume");
        settle_green;

        // ---------------- T04: request arriving right at start of GREEN waits for minimum green
        $display("T04 request early in GREEN respects minimum green");
        go(S_Y);                      // a cycle
        wait_state(S_G, 120);
        press(1);
        cyc(3);
        check(pwait && st == S_G, "T04 request pending while still in min green");
        wait_state(S_Y, 60);          // monitor checks age >= minimum green
        settle_green;

        // ---------------- T05: held button counts as one request
        $display("T05 held button = one request");
        ensure_green_steady;
        @(negedge clk); #2 ped_req = 1'b1;
        wait_state(S_Y, 20);
        wait_state(S_G, 200);
        hold_green(3 * TG * DIV, 0);
        check(!pwait, "T05 held button must not re-request");
        ped_req = 1'b0;
        cyc(6);
        press(1);
        wait_state(S_Y, 60);          // fresh press is served
        settle_green;

        // ---------------- T06: single-clock pulses at several phases relative to clk
        $display("T06 one-clock pulses at different phases");
        ensure_green_steady; press_ns(1, 10);  cyc(4); check(pwait, "T06a pulse captured"); settle_green;
        ensure_green_steady; press_ns(7, 9);   cyc(4); check(pwait, "T06b pulse captured"); settle_green;
        ensure_green_steady; press_ns(9, 10);  cyc(4); check(pwait, "T06c pulse captured"); settle_green;

        // ---------------- T07: emergency held in GREEN with a pending pedestrian request
        $display("T07 emergency holds GREEN, pedestrian request is kept");
        ensure_green_steady;
        set_em(1'b1);
        cyc(4); check(eact, "T07 emergency_active");
        press(1);
        cyc(4); check(pwait, "T07 request latched during emergency");
        hold_green(3 * TG * DIV, 0);
        check(pwait, "T07 request still pending");
        set_em(1'b0);
        wait_state(S_Y, 20);          // pending request now served
        settle_green;

        // ---------------- T08: simultaneous pedestrian and emergency request
        $display("T08 simultaneous pedestrian + emergency request");
        ensure_green_steady;
        @(negedge clk); #2 begin ped_req = 1'b1; emergency_req = 1'b1; end
        #10 ped_req = 1'b0;
        hold_green(4 * TG * DIV, 0);
        check(pwait && eact, "T08 emergency wins, request retained");
        set_em(1'b0);
        wait_state(S_Y, 20);
        settle_green;

        // ---------------- T09: emergency asserted in every phase of a cycle
        $display("T09 emergency in each phase");
        for (k = 0; k < 5; k = k + 1) begin
            case (k)
                0: sx = S_Y;   1: sx = S_AR1;  2: sx = S_W;  3: sx = S_C;  default: sx = S_AR2;
            endcase
            go(sx);
            cyc(1);
            set_em(1'b1);
            if (sx == S_W) begin
                cyc(4);
                check(st == S_C, "T09 emergency during WALK must go straight to CLEAR");
            end
            wait_state(S_G, 200);
            hold_green(3 * TG * DIV, 0);       // emergency still active: GREEN held, no WALK
            set_em(1'b0);
            settle_green;
        end

        // ---------------- T10: reset asynchronously asserted in every phase
        $display("T10 reset during every phase");
        for (k = 0; k < 6; k = k + 1) begin
            case (k)
                0: sx = S_G;  1: sx = S_Y;  2: sx = S_AR1;  3: sx = S_W;  4: sx = S_C;  default: sx = S_AR2;
            endcase
            go(sx);
            cyc(1);
            if (k % 2 == 1) set_em(1'b1);
            @(negedge clk); #3 rst_n = 1'b0;
            #1;
            check(st == S_AR2 && vr && ps && !pwait && !eact, "T10 reset must force the all-red state");
            #11;
            emergency_req = 1'b0;
            #6 rst_n = 1'b1;
            wait_state(S_G, 100);
            cyc(TG * DIV + 10);
            check(st == S_G && !pwait, "T10 no stale request after reset");
        end

        // ---------------- T11: illegal-state recovery (state corrupted by force)
        $display("T11 illegal state recovery");
        for (k = 6; k <= 7; k = k + 1) begin
            ensure_green_steady;
            @(negedge clk); #1 skip_trans = 1'b1; no_age = 1'b1;
            force dut.state = k[2:0];
            #1;
            check(vr && ps && !vg && !vy && !pw && !pc, "T11 illegal state must drive all-red");
            release dut.state;
            @(negedge clk);
            check(st == S_AR2, "T11 must recover to ALLRED2");
            wait_state(S_G, 40);
            settle_green;
        end

        // ---------------- T12: presses while walking / clearing are ignored
        $display("T12 presses during WALK and CLEAR are ignored");
        go(S_W);  cyc(3);  press(1);  cyc(4);  check(!pwait, "T12 press during WALK ignored");
        wait_state(S_C, 40);  cyc(3);  press(1);  cyc(4);  check(!pwait, "T12 press during CLEAR ignored");
        wait_state(S_G, 60);
        hold_green(3 * TG * DIV, 0);
        check(!pwait, "T12 no second cycle");

        // ---------------- T13: second press swept across the whole cycle (boundary cases)
        $display("T13 second press swept over every clock of the cycle");
        for (j = 0; j <= 80; j = j + 1) begin
            ensure_green_steady;
            press(1);
            wait_state(S_AR1, 60);
            cyc(j);
            press(1);
            settle_green;
        end

        // ---------------- T14: emergency pulse swept over every clock of the cycle
        $display("T14 emergency pulse swept over the cycle");
        for (j = 0; j <= 80; j = j + 2) begin
            ensure_green_steady;
            press(1);
            wait_state(S_Y, 60);
            cyc(j);
            set_em(1'b1);
            cyc(25);
            set_em(1'b0);
            settle_green;
        end

        // ---------------- T15: emergency pulse shorter than the synchronizer (1 clock)
        $display("T15 one-clock emergency pulse");
        ensure_green_steady;
        press(1); wait_state(S_W, 60); cyc(2);
        @(negedge clk); #2 emergency_req = 1'b1; @(negedge clk); #2 emergency_req = 1'b0;
        settle_green;

        cyc(5);
        summary_and_finish;
    end

endmodule
