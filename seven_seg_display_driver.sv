module seven_seg_display_driver (
    input wire [3:0] digit,      // 4-bit input digit (BCD)
    output wire [6:0] segments  // 7-segment display output (g, f, e, d, c, b, a)
);

    // Active-low outputs
    assign segments = (digit == 4'd0) ? 7'b1000000 : // 0
                      (digit == 4'd1) ? 7'b1111001 : // 1
                      (digit == 4'd2) ? 7'b0100100 : // 2
                      (digit == 4'd3) ? 7'b0110000 : // 3
                      (digit == 4'd4) ? 7'b0011001 : // 4
                      (digit == 4'd5) ? 7'b0010010 : // 5
                      (digit == 4'd6) ? 7'b0000010 : // 6
                      (digit == 4'd7) ? 7'b1111000 : // 7
                      (digit == 4'd8) ? 7'b0000000 : // 8
                      (digit == 4'd9) ? 7'b0010000 : // 9
                      7'b1111111;                  // Blank for invalid input

endmodule