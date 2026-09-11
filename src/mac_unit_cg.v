// mac_unit_cg.v
// MAC unit WITH explicit clock gating via clock_gating_cell.
// Sequential logic is clocked by gated_clk instead of clk, so the
// register bank does not toggle at all when `en` is low.
module mac_unit_cg #(
    parameter WIDTH = 16
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               en,
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output reg  [2*WIDTH-1:0] acc
);

    wire gated_clk;
    wire [2*WIDTH-1:0] mult;
    wire [2*WIDTH-1:0] sum;

    // Instantiate clock gating cell. Instance is named u_cg — the
    // constraints file below matches it by REF_NAME so DONT_TOUCH
    // still applies no matter what this instance is called.
    clock_gating_cell u_cg (
        .clk       (clk),
        .en        (en),
        .test_en   (1'b0),      // tie low: normal (non-DFT) operation
        .gated_clk (gated_clk)
    );

    // Combinational logic (unclocked, so it isn't affected by gating)
    assign mult = a * b;
    assign sum  = acc + mult;

    // Sequential logic uses the GATED clock
    always @(posedge gated_clk or negedge rst_n) begin
        if (!rst_n)
            acc <= {2*WIDTH{1'b0}};
        else if (en)  // belt-and-braces: acc only updates when en=1 anyway
            acc <= sum;
    end

endmodule
