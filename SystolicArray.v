`include "PE.v"

module SystolicArray #
(
    parameter SIZE = 4
)
(
    input clk,
    input rst_n,

    output [SIZE * 32 - 1:0]   C_data_in,

    input signed [SIZE * SIZE * 8 - 1:0] A_buf,
    input signed [SIZE * SIZE * 8 - 1:0] B_buf,
    input       rst_horiz,
    input       rst_vert,
    input       rst_psum,
    input       rst_pe,
    input       mac_active,
    input       output_active,

    input [SIZE - 1: 0] psum_row
);
    // Debug info
    // always @(posedge clk) begin
    //     integer i, j;
    //     // Print A_buf
    //     $display("A_buf:");
    //     for (i = 0; i < SIZE; i = i + 1) begin
    //         for (j = 0; j < SIZE; j = j + 1) begin
    //             $write("%02h ", A_buf[i][j]);
    //         end
    //         $write("\n");
    //     end

    //     // Print B_buf
    //     $display("B_buf:");
    //     for (i = 0; i < SIZE; i = i + 1) begin
    //         for (j = 0; j < SIZE; j = j + 1) begin
    //             $write("%2h ", B_buf[i][j]);
    //         end
    //         $write("\n");
    //     end
    //     $write("\n");

    //     // Print C_buf
    //     $display("psum_buf:");
    //     for (i = 0; i < SIZE; i = i + 1) begin
    //         for (j = 0; j < SIZE; j = j + 1) begin
    //             $write("%8h ", psum_bus[i][j]);
    //         end
    //         $write("\n");
    //     end
    //     $write("=====================================================\n");
    // end

    // Output regsiter
    reg [SIZE * 32 - 1:0] C_data_in_reg;

    // Output signal
    assign C_data_in = C_data_in_reg;

    // PE output
    wire signed [SIZE * (SIZE + 1) * 8 - 1:0] horiz_bus; // extra column for rightmost outputs
    wire signed [(SIZE + 1) * SIZE * 8 - 1:0] vert_bus;  // extra row for bottom outputs
    wire signed [SIZE * SIZE * 32 - 1:0] psum_bus;

    // Systolic array
    generate
        genvar i, j;
        for (i = 0; i < SIZE; i = i + 1) begin: sa_row
            for (j = 0; j < SIZE; j = j + 1) begin: sa_col
                if (i == 0 && j == 0) begin
                    PE pe_inst
                    (
                        .clk(clk),
                        .rst_horiz(rst_horiz),
                        .rst_vert(rst_vert),
                        .rst_psum(rst_psum),
                        .rst_pe(rst_pe),
                        .a_in(A_buf[(i * SIZE + (SIZE - 1)) * 8+:8]),
                        .b_in(B_buf[((SIZE - 1) * SIZE + j) * 8+:8]),
                        .horiz_out(horiz_bus[(i * (SIZE + 1) + j) * 8+:8]),
                        .vert_out(vert_bus[(i * SIZE + j) * 8+:8]),
                        .psum_out(psum_bus[(i * SIZE + j) * 32+:32]),
                        .mac_active(mac_active)
                    );
                end else if (i == 0) begin
                    PE pe_inst
                    (
                        .clk(clk),
                        .rst_horiz(rst_horiz),
                        .rst_vert(rst_vert),
                        .rst_psum(rst_psum),
                        .rst_pe(rst_pe),
                        .a_in((j == 0) ? A_buf[(i * SIZE + (SIZE - 1)) * 8+:8] : horiz_bus[(i * (SIZE + 1) + (j - 1)) * 8+:8]),
                        .b_in(B_buf[((SIZE - 1) * SIZE + j) * 8+:8]),
                        .horiz_out(horiz_bus[(i * (SIZE + 1) + j) * 8+:8]),
                        .vert_out(vert_bus[(i * SIZE + j) * 8+:8]),
                        .psum_out(psum_bus[(i * SIZE + j) * 32+:32]),
                        .mac_active(mac_active)
                    );
                end else if (j == 0) begin
                    PE pe_inst
                    (
                        .clk(clk),
                        .rst_horiz(rst_horiz),
                        .rst_vert(rst_vert),
                        .rst_psum(rst_psum),
                        .rst_pe(rst_pe),
                        .a_in(A_buf[(i * SIZE + (SIZE - 1)) * 8+:8]),
                        .b_in(vert_bus[((i - 1) * SIZE + j) * 8+:8]),
                        .horiz_out(horiz_bus[(i * (SIZE + 1) + j) * 8+:8]),
                        .vert_out(vert_bus[(i * SIZE + j) * 8+:8]),
                        .psum_out(psum_bus[(i * SIZE + j) * 32+:32]),
                        .mac_active(mac_active)
                    );
                end else begin
                    PE pe_inst
                    (
                        .clk(clk),
                        .rst_horiz(rst_horiz),
                        .rst_vert(rst_vert),
                        .rst_psum(rst_psum),
                        .rst_pe(rst_pe),
                        .a_in((j == 0) ? A_buf[(i * SIZE + (SIZE - 1)) * 8+:8] : horiz_bus[(i * (SIZE + 1) + (j - 1)) * 8+:8]),
                        .b_in((i == 0) ? B_buf[((SIZE - 1) * SIZE + j) * 8+:8] : vert_bus[((i - 1) * SIZE + j) * 8+:8]),
                        .horiz_out(horiz_bus[(i * (SIZE + 1) + j) * 8+:8]),
                        .vert_out(vert_bus[(i * SIZE + j) * 8+:8]),
                        .psum_out(psum_bus[(i * SIZE + j) * 32+:32]),
                        .mac_active(mac_active)
                    );
                end
            end
        end
    endgenerate

    // Write the results to matrix C
    always @(*) begin
        if (output_active) begin : write_matrix_c
            integer i;
            for (i = 0; i < SIZE; i = i + 1) begin : row_concat
                C_data_in_reg[(SIZE - i) * 32 - 1 -: 32] = psum_bus[(psum_row * SIZE + i) * 32+:32];
            end
        end else begin
            C_data_in_reg = 128'hDEADBEEFDEADBEEFDEADBEEFDEADBEEF;
        end
    end
endmodule