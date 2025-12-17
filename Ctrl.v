module Ctrl #
(
    parameter SIZE = 4
)
(
    input         clk,
    input         rst_n,
    input         in_valid,
    input  [ 7:0] K,
    input  [ 7:0] M,
    input  [ 7:0] N,
    input  [ 2:0] funct3,
    input  [ 6:0] funct7,
    input  [11:0] write_A_B_index,
    input  [11:0] read_A_B_index,
    input  [11:0] read_C_index,
    output        busy,
    output        A_wr_en,
    output reg [11:0] A_index,
    output        B_wr_en,
    output reg [11:0] B_index,
    output        C_wr_en,
    output [11:0] C_index,
    output        rst_horiz,
    output        rst_vert,
    output        rst_psum,
    output        rst_pe,
    output        mac_active,
    output        load_active,
    output        output_active,
    output [SIZE - 1: 0] psum_row
);
    // FSM definition
    localparam IDLE       = 3'b000;
    localparam LOAD       = 3'b001;
    localparam LOAD_MAC   = 3'b010;
    localparam MAC        = 3'b011;
    localparam MAC_OUTPUT = 3'b100;
    localparam OUTPUT     = 3'b101;
    localparam SEND       = 3'b110;
    localparam RECV       = 3'b111;

    // Input register
    reg [11:0] A_index_reg;
    reg [11:0] B_index_reg;
    reg [11:0] C_index_reg;

    // Output register
    reg load_active_reg;
    reg mac_active_reg;
    reg output_active_reg;
    reg C_wr_en_reg;
    reg rst_horiz_reg;
    reg rst_vert_reg;
    reg rst_psum_reg;
    reg busy_reg;
    reg [SIZE - 1:0] psum_row_reg; // Holds the psum row counter

    // Output signal
    wire write_A = (funct3 == 3'b000 && funct7[6] == 1'b0);
    wire read_A  = (funct3 == 3'b111 && funct7[6] == 1'b0);
    assign A_wr_en = (funct3 == 3'b000 && write_A) ? 1 : 0;
    wire read_B  = (funct3 == 3'b111 && funct7[6] == 1'b1);
    wire write_B = (funct3 == 3'b001 && funct7[6] == 1'b1);
    assign B_wr_en = (funct3 == 3'b001 && write_B) ? 1 : 0;
    wire read_C = (funct3 == 3'b010);
    assign C_index = (read_C) ? read_C_index : C_index_reg;
    assign C_wr_en = (read_C) ? 0 :  C_wr_en_reg;
    assign rst_horiz = rst_horiz_reg;
    assign rst_vert = rst_vert_reg;
    assign rst_psum = rst_psum_reg;
    assign rst_pe = !rst_n || rst_horiz || rst_vert || rst_psum || in_valid;
    assign busy = busy_reg;
    assign mac_active = mac_active_reg;
    assign load_active = load_active_reg;
    assign output_active = output_active_reg;
    assign psum_row = psum_row_reg;

    always @(*) begin
        A_index = A_index_reg;
        if (A_wr_en) begin
            A_index = write_A_B_index;
        end else begin
            if (read_A) begin
                A_index = read_A_B_index;
            end else begin
                A_index = A_index_reg;
            end
        end
    end

    always @(*) begin
        B_index = B_index_reg;
        if (B_wr_en) begin
            B_index = write_A_B_index;
        end else begin
            if (read_B) begin
                B_index = read_A_B_index;
            end else begin
                B_index = B_index_reg;
            end
        end
    end

    // Iteration index
    wire [7:0] i_tile_index = i_tile_index_reg;
    wire [7:0] M_tile_index = M_tile_index_reg;
    wire [7:0] N_tile_index = N_tile_index_reg;

    // Number of tiles and remainder
    wire [7:0] M_tiles = (M + SIZE - 1) / SIZE;
    wire [7:0] K_tiles = (K + SIZE - 1) / SIZE;
    wire [7:0] N_tiles = (N + SIZE - 1) / SIZE;;
    wire [7:0] M_rem   = M % SIZE;
    wire [7:0] K_rem   = K % SIZE;

    // Finish computation
    reg i_tile_done;
    reg all_tile_done;

    // Cycle counter
    // reg [$clog2(3 * SIZE):0] cycles;
    reg [5:0] cycles;

    // Current state and next states
    reg [2:0] curr_state, next_state;

    // FSM state thresholds
    // localparam LOAD_THRESHOLD       = 0;
    // localparam LOAD_MAC_THRESHOLD   = SIZE - 1;
    // localparam MAC_THRESHOLD        = LOAD_MAC_THRESHOLD + SIZE;  // 2 * SIZE - 1
    // localparam MAC_OUTPUT_THRESHOLD = MAC_THRESHOLD + (SIZE - 1); // 3 * SIZE - 2
    // localparam OUTPUT_THRESHOLD     = MAC_OUTPUT_THRESHOLD + 1;   // 3 * SIZE - 1
    reg [5:0] LOAD_THRESHOLD       = 0;
    reg [5:0] LOAD_MAC_THRESHOLD   = SIZE - 1;
    reg [5:0] MAC_THRESHOLD        = 2 * SIZE - 1;
    reg [5:0] MAC_OUTPUT_THRESHOLD = 3 * SIZE - 2;
    reg [5:0] OUTPUT_THRESHOLD     = 3 * SIZE - 1;

    // Update cycle counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycles <= 0;
        end else if (next_state == LOAD) begin
            cycles <= 0;
        end else begin
            cycles <= cycles + 1;
        end
    end

    // Update current state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= IDLE;
        end else begin
            curr_state <= next_state;
        end
    end

    // Update next state
    always @(*) begin
        if (in_valid) begin
            next_state = IDLE;
        end else begin
            next_state = curr_state;
            case (curr_state)
                IDLE: begin
                    if (write_A || write_B) begin
                        next_state = SEND;
                    end else if (read_A || read_B || read_C) begin
                        next_state = RECV;
                    end else if (in_valid || !i_tile_done || !all_tile_done) begin
                        next_state = LOAD;
                    end else begin
                        next_state = IDLE;
                    end
                end
                SEND: begin
                    next_state = IDLE;
                end
                RECV: begin
                    next_state = IDLE;
                end
                LOAD: begin
                    if (cycles >= LOAD_THRESHOLD) begin
                        next_state = LOAD_MAC;
                    end else begin
                        next_state = LOAD;
                    end
                end
                LOAD_MAC: begin
                    if (cycles >= LOAD_MAC_THRESHOLD) begin
                        next_state = MAC;
                    end else begin
                        next_state = LOAD_MAC;
                    end
                end
                MAC: begin
                    if (i_tile_index < K_tiles - 1) begin
                        if (cycles < MAC_OUTPUT_THRESHOLD) begin
                            next_state = MAC;
                        end else begin
                            next_state = LOAD;
                        end
                    end else begin
                        if (cycles < MAC_THRESHOLD) begin
                            next_state = MAC;
                        end else begin
                            next_state = MAC_OUTPUT;
                        end
                    end
                end
                MAC_OUTPUT: begin
                    if (cycles >= MAC_OUTPUT_THRESHOLD) begin
                        next_state = OUTPUT;
                    end else begin
                        next_state = MAC_OUTPUT;
                    end
                end
                OUTPUT: begin
                    if (cycles >= OUTPUT_THRESHOLD) begin
                        next_state = IDLE;
                    end else begin
                        next_state = OUTPUT;
                    end
                end
                default: next_state = IDLE;
            endcase
        end
    end

    // Update busy signal
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_reg <= 0;
        end else begin
            if (all_tile_done && next_state == IDLE) begin
                busy_reg <= 0;
            end else begin
                busy_reg <= 1;
            end
        end
    end

    // Update reset signal
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_horiz_reg <= 1;
            rst_vert_reg  <= 1;
            rst_psum_reg  <= 1;
        end else begin
            if (next_state == LOAD) begin
                rst_horiz_reg <= 1;
                rst_vert_reg  <= 1;
            end else if (next_state == IDLE) begin
                rst_psum_reg <= 1;
            end else begin
                rst_horiz_reg <= 0;
                rst_vert_reg  <= 0;
                rst_psum_reg  <= 0;
            end
        end
    end

    // Update the active states for load, MAC computation, and output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_active_reg   <= 0;
            mac_active_reg    <= 0;
            output_active_reg <= 0;
        end else begin
            case (curr_state)
                IDLE: begin
                    if (next_state == LOAD) begin
                        load_active_reg <= 1;
                    end
                end
                LOAD: begin
                    if (cycles >= LOAD_THRESHOLD) begin
                        mac_active_reg <= 1;
                    end
                    // Prevent reading extra data
                    if (i_tile_index == K_tiles - 1 && cycles == K_rem - 1) begin
                        load_active_reg <= 0;
                    end
                end
                LOAD_MAC: begin
                    if (cycles >= LOAD_MAC_THRESHOLD) begin
                        load_active_reg <= 0;
                    end
                    // Prevent reading extra data
                    if (i_tile_index == K_tiles - 1 && cycles == K_rem - 1) begin
                        load_active_reg <= 0;
                    end
                end
                MAC: begin
                    if (next_state == MAC_OUTPUT) begin
                        output_active_reg <= 1;
                    end else if (next_state == LOAD) begin
                        load_active_reg <= 1;
                        mac_active_reg <= 0;
                    end
                end
                MAC_OUTPUT: begin
                    if (cycles >= MAC_OUTPUT_THRESHOLD) begin
                        mac_active_reg <= 0;
                    end

                    // Prevent overwriting data
                    if (i_tile_index == K_tiles - 1 &&
                        M_tile_index == M_tiles - 1 &&
                        cycles       == OUTPUT_THRESHOLD - (SIZE - M_rem)) begin
                        output_active_reg <= 0;
                    end
                end
                OUTPUT: begin
                    if (cycles >= OUTPUT_THRESHOLD) begin
                        output_active_reg <= 0;
                    end
                end
                default: begin
                    load_active_reg   <= 0;
                    mac_active_reg    <= 0;
                    output_active_reg <= 0;
                end
           endcase
        end
    end

    // Update i_tile_index for each partial sum iteration
    reg [7:0] i_tile_index_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_tile_index_reg <= 8'b0;
            i_tile_done      <= 1;
        end else begin
            if (next_state == LOAD) begin
                if (curr_state == IDLE) begin
                    i_tile_index_reg <= 8'b0;
                    i_tile_done      <= 0;
                end else if (curr_state == MAC) begin
                    i_tile_index_reg <= i_tile_index_reg + 1;
                    i_tile_done      <= 0;
                end
            end else if (next_state == IDLE) begin
                i_tile_index_reg <= 8'b0;
                i_tile_done      <= 1;
            end else begin
                i_tile_index_reg <= i_tile_index_reg;
                i_tile_done      <= 0;
            end
        end
    end

    // Update A matrix index
    wire [7:0] i_tile_index_next = (curr_state == MAC) ? i_tile_index + 1
                                                       : i_tile_index + 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_index_reg  <= 16'b0;
        end else begin
            if (next_state == LOAD) begin
                if (K_rem == 8'b0) begin
                    A_index_reg <= K_tiles * SIZE * M_tile_index + (i_tile_index_next) * SIZE;
                end else begin
                    A_index_reg <= K_tiles * SIZE * M_tile_index + (i_tile_index_next) * SIZE - (SIZE - K_rem) * M_tile_index;
                end
            end else if(next_state == LOAD_MAC) begin
                A_index_reg <= A_index_reg + 1;
            end else begin
                A_index_reg <= A_index_reg;
            end
        end
    end

    // Update B matrix index
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            B_index_reg  <= 16'b0;
        end else begin
            if (next_state == LOAD) begin
                if (K_rem == 8'b0) begin
                    B_index_reg <= K_tiles * SIZE * N_tile_index + (i_tile_index_next) * SIZE;
                end else begin
                    B_index_reg <= K_tiles * SIZE * N_tile_index + (i_tile_index_next) * SIZE - (SIZE - K_rem) * N_tile_index;
                end
            end else if (next_state == LOAD_MAC) begin
                B_index_reg <= B_index_reg + 1;
            end else begin
                B_index_reg <= B_index_reg;
            end
        end
    end

    // Update C matrix index
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            C_index_reg  <= 16'b0;
            C_wr_en_reg  <= 0;
        end else begin
            if (curr_state == MAC && next_state == MAC_OUTPUT) begin
                C_wr_en_reg <= 1;
                if (M_rem == 8'b0) begin
                    C_index_reg <= M_tiles * SIZE * N_tile_index + M_tile_index * SIZE;
                end else begin
                    C_index_reg <= M_tiles * SIZE * N_tile_index + M_tile_index * SIZE - (SIZE - M_rem) * N_tile_index;
                end
            end else if (next_state == MAC_OUTPUT || next_state == OUTPUT) begin
                C_index_reg <= C_index_reg + 1;
            end else begin
                C_wr_en_reg <= 0;
            end

            // Prevent overwriting data
            if (curr_state   == MAC_OUTPUT &&
                i_tile_index == K_tiles - 1 &&
                M_tile_index == M_tiles - 1 &&
                cycles       == OUTPUT_THRESHOLD - (SIZE - M_rem)) begin
                C_wr_en_reg <= 0;
            end
        end
    end

    // Update PE partial sum row index
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psum_row_reg <= {SIZE{1'b0}};
        end else begin
            if (curr_state == MAC && next_state == MAC_OUTPUT) begin
                psum_row_reg <= {SIZE{1'b0}};
            end else if (next_state == MAC_OUTPUT || next_state == OUTPUT) begin
                psum_row_reg <= psum_row_reg + 1;
            end else begin
                psum_row_reg <= {SIZE{1'b0}};
            end
        end
    end

    // Update C matrix tile index
    reg [7:0] M_tile_index_reg, N_tile_index_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_tile_index_reg <= 8'b0;
            N_tile_index_reg <= 8'b0;
            all_tile_done    <= 1;
        end else if (in_valid && next_state == IDLE) begin
            M_tile_index_reg <= 8'b0;
            N_tile_index_reg <= 8'b0;
            all_tile_done    <= 0;
        end else begin
            if (next_state == IDLE) begin
                if (curr_state == IDLE) begin
                    M_tile_index_reg <= 8'b0;
                    N_tile_index_reg <= 8'b0;
                    all_tile_done    <= 1;
                end else begin
                    if (N_tile_index < N_tiles - 1) begin
                        N_tile_index_reg <= N_tile_index_reg + 1;
                        all_tile_done    <= 0;
                    end else begin
                        if (M_tile_index_reg != M_tiles - 1) begin
                            M_tile_index_reg <= M_tile_index_reg + 1;
                            N_tile_index_reg <= 8'b0;
                            all_tile_done    <= 0;
                        end else begin
                            all_tile_done <= 1;
                        end
                    end
                end
            end else begin
                all_tile_done <= 0;
            end
        end
    end
endmodule