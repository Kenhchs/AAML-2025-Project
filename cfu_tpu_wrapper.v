`include "TPU.v"
`include "global_buffer_bram.v"

module cfu_tpu_wrapper #
(
    parameter SIZE = 4
)
(
    input clk,
    input rst_n,
    input in_valid,
    input  [ 2:0] funct3,
    input  [ 6:0] funct7,
    input  [31:0] payload_input0,
    input  [31:0] payload_input1,
    output [31:0] payload_output,
    output busy
);
    reg [31:0] payload_output_reg;
    assign payload_output = payload_output_reg;
    wire [31:0] slice = payload_input1;
    always @(*) begin
        payload_output_reg = 32'hDDDDFFFF;
        case (funct3)
            3'b010: begin // Matrix C
                payload_output_reg = C_data_out[(SIZE - 1 - slice) * 32+:32];
            end
            3'b111: begin // Matrix A or B
                case (funct7[6])
                    1'b0: begin
                        payload_output_reg = A_data_out;
                    end
                    1'b1: begin
                        payload_output_reg = B_data_out;
                    end
                    default: begin
                        payload_output_reg = 32'hABCDEF01;
                    end
                endcase
            end
            default: begin
                payload_output_reg = 32'hDDDDFFFF;
            end
        endcase
    end

    // 32'hxxxx{M}{N}{K}
    wire [7:0] K = payload_input0[7:0];
    wire [7:0] N = payload_input0[15:8];
    wire [7:0] M = payload_input0[23:16];

    wire [11:0] write_A_B_index         = payload_input0[15:0];
    wire [SIZE * 8 - 1:0] write_A_B_val = payload_input1; // Need config if size not 4
    wire [11:0] read_A_B_index          = payload_input0[15:0];
    wire [11:0] read_C_index            = payload_input0[15:0];

    TPU #
    (
        .SIZE(SIZE)
    )
        tpu
    (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .K(K),
        .M(M),
        .N(N),
        .busy(busy),
        .A_wr_en(A_wr_en),
        .A_index(A_index),
        .A_data_out(A_data_out),
        .B_wr_en(B_wr_en),
        .B_index(B_index),
        .B_data_out(B_data_out),
        .C_wr_en(C_wr_en),
        .C_index(C_index),
        .C_data_in(C_data_in),
        .C_data_out(C_data_out),
        .funct3(funct3),
        .funct7(funct7),
        .payload_input0(payload_input0),
        .payload_input1(payload_input1),
        .write_A_B_index(write_A_B_index),
        .read_A_B_index(read_A_B_index),
        .read_C_index(read_A_B_index)
    );

    wire                   A_wr_en;
    wire [15:0]            A_index;
    wire [SIZE * 8 - 1:0]  A_data_in = write_A_B_val;
    wire [SIZE * 8 - 1:0]  A_data_out;
    wire                   B_wr_en;
    wire [15:0]            B_index;
    wire [SIZE * 8 - 1:0]  B_data_in = write_A_B_val;
    wire [SIZE * 8 - 1:0]  B_data_out;
    wire                   C_wr_en;
    wire [15:0]            C_index;
    wire [SIZE * 32 - 1:0] C_data_in;
    wire [SIZE * 32 - 1:0] C_data_out;

    global_buffer_bram #
    (
        .ADDR_BITS(12),
        .DATA_BITS(SIZE * 8)
    )
    gbuff_A
    (
        .clk(clk),
        .rst_n(1'b1),
        .ram_en(1'b1),
        .wr_en(A_wr_en),
        .index(A_index),
        .data_in(A_data_in),
        .data_out(A_data_out)
    );

    global_buffer_bram #
    (
        .ADDR_BITS(12),
        .DATA_BITS(SIZE * 8)
    )
    gbuff_B
    (
        .clk(clk),
        .rst_n(1'b1),
        .ram_en(1'b1),
        .wr_en(B_wr_en),
        .index(B_index),
        .data_in(B_data_in),
        .data_out(B_data_out)
    );

    global_buffer_bram #
    (
        .ADDR_BITS(12),
        .DATA_BITS(SIZE * 32)
    )
    gbuff_C
    (
        .clk(clk),
        .rst_n(1'b1),
        .ram_en(1'b1),
        .wr_en(C_wr_en),
        .index(C_index),
        .data_in(C_data_in),
        .data_out(C_data_out)
    );
endmodule