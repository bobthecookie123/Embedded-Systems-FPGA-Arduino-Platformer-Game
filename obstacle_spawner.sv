module obstacle_spawner (
    input  logic clk,
    input  logic reset,
    input  logic enable,
    input  logic [6:0] player_y,              // Player vertical position (0–64)
    output logic [3:0] spawn_pulse,           // Block spawn pulses for each lane
    output logic collision_detected           // 1-cycle pulse if collision occurs
);

    // === Constants ===
    localparam int TICKS_PER_STEP  = 1_562_500; // 32Hz at 50MHz
    localparam int PLAYER_X        = 30 + 33;   // Adjusted for Arduino offset (x = 63)
    localparam int OBSTACLE_WIDTH  = 32;
    localparam int OBSTACLE_HEIGHT = 16;
    localparam int COLLISION_TICKS_REQUIRED = 2;

    localparam int LANE0_Y = 0;
    localparam int LANE1_Y = 16;
    localparam int LANE2_Y = 32;
    localparam int LANE3_Y = 48;

    localparam int L1_LEN = 6;
    localparam int L2_LEN = 3;
    localparam int L3_LEN = 5;
    localparam int L4_LEN = 6;

    logic [9:0] lane1_spawn [0:L1_LEN-1] = '{161, 193, 257, 385, 417, 449};
    logic [9:0] lane2_spawn [0:L2_LEN-1] = '{225, 353, 577};
    logic [9:0] lane3_spawn [0:L3_LEN-1] = '{289, 353, 449, 481, 513};
    logic [9:0] lane4_spawn [0:L4_LEN-1] = '{161, 193, 257, 417, 545, 577};

    logic [9:0] l1_pos [0:L1_LEN-1];
    logic [9:0] l2_pos [0:L2_LEN-1];
    logic [9:0] l3_pos [0:L3_LEN-1];
    logic [9:0] l4_pos [0:L4_LEN-1];

    logic [$clog2(L1_LEN):0] lane1_index;
    logic [$clog2(L2_LEN):0] lane2_index;
    logic [$clog2(L3_LEN):0] lane3_index;
    logic [$clog2(L4_LEN):0] lane4_index;

    logic [3:0] pulse;
    assign spawn_pulse = pulse;

    logic collision_flag = 0;
    assign collision_detected = collision_flag;

    logic [$clog2(TICKS_PER_STEP):0] step_counter = 0;
    logic step_enable = 0;

    // === Collision tracking counters (per lane) ===
    logic [1:0] lane0_counter = 0;
    logic [1:0] lane1_counter = 0;
    logic [1:0] lane2_counter = 0;
    logic [1:0] lane3_counter = 0;

    // === Collision hit flags — must be declared outside procedural block
    logic hit0, hit1, hit2, hit3;

    // === Tick generation at 32Hz ===
    always_ff @(posedge clk) begin
        if (step_counter == TICKS_PER_STEP - 1) begin
            step_counter <= 0;
            step_enable <= 1;
        end else begin
            step_counter <= step_counter + 1;
            step_enable <= 0;
        end
    end

    always_ff @(posedge clk) begin
        pulse <= 4'b0000;
        collision_flag <= 0;

        if (reset) begin
            lane1_index <= 0;
            lane2_index <= 0;
            lane3_index <= 0;
            lane4_index <= 0;

            for (int i = 0; i < L1_LEN; i++) l1_pos[i] <= lane1_spawn[i];
            for (int i = 0; i < L2_LEN; i++) l2_pos[i] <= lane2_spawn[i];
            for (int i = 0; i < L3_LEN; i++) l3_pos[i] <= lane3_spawn[i];
            for (int i = 0; i < L4_LEN; i++) l4_pos[i] <= lane4_spawn[i];

            lane0_counter <= 0;
            lane1_counter <= 0;
            lane2_counter <= 0;
            lane3_counter <= 0;

        end else if (enable && step_enable) begin
            // Move blocks left
            for (int i = 0; i < L1_LEN; i++) if (l1_pos[i] > 0) l1_pos[i] <= l1_pos[i] - 1;
            for (int i = 0; i < L2_LEN; i++) if (l2_pos[i] > 0) l2_pos[i] <= l2_pos[i] - 1;
            for (int i = 0; i < L3_LEN; i++) if (l3_pos[i] > 0) l3_pos[i] <= l3_pos[i] - 1;
            for (int i = 0; i < L4_LEN; i++) if (l4_pos[i] > 0) l4_pos[i] <= l4_pos[i] - 1;

            // Spawn pulses at x = 160
            if (lane1_index < L1_LEN && l1_pos[lane1_index] == 160) begin
                pulse[0] <= 1;
                lane1_index <= lane1_index + 1;
            end
            if (lane2_index < L2_LEN && l2_pos[lane2_index] == 160) begin
                pulse[1] <= 1;
                lane2_index <= lane2_index + 1;
            end
            if (lane3_index < L3_LEN && l3_pos[lane3_index] == 160) begin
                pulse[2] <= 1;
                lane3_index <= lane3_index + 1;
            end
            if (lane4_index < L4_LEN && l4_pos[lane4_index] == 160) begin
                pulse[3] <= 1;
                lane4_index <= lane4_index + 1;
            end

            // Reset hit flags
            hit0 = 0; hit1 = 0; hit2 = 0; hit3 = 0;

            // Check for overlaps this tick
            for (int i = 0; i < L4_LEN; i++) if (
                l4_pos[i] <= PLAYER_X && l4_pos[i] + OBSTACLE_WIDTH - 1 >= PLAYER_X &&
                player_y >= LANE0_Y && player_y <= LANE0_Y + OBSTACLE_HEIGHT - 1
            ) hit0 = 1;

            for (int i = 0; i < L3_LEN; i++) if (
                l3_pos[i] <= PLAYER_X && l3_pos[i] + OBSTACLE_WIDTH - 1 >= PLAYER_X &&
                player_y >= LANE1_Y && player_y <= LANE1_Y + OBSTACLE_HEIGHT - 1
            ) hit1 = 1;

            for (int i = 0; i < L2_LEN; i++) if (
                l2_pos[i] <= PLAYER_X && l2_pos[i] + OBSTACLE_WIDTH - 1 >= PLAYER_X &&
                player_y >= LANE2_Y && player_y <= LANE2_Y + OBSTACLE_HEIGHT - 1
            ) hit2 = 1;

            for (int i = 0; i < L1_LEN; i++) if (
                l1_pos[i] <= PLAYER_X && l1_pos[i] + OBSTACLE_WIDTH - 1 >= PLAYER_X &&
                player_y >= LANE3_Y && player_y <= LANE3_Y + OBSTACLE_HEIGHT - 1
            ) hit3 = 1;

            // Update counters (reset if not hit)
            lane0_counter <= hit0 ? lane0_counter + 1 : 0;
            lane1_counter <= hit1 ? lane1_counter + 1 : 0;
            lane2_counter <= hit2 ? lane2_counter + 1 : 0;
            lane3_counter <= hit3 ? lane3_counter + 1 : 0;

            // Trigger collision if sustained 2-tick overlap
            if (lane0_counter >= COLLISION_TICKS_REQUIRED ||
                lane1_counter >= COLLISION_TICKS_REQUIRED ||
                lane2_counter >= COLLISION_TICKS_REQUIRED ||
                lane3_counter >= COLLISION_TICKS_REQUIRED)
                collision_flag <= 1;
        end
    end
endmodule
