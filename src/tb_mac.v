`timescale 1ns/1ps

// tb_mac.v
// Drives BOTH mac_unit (ungated) and mac_unit_cg (gated) with identical
// stimulus so their switching activity can be compared fairly.
//
// NOTE on SAIF capture: $set_toggle_region / $toggle_start / $toggle_stop /
// $toggle_report below are the IEEE-1364 PLI toggle-counting tasks, which
// are supported by several simulators (Questa/VCS/Xcelium) but Xilinx's
// XSIM documents a *different*, Tcl-based SAIF flow (open_saif / log_saif /
// close_saif — see scripts/xsim_saif.tcl in this project). If you simulate
// with `xsim`/Vivado's built-in simulator and these tasks are not
// recognized, use scripts/xsim_saif.tcl instead — it drives this exact
// testbench and captures the SAIF the Xilinx-native way. Kept here as-is
// for portability to simulators that do support them.
module tb_mac;

    parameter WIDTH = 16;
    parameter N     = 1000;  // Number of operations

    reg              clk;
    reg              rst_n;
    reg              en;
    reg  [WIDTH-1:0] a, b;
    wire [2*WIDTH-1:0] acc_normal;
    wire [2*WIDTH-1:0] acc_cg;

    // Instantiate both designs
    mac_unit #(
        .WIDTH(WIDTH)
    ) u_mac_normal (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .a     (a),
        .b     (b),
        .acc   (acc_normal)
    );

    mac_unit_cg #(
        .WIDTH(WIDTH)
    ) u_mac_cg (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .a     (a),
        .b     (b),
        .acc   (acc_cg)
    );

    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Stimulus
    integer i;
    initial begin
        // Initialize
        rst_n = 0;
        en    = 0;
        a     = 0;
        b     = 0;

        #20 rst_n = 1;

        // Run N operations with random enable.
        //
        // FIX #1: use `$random & 1` instead of `$random % 2`. $random
        // returns a signed 32-bit value, so `% 2` can yield -1, 0, or 1 —
        // it still truncates correctly into the 1-bit `en` reg, but it's
        // confusing to read and easy to misuse elsewhere. `& 1` is
        // unambiguous.
        //
        // FIX #2 (the important one — confirmed by actually simulating
        // this testbench): driving a/b/en on `@(posedge clk)` — the SAME
        // edge both DUTs sample on — is a race. mac_unit samples directly
        // on `posedge clk`, in the same delta cycle as this stimulus
        // update, so which value (old or new) it sees is scheduling-
        // dependent. mac_unit_cg samples on `posedge gated_clk`, which is
        // produced one extra delta cycle later (clk -> latch -> AND gate),
        // so it consistently sees the *new* values instead. Net effect:
        // the two DUTs silently diverge on almost every single operation,
        // which was verified empirically — 999/1000 mismatches with the
        // original `@(posedge clk)` stimulus, 0/1000 after this fix.
        // That completely invalidates any correctness/power comparison
        // between them. Driving stimulus on the opposite edge (`negedge`)
        // gives it a full half-period to settle before either DUT's
        // rising edge samples it, removing the race entirely.
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            en = ($random & 1);   // ~50% activity
            a  = $random;
            b  = $random;
        end

        #50;
        $finish;
    end

    // SAIF dumping for power analysis (see file header note above).
    //
    // FIX (confirmed by actually compiling+running this testbench):
    // $set_toggle_region / $toggle_start / $toggle_stop / $toggle_report
    // are FATAL "not defined by any module" errors on Icarus Verilog, and
    // are not part of Xilinx XSIM's documented SAIF flow either — so
    // leaving them unconditional broke simulation outright rather than
    // just failing to capture a SAIF. They're now compiled in only when
    // `USE_TOGGLE_TASKS` is defined (pass `+define+USE_TOGGLE_TASKS` at
    // compile time on a simulator that actually implements them, e.g.
    // Questa/VCS/Xcelium). Default build simply skips this block and
    // stays runnable everywhere; on Vivado/xsim use scripts/xsim_saif.tcl
    // instead to capture the SAIF.
`ifdef USE_TOGGLE_TASKS
    initial begin
        $set_toggle_region(tb_mac);
        $toggle_start();

        // Wait for simulation to finish.
        // N operations * 10ns/clock + 20ns reset + 50ns tail + margin.
        #((N + 10) * 10);

        $toggle_stop();
        $toggle_report("mac_power.saif", 1e-9, tb_mac);
    end
`endif

    // VCD for waveform viewing
    initial begin
        $dumpfile("mac_waveform.vcd");
        $dumpvars(0, tb_mac);
    end

endmodule
