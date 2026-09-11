`timescale 1ns/1ps
// tb_mac_pipelined.sv
//
// Self-checking testbench for mac_unit_pipelined_cg (2-cycle latency).
// Layers, from "verified right now" to "written for a real SV sim":
//
//   1. Scoreboard (reference queue model) + IMMEDIATE assertions --
//      confirmed to run on Icarus Verilog (`iverilog -g2012`).
//   2. Concurrent SVA properties + a functional covergroup -- IEEE-1800
//      standard syntax, but neither Icarus 12.0 nor Verilator 5.020
//      implement `covergroup`/cycle-delay `assert property` (both were
//      tried here and rejected at parse time). Guarded behind
//      `USE_SVA_COVERAGE` so the file still compiles+runs everywhere by
//      default; define that macro on Vivado xsim / Questa / VCS to
//      compile them in.
module tb_mac_pipelined;

    parameter WIDTH = 16;
    parameter N     = 2000;

    // Activity factor (probability en=1, in percent) -- overridable via
    // `+EN_PROB=<0-100>` so this same testbench drives the sweep script.
    int en_prob;
    initial begin
        if (!$value$plusargs("EN_PROB=%d", en_prob))
            en_prob = 50;
    end

    logic               clk, rst_n, en;
    logic [WIDTH-1:0]   a, b;
    logic [2*WIDTH-1:0] acc;
    logic               valid_out;

    mac_unit_pipelined_cg #(.WIDTH(WIDTH)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (en),
        .a         (a),
        .b         (b),
        .acc       (acc),
        .valid_out (valid_out)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    // ---------------- Reference (software) model ----------------
    // Mirrors the DUT's 2-stage pipeline exactly, including the
    // operand-isolation-forces-zero behaviour, so it stays correct even
    // when en=0 (isolated inputs would multiply to 0 anyway, but the
    // model does the same isolation for symmetry with the RTL).
    logic [2*WIDTH-1:0] ref_acc;
    logic [2*WIDTH-1:0] ref_mult_r, ref_mult;
    logic                ref_valid_s1;

    int mismatches = 0;
    int checked    = 0;

    // ---------------- Stimulus ----------------
    int i;
    initial begin
        rst_n = 0; en = 0; a = 0; b = 0;
        #20 rst_n = 1;

        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            en = ($urandom_range(0, 99) < en_prob);
            a  = $urandom;
            b  = $urandom;
        end

        // Drain the pipeline (2 extra cycles) before finishing.
        @(negedge clk); en = 0;
        @(negedge clk);
        @(negedge clk);
        $display("[tb_mac_pipelined] EN_PROB=%0d  checked=%0d  mismatches=%0d",
                  en_prob, checked, mismatches);
        if (mismatches == 0)
            $display("[tb_mac_pipelined] PASS");
        else
            $display("[tb_mac_pipelined] FAIL");
        $finish;
    end

    // ---------------- Reference model + scoreboard (runs every posedge) --
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_mult_r   <= '0;
            ref_valid_s1 <= 1'b0;
            ref_acc      <= '0;
        end else begin
            // stage 1 (always-on reference clock, no gating -- this is
            // the golden model, it just needs to be functionally right)
            ref_mult_r   <= en ? (a * b) : '0;
            ref_valid_s1 <= en;
            // stage 2
            if (ref_valid_s1)
                ref_acc <= ref_acc + ref_mult_r;
        end
    end

    // Compare DUT vs reference whenever the DUT says a result is valid.
    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            checked = checked + 1;
            // IMMEDIATE assertion -- evaluated right here, runs on Icarus.
            assert (acc === ref_acc) else begin
                mismatches = mismatches + 1;
                $display("MISMATCH @ %0t: dut_acc=%h ref_acc=%h", $time, acc, ref_acc);
            end
        end
    end

`ifdef USE_SVA_COVERAGE
    // ---------------- Concurrent assertions (Vivado xsim/Questa/VCS) ----
    // No glitches on either gated clock: a rising edge on gated_clk_s1
    // must never occur while `en` looks unstable going into it (the
    // latch should have already resolved en_latch during the low phase).
    property p_no_glitch_s1;
        @(posedge clk) $rose(dut.gated_clk_s1) |-> $stable(dut.u_cg_s1.en_latch);
    endproperty
    a_no_glitch_s1: assert property (p_no_glitch_s1);

    property p_no_glitch_s2;
        @(posedge clk) $rose(dut.gated_clk_s2) |-> $stable(dut.u_cg_s2.en_latch);
    endproperty
    a_no_glitch_s2: assert property (p_no_glitch_s2);

    // valid_out must never assert unless stage 1 was valid the cycle before.
    property p_valid_causality;
        @(posedge clk) disable iff (!rst_n)
        valid_out |-> $past(valid_s1_probe);
    endproperty
    wire valid_s1_probe = dut.valid_s1;
    a_valid_causality: assert property (p_valid_causality);

    // ---------------- Functional coverage ----------------
    // Buckets the activity factor actually exercised and looks for
    // interesting sequences (back-to-back ops, idle stretches, a
    // request arriving the same cycle the pipeline is draining).
    covergroup cg_activity @(posedge clk);
        option.per_instance = 1;
        cp_en:      coverpoint en;
        cp_valid:   coverpoint valid_out;
        cp_back2back: coverpoint en iff (rst_n) {
            bins idle_run    = (0 [* 3:10]);
            bins active_run  = (1 [* 3:10]);
            bins toggling    = (0 => 1 => 0);
        }
        cross cp_en, cp_valid;
    endgroup
    cg_activity cg_inst = new();
`endif

endmodule
