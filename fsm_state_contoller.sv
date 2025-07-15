module fsm_state_controller (
    input  logic clk,
    input  logic key1_n,
    input  logic key0_n,
    input  logic collision_detected,
    output logic [2:0] state_leds,
    output logic state_pulse,
    output logic clock_enable,
    output logic tick,
    output logic tick_player_y,
    output logic obstacle_enable,
    output logic [6:0] player_y,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5
);

    localparam integer HALF_PERIOD_CYCLES = 781_250;
    localparam integer Y_TICK_CYCLES     = 781_250;

    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        ACTIVE = 2'b01,
        END    = 2'b10
    } state_t;

    state_t pr_state = IDLE, nx_state;

    logic key1_sync_0, key1_sync_1, key1_prev, key1_debounced;
    logic key1_pressed;

    always_ff @(posedge clk) begin
        key1_sync_0 <= key1_n;
        key1_sync_1 <= key1_sync_0;
        key1_prev   <= key1_debounced;
    end

    assign key1_debounced = key1_sync_1;
    assign key1_pressed   = (key1_prev == 1 && key1_debounced == 0);

    always_ff @(posedge clk) begin
        pr_state <= nx_state;
    end

    logic score_reached;

    always_comb begin
        nx_state = pr_state;
        case (pr_state)
            IDLE:    if (key1_pressed) nx_state = ACTIVE;
            ACTIVE:  if (score_reached || collision_detected || key1_pressed) nx_state = END;
            END:     if (key1_pressed) nx_state = IDLE;
        endcase
    end

    assign state_leds = (pr_state == IDLE)   ? 3'b001 :
                        (pr_state == ACTIVE) ? 3'b010 :
                        (pr_state == END)    ? 3'b100 : 3'b000;

    logic state_pulse_reg = 0;
    state_t prev_pr_state = IDLE;

    always_ff @(posedge clk) begin
        if (pr_state != prev_pr_state)
            state_pulse_reg <= 1;
        else
            state_pulse_reg <= 0;
        prev_pr_state <= pr_state;
    end

    assign state_pulse     = state_pulse_reg;
    assign clock_enable    = (pr_state == ACTIVE);
    assign obstacle_enable = (pr_state == ACTIVE);

    logic [$clog2(HALF_PERIOD_CYCLES):0] tick_counter = 0;
    logic tick_reg = 0;

    always_ff @(posedge clk) begin
        if (pr_state == ACTIVE) begin
            tick_counter <= tick_counter + 1;
            if (tick_counter == HALF_PERIOD_CYCLES) begin
                tick_reg <= ~tick_reg;
                tick_counter <= 0;
            end
        end else begin
            tick_counter <= 0;
            tick_reg <= 0;
        end
    end

    assign tick = tick_reg;

    logic tick_prev;
    wire pixel_tick = (tick == 1 && tick_prev == 0);

    always_ff @(posedge clk) begin
        tick_prev <= tick;
    end

    logic [$clog2(Y_TICK_CYCLES):0] y_tick_counter = 0;
    logic y_tick = 0;

    always_ff @(posedge clk) begin
        if (pr_state == ACTIVE) begin
            y_tick_counter <= y_tick_counter + 1;
            if (y_tick_counter == Y_TICK_CYCLES) begin
                y_tick <= ~y_tick;
                y_tick_counter <= 0;
            end
        end else begin
            y_tick_counter <= 0;
            y_tick <= 0;
        end
    end

    logic y_tick_prev = 0;
    wire y_tick_rising = (y_tick == 1 && y_tick_prev == 0);

    always_ff @(posedge clk) begin
        y_tick_prev <= y_tick;
        if (pr_state == ACTIVE && y_tick_rising) begin
            if (~key0_n && player_y < 64)
                player_y <= player_y + 1;
            else if (key0_n && player_y > 0)
                player_y <= player_y - 1;
        end
    end

    assign tick_player_y = ~key0_n && (pr_state == ACTIVE);

    // === HEX2 / HEX3 Display (player_y) ===
    logic [23:0] bcd_out;
    logic [6:0] seg2, seg3;

    double_dabble u_dabble (
        .bin({13'd0, player_y}),
        .bcd(bcd_out)
    );

    seven_seg_display_driver u_hex2 (.digit(bcd_out[3:0]), .segments(seg2));
    seven_seg_display_driver u_hex3 (.digit(bcd_out[7:4]), .segments(seg3));

    assign HEX2 = (pr_state == ACTIVE) ? seg2 : 7'b1111111;
    assign HEX3 = (pr_state == ACTIVE) ? seg3 : 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

    // === Score Tracking and Display (HEX0 / HEX1) ===
    logic [6:0] score = 0;
    logic [6:0] tick_count = 0;
    logic [19:0] score_bin;
    logic [23:0] score_bcd;
    logic [7:0] score_display_bcd;
    logic [6:0] seg0, seg1;

    always_ff @(posedge clk) begin
        if (pr_state == ACTIVE && pixel_tick && score < 90) begin
            tick_count <= tick_count + 1;
            if (tick_count == 9) begin
                tick_count <= 0;
                score <= score + 1;
            end
        end else if (pr_state == IDLE) begin
            tick_count <= 0;
            score <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (score == 90 && tick_count == 9)
            score_reached <= 1;
        else if (pr_state == IDLE)
            score_reached <= 0;
    end

    assign score_bin = {13'd0, score};

    double_dabble u_score_dabble (
        .bin(score_bin),
        .bcd(score_bcd)
    );

    // === Score display logic that latches and holds 60 correctly ===
    always_ff @(posedge clk) begin
        if (pr_state == IDLE)
            score_display_bcd <= 8'd0;
        else if (score >= 60)
            score_display_bcd <= {4'd6, 4'd0}; // Correct BCD for 60
        else if (pr_state == ACTIVE)
            score_display_bcd <= score_bcd[7:0];
    end

    seven_seg_display_driver u_hex0 (.digit(score_display_bcd[3:0]), .segments(seg0));
    seven_seg_display_driver u_hex1 (.digit(score_display_bcd[7:4]), .segments(seg1));

    assign HEX0 = (pr_state == ACTIVE || pr_state == END) ? seg0 : 7'b1111111;
    assign HEX1 = (pr_state == ACTIVE || pr_state == END) ? seg1 : 7'b1111111;

endmodule
