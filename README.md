## Operations
| Operation | Purpose | funct7 | rs1 | rs2 |
|:---------:|:-------:|:------:|:---:|:---:|
| cfu_op0 | Write matrix A | 0b0xxxxxx | A_index (12 bits) | {int8, int8, int8, int8} |
| cfu_op1 | Write matrix B | 0b1xxxxxx | B_index (12 bits) | {int8, int8, int8, int8} |
| cfu_op2 | Read  matrix C |  | C_index (12bits) | which 32-bit slice<sup>1</sup> |
| cfu_op3 | Matrix multiplication |  | {M, N} (16 bits each) | {don't care, K (16 bits)} |
| cfu_op4 | Set Leaky ReLU quantized multiplier |  | quantized_multiplier_identity | quantized_multiplier_alpha |
| cfu_op5 | Calculate Leaky ReLU |  | {shift_identity, shift_alpha, input_offset, output_offset} (8 bits each) | input_data_pack |
| cfu_op6 |  |  |  |  |
| cfu_op7 | Read matrix A or B | 0b{0=A, 1=B}xxxxxx | index (12 bits) | which 32-bit slice<sup>1</sup> |

> [!IMPORTANT]
> <sup>1</sup> A slice is counted from the most significant bits (32 bits per slice). For example, if the data at C_index is [0x0123456789ABC145], slice 0 contains [0x01234567], and slice 1 contains [0x89ABC145].
