// mac_unit_pipelined_cg.v
//
// ADVANCED variant of the MAC unit. Two low-power techniques beyond the
// simple single-stage mac_unit_cg.v:
//
//   1. OPERAND ISOLATION: mac_unit_cg.v gates the *output register's*
//      clock, but `mult = a * b` is a combinational multiplier that keeps
//      toggling every time a/b change, REGARDLESS of `en`. That toggling
//      still burns dynamic power even while the design is "disabled".
//      Here, a_iso/b_iso are forced to 0 whenever en=0, so the
//      multiplier's internal combinational logic sees constant inputs
//      and stops toggling too -- not just the register.
//
//   2. FINE-GRAIN, PER-STAGE CLOCK GATING: the design is pipelined
//      (multiply in stage 1, accumulate in stage 2), and EACH stage has
//      its OWN clock-gating cell, gated by that stage's own valid signal.
//      This means stage 2's clock only ungates on cycles where stage 1
//      actually produced a valid product -- e.g. after a single `en=1`
//      followed by `en=0`, stage 1's clock gates off immediately, but
//      stage 2 still needs one more active cycle to drain the pipeline,
//      then also gates off. Coarser (single, block-level) gating cannot
//      express this -- it's an all-or-nothing gate for the whole unit.
//
// Latency: 2 cycles (valid_out is asserted 2 cycles after a request with
// en=1). Throughput: 1 operation/cycle (fully pipelined).
module mac_unit_pipelined_cg #(
    parameter WIDTH = 16
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               en,        // request / stage-0 valid-in
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output reg  [2*WIDTH-1:0] acc,
    output reg                valid_out  // acc updated this cycle
);

    // ---------------- Stage 0: operand isolation + multiply ----------------
    // Isolate operands when idle so the multiplier's combinational logic
    // (a big fan-in tree) doesn't toggle on every unrelated a/b change.
    wire [WIDTH-1:0]   a_iso = en ? a : {WIDTH{1'b0}};
    wire [WIDTH-1:0]   b_iso = en ? b : {WIDTH{1'b0}};
    wire [2*WIDTH-1:0] mult  = a_iso * b_iso;

    // ---------------- Stage 1: pipeline register (product) ----------------
    // FIX (found by the self-checking testbench, see tb_mac_pipelined.sv --
    // 1997/1999 mismatches before this): the control signal `valid_s1`
    // must NOT be clocked by the gated clock it also helps generate.
    // When en=0, gated_clk_s1 never ticks, so a `valid_s1` register
    // living on gated_clk_s1 would freeze at its last value instead of
    // deasserting -- stage 2 then keeps re-consuming a stale product
    // forever. Fix: keep the 1-bit valid/control chain on the ALWAYS-ON
    // clock (negligible power cost either way for 1 bit), and gate ONLY
    // the wide data register (mult_r) whose toggling is actually worth
    // saving power on.
    wire gated_clk_s1;
    clock_gating_cell u_cg_s1 (
        .clk       (clk),
        .en        (en),
        .test_en   (1'b0),
        .gated_clk (gated_clk_s1)
    );

    reg [2*WIDTH-1:0] mult_r;
    reg               valid_s1;

    // Data register: gated (only worth updating -- and only worth the
    // capacitive toggling -- when en=1).
    always @(posedge gated_clk_s1 or negedge rst_n) begin
        if (!rst_n)
            mult_r <= {2*WIDTH{1'b0}};
        else
            mult_r <= mult;
    end

    // Control register: ALWAYS-ON clock, so it correctly tracks en's
    // transitions every cycle, including the deassertion.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_s1 <= 1'b0;
        else
            valid_s1 <= en;
    end

    // ---------------- Stage 2: accumulate ----------------
    // Gated on valid_s1, NOT on `en` -- this stage's clock must stay
    // ungated one extra cycle after `en` drops, to drain the pipeline.
    wire gated_clk_s2;
    clock_gating_cell u_cg_s2 (
        .clk       (clk),
        .en        (valid_s1),
        .test_en   (1'b0),
        .gated_clk (gated_clk_s2)
    );

    wire [2*WIDTH-1:0] sum = acc + mult_r;

    // Data register: gated.
    always @(posedge gated_clk_s2 or negedge rst_n) begin
        if (!rst_n)
            acc <= {2*WIDTH{1'b0}};
        else if (valid_s1)
            acc <= sum;
    end

    // Control register: ALWAYS-ON clock.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_out <= 1'b0;
        else
            valid_out <= valid_s1;
    end

endmodule
