// clock_gating_cell.v
// Standard latch-based Integrated Clock Gating (ICG) cell.
// Level-sensitive (not edge-triggered) latch avoids glitches on
// gated_clk that a plain combinational AND-gate approach would cause.
module clock_gating_cell (
    input  wire clk,       // Global (ungated) clock
    input  wire en,        // Functional enable
    input  wire test_en,   // DFT test-mode enable (bypasses gating in scan mode)
    output wire gated_clk
);

    reg en_latch;

    // FIX: use a BLOCKING assignment ('=') inside a latch description.
    // Non-blocking ('<=') in a level-sensitive latch is a well-known
    // synthesis/simulation style pitfall (can create race conditions
    // when multiple latches are evaluated on the same event, and some
    // synthesis tools warn/refuse to infer a clean latch from it).
    always @(clk or en or test_en) begin
        if (!clk)
            en_latch = en | test_en;
    end

    assign gated_clk = clk & en_latch;

endmodule
