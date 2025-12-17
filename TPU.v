`include "Ctrl.v"
`include "DataLoader.v"
`include "SystolicArray.v"

module TPU #
(
    parameter SIZE = 4
)
(
    input clk,
    input rst_n,
    input            in_valid,
    input [7:0]      K,
    input [7:0]      M,
    input [7:0]      N,
    output           busy,

    output                  A_wr_en,
    output [15:0]           A_index,
    input  [SIZE * 8 - 1:0] A_data_out,

    output                  B_wr_en,
    output [15:0]           B_index,
    input  [SIZE * 8 - 1:0] B_data_out,

    output                   C_wr_en,
    output [15:0]            C_index,
    output [SIZE * 32 - 1:0] C_data_in,
    input  [SIZE * 32 - 1:0] C_data_out,

    input  [ 2:0] funct3,
    input  [ 6:0] funct7,
    input  [31:0] payload_input0,
    input  [31:0] payload_input1,
    input  [15:0] write_A_B_index,
    input  [15:0] read_A_B_index,
    input  [15:0] read_C_index
);
    wire signed [SIZE * SIZE * 8 - 1:0] A_buf;
    wire signed [SIZE * SIZE * 8 - 1:0] B_buf;
    wire rst_horiz;
    wire rst_vert;
    wire rst_psum;
    wire rst_pe;
    wire load_active;
    wire mac_active;
    wire output_active;
    wire [SIZE - 1:0] psum_row;

    Ctrl #
    (
        .SIZE(SIZE)
    )
        ctrl
    (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .K(K),
        .M(M),
        .N(N),
        .funct3(funct3),
        .funct7(funct7),
        .write_A_B_index(write_A_B_index),
        .read_A_B_index(read_A_B_index),
        .read_C_index(read_C_index),
        .busy(busy),
        .A_wr_en(A_wr_en),
        .A_index(A_index),
        .B_wr_en(B_wr_en),
        .B_index(B_index),
        .C_wr_en(C_wr_en),
        .C_index(C_index),
        .rst_horiz(rst_horiz),
        .rst_vert(rst_vert),
        .rst_psum(rst_psum),
        .rst_pe(rst_pe),
        .mac_active(mac_active),
        .load_active(load_active),
        .output_active(output_active),
        .psum_row(psum_row)
    );

    DataLoader #
    (
        .SIZE(SIZE)
    )
        DL
    (
        .clk(clk),
        .rst_n(rst_n),
        .A_data_out(A_data_out),
        .B_data_out(B_data_out),
        .A_buf(A_buf),
        .B_buf(B_buf),
        .load_active(load_active)
    );

    SystolicArray #
    (
        .SIZE(SIZE)
    )
        SA
    (
        .clk(clk),
        .rst_n(rst_n),
        .C_data_in(C_data_in),
        .A_buf(A_buf),
        .B_buf(B_buf),
        .rst_horiz(rst_horiz),
        .rst_vert(rst_vert),
        .rst_psum(rst_psum),
        .rst_pe(rst_pe),
        .mac_active(mac_active),
        .output_active(output_active),
        .psum_row(psum_row)
    );
endmodule