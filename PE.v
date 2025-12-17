module PE
(
    input clk,
    input rst_horiz,
    input rst_vert,
    input rst_psum,
    input rst_pe,

    input signed [7:0] a_in,
    input signed [7:0] b_in,

    output signed [ 7:0] horiz_out,
    output signed [ 7:0] vert_out,
    output signed [31:0] psum_out,

    input mac_active
);
    // Input register
    reg signed [ 7:0] horiz_reg; // Data from the horizontal direction
    reg signed [ 7:0] vert_reg;  // Data from the vertical direction
    reg signed [31:0] psum_reg;  // Partial sum

    // Output signal
    assign horiz_out = horiz_reg;
    assign vert_out  = vert_reg;
    assign psum_out  = psum_reg;

    // PE
    always @(posedge clk or posedge rst_pe) begin
        if (rst_pe) begin
            if (rst_horiz) begin
                horiz_reg <= 8'b0;
            end
            if (rst_vert) begin
                vert_reg  <= 8'b0;
            end
            if (rst_psum) begin
                psum_reg  <= 32'b0;
            end
        end else begin
            // Store input
            horiz_reg <= a_in;
            vert_reg  <= b_in;

            // Compute
            if (mac_active) begin
                psum_reg  <= psum_reg + (a_in * b_in);
            end
        end
    end
endmodule