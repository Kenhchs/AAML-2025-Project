module DataLoader #
(
    parameter SIZE = 4
)
(
    input clk,
    input rst_n,
    input [SIZE * 8 - 1:0] A_data_out,
    input [SIZE * 8 - 1:0] B_data_out,
    output signed [SIZE * SIZE * 8 - 1:0] A_buf,
    output signed [SIZE * SIZE * 8 - 1:0] B_buf,
    input load_active
);
    // Output signal
    assign A_buf = A_buf_reg;
    assign B_buf = B_buf_reg;

    // Matrix buffer
    reg signed [SIZE * SIZE * 8 - 1:0] A_buf_reg;
    reg signed [SIZE * SIZE * 8 - 1:0] B_buf_reg;

    // Shift A buffer right and fetch new input data
    always @(posedge clk or negedge rst_n) begin : A_buf_proc
        integer i, j;
        if (!rst_n) begin
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    A_buf_reg[(i * SIZE + j) * 8+:8] <= 8'd0;
                end
            end
        end else begin
            // Shift A buffer right
            for (i = 1; i < SIZE; i = i + 1) begin
                for (j = SIZE - i; j < SIZE; j = j + 1) begin
                    A_buf_reg[(i * SIZE + j) * 8+:8] <= A_buf_reg[(i * SIZE + (j - 1)) * 8+:8];
                end
            end

            // Fetch new input data
            for (i = 0; i < SIZE; i = i + 1) begin
                if (load_active) begin
                    A_buf_reg[(i * SIZE + (SIZE - 1 - i)) * 8+:8] <= A_data_out[SIZE * 8 - 1 - (i * 8) -: 8];
                end else begin
                    A_buf_reg[(i * SIZE + (SIZE - 1 - i)) * 8+:8] <= 8'b0;
                end
            end
        end
    end

    // Shift B buffer down and fetch new input data
    always @(posedge clk or negedge rst_n) begin : B_buf_proc
        integer i, j;
        if (!rst_n) begin
            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    B_buf_reg[(i * SIZE + j) * 8+:8] <= 8'd0;
                end
            end
        end else begin
            // Shift B buffer down
            for (i = 1; i < SIZE; i = i + 1) begin
                for (j = SIZE - i; j < SIZE; j = j + 1) begin
                    B_buf_reg[(i * SIZE + j) * 8+:8] <= B_buf_reg[((i - 1) * SIZE + j) * 8+:8];
                end
            end

            // Fetch new input data
            for (i = 0; i < SIZE; i = i + 1) begin
                if (load_active) begin
                    B_buf_reg[(i * SIZE + (SIZE - 1 - i)) * 8+:8] <= B_data_out[(i + 1) * 8 - 1 -: 8];
                end else begin
                    B_buf_reg[(i * SIZE + (SIZE - 1 - i)) * 8+:8] <= 8'b0;
                end
            end
        end
    end
endmodule