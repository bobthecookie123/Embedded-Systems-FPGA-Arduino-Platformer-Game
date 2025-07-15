module pulse_extender #(
    parameter integer PULSE_WIDTH = 500000  // 10ms @ 50MHz
)(
    input  logic clk,
    input  logic trigger,        // 1-cycle input pulse from FSM
    output logic extended_out    // stays high for PULSE_WIDTH cycles
);

    localparam integer COUNTER_WIDTH = 26;  // log2(50_000_000) ≈ 26
    logic [COUNTER_WIDTH-1:0] counter = 0;
    logic active = 0;

    always_ff @(posedge clk) begin
        if (trigger && !active) begin
            counter <= PULSE_WIDTH;
            active  <= 1;
        end else if (active && counter > 0) begin
            counter <= counter - 1;
            if (counter == 1)
                active <= 0;
        end
    end

    assign extended_out = active;

endmodule
