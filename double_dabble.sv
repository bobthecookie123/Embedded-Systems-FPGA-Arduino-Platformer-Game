module double_dabble (
    input logic [19:0] bin,       // 20-bit binary input
    output logic [23:0] bcd       // 24-bit BCD output for 7 decimal digits
);

    integer i;                    // Iteration counter

    always_comb begin
        bcd = 0;                  // Initialize BCD to 0

        // Loop through all bits in the binary input
        for (i = 0; i < 20; i = i + 1) begin
            // Adjust BCD digits if any are >= 5
            if (bcd[3:0] >= 5)    bcd[3:0]   = bcd[3:0]   + 3;
            if (bcd[7:4] >= 5)    bcd[7:4]   = bcd[7:4]   + 3;
            if (bcd[11:8] >= 5)   bcd[11:8]  = bcd[11:8]  + 3;
            if (bcd[15:12] >= 5)  bcd[15:12] = bcd[15:12] + 3;
            if (bcd[19:16] >= 5)  bcd[19:16] = bcd[19:16] + 3;
            if (bcd[23:20] >= 5)  bcd[23:20] = bcd[23:20] + 3;

            // Shift left and bring in the next bit from binary input
            bcd = {bcd[22:0], bin[19 - i]};
        end
    end

endmodule