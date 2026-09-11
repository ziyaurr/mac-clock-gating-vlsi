// mac_unit.v
// Baseline MAC (Multiply-Accumulate) unit WITHOUT clock gating.
// Used as the power/reference baseline against mac_unit_cg.v.
module mac_unit #(
    parameter WIDTH = 16
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               en,
    input  wire [WIDTH-1:0]   a,
    input  wire [WIDTH-1:0]   b,
    output reg  [2*WIDTH-1:0] acc
);

    wire [2*WIDTH-1:0] mult;
    wire [2*WIDTH-1:0] sum;

    assign mult = a * b;
    assign sum  = acc + mult;
    // NOTE: this is a finite-width free-running accumulator, so `sum`
    // can wrap on overflow. That's expected/accepted here since this
    // project's purpose is a power/toggle-activity comparison between
    // the gated and ungated versions, not a saturating arithmetic core.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= {2*WIDTH{1'b0}};
        else if (en)
            acc <= sum;
    end

endmodule
