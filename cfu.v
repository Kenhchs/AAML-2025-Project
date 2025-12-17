// Copyright 2021 The CFU-Playground Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
`include "cfu_tpu_wrapper.v"

module Cfu (
  input               cmd_valid,
  output              cmd_ready,
  input      [9:0]    cmd_payload_function_id,
  input      [31:0]   cmd_payload_inputs_0,
  input      [31:0]   cmd_payload_inputs_1,
  output reg          rsp_valid,
  input               rsp_ready,
  output     [31:0]   rsp_payload_outputs_0,
  input               reset,
  input               clk
);
  // FSM states
  localparam IDLE = 3'b000;
  localparam SEND = 3'b001;
  localparam RECV = 3'b010;
  localparam CALC = 3'b011;
  localparam DONE = 3'b100;

  reg [2:0] curr_state, next_state;
  wire [2:0] funct3 = cmd_payload_function_id[2:0];
  wire [6:0] funct7 = cmd_payload_function_id[9:3];
  reg [2:0] funct3_reg;
  reg [6:0] funct7_reg;
  reg [31:0] input0_reg, input1_reg;
  wire calc_busy;
  wire calc_done = !calc_busy;

  wire start = cmd_valid && cmd_ready;
  assign cmd_ready = (curr_state == IDLE);

  // Update state
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      curr_state <= IDLE;
    end else begin
      curr_state <= next_state;
    end
  end

  // FSM
  localparam SEND_A = 3'd0;
  localparam SEND_B = 3'd1;
  localparam RECV_C = 3'd2;
  localparam CALC_C = 3'd3;
  localparam RECV_A_B = 3'd7;
  always @(*) begin
    next_state = curr_state;
    case (curr_state)
      IDLE: begin
        case (start)
          1'd1: begin
            case (funct3)
              SEND_A, SEND_B: begin
                next_state = SEND;
              end
              RECV_C, RECV_A_B: begin
                next_state = RECV;
              end
              CALC_C: begin
                next_state = CALC;
              end
              default: begin
                next_state = IDLE;
              end
            endcase
          end
          default: begin
            next_state = IDLE;
          end
        endcase
      end
      SEND: begin
        next_state = DONE;
      end
      RECV: begin
        next_state = DONE;
      end
      CALC: begin
        if (calc_done) begin
          next_state = DONE;
        end
      end
      DONE: begin
        if (rsp_ready) begin
          next_state = IDLE;
        end
      end
      default: begin
        next_state = IDLE;
      end
    endcase
  end

  // Handshake
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      rsp_valid <= 1'b0;
    end else if (next_state == DONE) begin
      rsp_valid <= 1'b1;
    end else if (rsp_ready) begin
      rsp_valid <= 1'b0;
    end
  end

  // Grab input
  always @(posedge clk) begin
    if (start) begin
      funct3_reg <= cmd_payload_function_id[2:0];
      funct7_reg <= cmd_payload_function_id[9:3];
      input0_reg <= cmd_payload_inputs_0;
      input1_reg <= cmd_payload_inputs_1;
    end
  end

  wire rst_n = ~reset;
  cfu_tpu_wrapper #
  (
    .SIZE(4)
  )
    tpu
  (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(start),
    .funct3(funct3_reg),
    .funct7(funct7_reg),
    .payload_input0(input0_reg),
    .payload_input1(input1_reg),
    .payload_output(rsp_payload_outputs_0),
    .busy(calc_busy)
  );
endmodule