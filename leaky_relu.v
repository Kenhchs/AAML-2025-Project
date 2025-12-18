module leaky_relu (
    input  wire [31:0] input_data_pack,
    input  wire [31:0] quantized_multiplier_identity,
    input  wire [31:0] quantized_multiplier_alpha,
    input  wire [ 7:0] shift_identity,
    input  wire [ 7:0] shift_alpha,
    input  wire [ 7:0] input_offset,
    input  wire [ 7:0] output_offset,
    output wire [31:0] output_data_pack,
    output wire busy
);
    assign busy = 0;

    wire [7:0] lane_out [0:3];

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : lanes
            leaky_relu_lane u_lane (
                .input_val   (input_data_pack[i*8 +: 8]),
                .q_mul_id    (quantized_multiplier_identity),
                .q_mul_alpha (quantized_multiplier_alpha),
                .shift_id    (shift_identity),
                .shift_alpha (shift_alpha),
                .in_offset   (input_offset),
                .out_offset  (output_offset),
                .result      (lane_out[i])
            );
        end
    endgenerate

    assign output_data_pack = {lane_out[3], lane_out[2], lane_out[1], lane_out[0]};

endmodule

module leaky_relu_lane (
    input  wire [ 7:0] input_val,
    input  wire [31:0] q_mul_id,
    input  wire [31:0] q_mul_alpha,
    input  wire [ 7:0] shift_id,
    input  wire [ 7:0] shift_alpha,
    input  wire [ 7:0] in_offset,
    input  wire [ 7:0] out_offset,
    output wire [ 7:0] result
);

    // 1. Unpacking and Offset
    wire signed [31:0] input_val_32 = $signed({{24{input_val[7]}}, input_val});
    wire signed [31:0] in_offset_32 = $signed({{24{in_offset[7]}}, in_offset});
    wire signed [31:0] input_value;
    assign input_value = input_val_32 - in_offset_32;

    // 2. Parameter Selection
    reg signed [31:0] b;
    reg signed [ 7:0] shift;

    always @(*) begin
        if (input_value >= 0) begin
            b = q_mul_id;
            shift = shift_id;
        end else begin
            b = q_mul_alpha;
            shift = shift_alpha;
        end
    end

    // 3. Shift Setup
    wire signed [31:0] shift_32 = {{24{shift[7]}}, shift};
    wire signed [31:0] left_shift;
    wire signed [31:0] right_shift;
    
    assign left_shift  = (shift_32 > 0) ? shift_32 : 32'sd0;
    assign right_shift = (shift_32 > 0) ? 32'sd0   : -shift_32;

    // 4. Pre-multiplication Shift
    wire signed [31:0] a;
    assign a = input_value <<< left_shift;

    // 5. Overflow Check
    wire overflow;
    assign overflow = (a == b) && (a == 32'h80000000);

    // 6. 64-bit Multiplication
    wire signed [63:0] a_64 = {{32{a[31]}}, a};
    wire signed [63:0] b_64 = {{32{b[31]}}, b};
    wire signed [63:0] ab_64;
    assign ab_64 = a_64 * b_64;

    // 7. Nudge and High 32 Calculation
    wire signed [63:0] nudge;
    assign nudge = (ab_64 >= 0) ? 64'h40000000 : (64'd1 - 64'h40000000);

    wire signed [63:0] numerator;
    assign numerator = ab_64 + nudge;

    reg signed [31:0] ab_x2_high32;
    
    wire signed [63:0] num_shifted = numerator >>> 31;
    wire signed [63:0] neg_num_shifted = (-numerator) >>> 31;

    always @(*) begin
        if (numerator >= 0) begin
            ab_x2_high32 = num_shifted[31:0];
        end else begin
            // Emulate truncation toward zero for negative division
            ab_x2_high32 = -neg_num_shifted[31:0];
        end
    end

    // 8. Result Mux
    reg signed [31:0] mul_res;
    always @(*) begin
        if (overflow)
            mul_res = 32'h7FFFFFFF; // INT32_MAX
        else
            mul_res = ab_x2_high32;
    end

    // 9. Right Shift and Rounding
    reg signed [31:0] final_mul_res;
    reg [31:0] mask;
    reg [31:0] remainder;
    reg [31:0] threshold;
    reg remainder_gt_threshold;

    always @(*) begin
        // Default assignments to prevent latch inference
        final_mul_res = mul_res; 
        mask = 0;
        remainder = 0;
        threshold = 0;
        remainder_gt_threshold = 0;

        if (right_shift > 0) begin
            mask = (1 << right_shift) - 1;
            remainder = final_mul_res & mask;
            
            threshold = (mask >> 1) + ((final_mul_res < 0) ? 1 : 0);
            
            remainder_gt_threshold = (remainder > threshold);
            
            final_mul_res = (final_mul_res >>> right_shift) + (remainder_gt_threshold ? 1 : 0);
        end
    end

    // 10. Output Clamping
    wire signed [31:0] out_offset_32 = {{24{out_offset[7]}}, out_offset};
    wire signed [31:0] unclamped_output;
    assign unclamped_output = final_mul_res + out_offset_32;

    reg signed [7:0] clamped_output;
    always @(*) begin
        if (unclamped_output > 127)
            clamped_output = 127;
        else if (unclamped_output < -128)
            clamped_output = -128;
        else
            clamped_output = unclamped_output[7:0];
    end

    assign result = clamped_output;

endmodule
