`timescale 1ns/1ps
// tb_activity_sweep.sv
//
// Drives all THREE MAC variants with the IDENTICAL stimulus stream, at a
// configurable activity factor (`+EN_PROB=<0-100>`), and dumps a VCD.
// Correctness is already proven elsewhere (tb_mac.v, tb_mac_pipelined.sv)
// -- this testbench exists purely to capture real, measurable switching
// activity for the toggle-based Clock Gating Efficiency (CGE) analysis
// in scripts/toggle_cge_analysis.py:
//
//   CGE = 1 - (rising-edge count of the gated clock / rising-edge count
//              of the reference clock) over the same window
//
// which is a direct, tool-independent proxy for the dynamic-power
// savings a real Vivado SAIF/report_power flow would show (fewer clock
// edges reaching the registers behind that gate == less switched
// capacitance == less dynamic power), and one we can actually compute
// and plot right here without needing a Vivado license.
module tb_activity_sweep;

    parameter WIDTH = 16;
    parameter N     = 3000;

    int en_prob;
    initial begin
        if (!$value$plusargs("EN_PROB=%d", en_prob))
            en_prob = 50;
    end

    logic               clk, rst_n, en;
    logic [WIDTH-1:0]   a, b;
    logic [2*WIDTH-1:0] acc_baseline, acc_cg, acc_pipe;
    logic               pipe_valid_out;

    mac_unit #(.WIDTH(WIDTH)) u_baseline (
        .clk(clk), .rst_n(rst_n), .en(en), .a(a), .b(b), .acc(acc_baseline)
    );

    mac_unit_cg #(.WIDTH(WIDTH)) u_cg (
        .clk(clk), .rst_n(rst_n), .en(en), .a(a), .b(b), .acc(acc_cg)
    );

    mac_unit_pipelined_cg #(.WIDTH(WIDTH)) u_pipe (
        .clk(clk), .rst_n(rst_n), .en(en), .a(a), .b(b),
        .acc(acc_pipe), .valid_out(pipe_valid_out)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

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

        #50;
        $finish;
    end

    // Full recursive dump -- the post-processing script only looks at
    // clk / gated_clk / gated_clk_s1 / gated_clk_s2 by name, but a full
    // dump keeps this testbench simple and reusable for other signals
    // later without having to touch the dump list.
    initial begin
        $dumpfile("activity_sweep.vcd");
        $dumpvars(0, tb_activity_sweep);
    end

endmodule
