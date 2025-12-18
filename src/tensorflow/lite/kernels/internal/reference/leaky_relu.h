/* Copyright 2020 The TensorFlow Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
==============================================================================*/
#ifndef TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_LEAKY_RELU_H_
#define TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_LEAKY_RELU_H_

#include <algorithm>
#include <limits>

#include "tensorflow/lite/kernels/internal/common.h"
#include "cfu.h"

namespace tflite {
namespace reference_ops {

inline void LeakyRelu(const tflite::LeakyReluParams& params,
                      const RuntimeShape& input_shape, const float* input_data,
                      const RuntimeShape& output_shape, float* output_data) {
  const int flat_size = MatchingFlatSize(input_shape, output_shape);
  for (int i = 0; i < flat_size; ++i) {
    const float val = input_data[i];
    // Note that alpha might be > 1 or < 0, so we don't use std::max here.
    output_data[i] = val > 0 ? val : val * params.alpha;
  }
}

inline uint32_t MultiplyByQuantizedMultiplierSoftware(int32_t input_data_pack,
                                                      int32_t quantized_multiplier_identity,
                                                      int32_t quantized_multiplier_alpha,
                                                      int8_t shift_identity,
                                                      int8_t shift_alpha,
                                                      int8_t input_offset,
                                                      int8_t output_offset) {
  int32_t b, shift;
  uint32_t output_data_pack = 0;

  for (int lane = 0; lane < 4; lane++) {
    int8_t input_lane = (int8_t)((input_data_pack >> (lane * 8)) & 0xFF);
    int32_t input_value = (int32_t)input_lane - input_offset;

    if (input_value >= 0) {
      b = quantized_multiplier_identity;
      shift = shift_identity;
    } else {
      b = quantized_multiplier_alpha;
      shift = shift_alpha;
    }

    int left_shift = shift > 0 ? shift : 0;
    int right_shift = shift > 0 ? 0 : -shift;

    int32_t a = (input_value) * (1 << left_shift);
    bool overflow = a == b && a == std::numeric_limits<std::int32_t>::min();
    int64_t a_64(a);
    int64_t b_64(b);
    int64_t ab_64 = a_64 * b_64;
    int32_t nudge = ab_64 >= 0 ? (1 << 30) : (1 - (1 << 30));
    int32_t ab_x2_high32 = static_cast<std::int32_t>((ab_64 + nudge) / (1ll << 31));
    int32_t mul_res = overflow ? std::numeric_limits<std::int32_t>::max() : ab_x2_high32;

    if (right_shift > 0) {
        int32_t mask = (1 << right_shift) - 1;
        int32_t remainder = mul_res & mask;
        int32_t threshold = (mask >> 1) + ((mul_res < 0) ? 1 : 0);
        mul_res = (mul_res >> right_shift) + ((remainder > threshold) ? 1 : 0);
    }

    static const int32_t quantized_min = std::numeric_limits<int8_t>::min();
    static const int32_t quantized_max = std::numeric_limits<int8_t>::max();
    int32_t unclamped_output = mul_res + output_offset;
    int8_t clamped_output = std::min(quantized_max, std::max(quantized_min, unclamped_output));
    output_data_pack |= ((uint32_t)(uint8_t)clamped_output) << (lane * 8);
  }

  return output_data_pack;
}

template <typename T>
inline void QuantizeLeakyRelu(const LeakyReluParams& params,
                              const RuntimeShape& input_shape,
                              const T* input_data,
                              const RuntimeShape& output_shape,
                              T* output_data) {
  const int flat_size = MatchingFlatSize(input_shape, output_shape);
  static const int32_t quantized_min = std::numeric_limits<T>::min();
  static const int32_t quantized_max = std::numeric_limits<T>::max();
  for (int i = 0; i < flat_size; ++i) {
    const int32_t input_value = input_data[i] - params.input_offset;
    int32_t unclamped_output;
    if (input_value >= 0) {
      unclamped_output = params.output_offset +
                         MultiplyByQuantizedMultiplier(
                             input_value, params.output_multiplier_identity,
                             params.output_shift_identity);
    } else {
      unclamped_output = params.output_offset +
                         MultiplyByQuantizedMultiplier(
                             input_value, params.output_multiplier_alpha,
                             params.output_shift_alpha);
    }
    const T clamped_output =
        std::min(quantized_max, std::max(quantized_min, unclamped_output));
    output_data[i] = static_cast<T>(clamped_output);
  }
}

template <>
inline void QuantizeLeakyRelu(const LeakyReluParams& params,
                              const RuntimeShape& input_shape,
                              const int8_t* __restrict input_data,
                              const RuntimeShape& output_shape,
                              int8_t* __restrict output_data) {
  const int flat_size = input_shape.FlatSize();

  cfu_op4(0, params.output_multiplier_identity, params.output_multiplier_alpha);
  const uint32_t packed_params =
    ((uint32_t)(uint8_t)params.output_shift_identity << 24) |
    ((uint32_t)(uint8_t)params.output_shift_alpha    << 16) |
    ((uint32_t)(uint8_t)params.input_offset          <<  8) |
    ((uint32_t)(uint8_t)params.output_offset              ) ;

  const uint32_t* src_ptr = reinterpret_cast<const uint32_t*>(input_data);
  uint32_t* dst_ptr       = reinterpret_cast<uint32_t*>(output_data);

  int trip_count = (flat_size >> 2);
  int i = 0;

  for (; i < trip_count; ++i) {
    uint32_t in_val = src_ptr[i];
    uint32_t out_val = cfu_op5(0, packed_params, in_val);
    dst_ptr[i] = out_val;
  }
  i <<= 2;

  static const int32_t quantized_min = std::numeric_limits<int8_t>::min();
  static const int32_t quantized_max = std::numeric_limits<int8_t>::max();
  for (; i < flat_size; i++) {
    const int32_t input_value = input_data[i] - params.input_offset;
    int32_t unclamped_output;
    if (input_value >= 0) {
      unclamped_output = params.output_offset +
                         MultiplyByQuantizedMultiplier(
                             input_value, params.output_multiplier_identity,
                             params.output_shift_identity);
    } else {
      unclamped_output = params.output_offset +
                         MultiplyByQuantizedMultiplier(
                             input_value, params.output_multiplier_alpha,
                             params.output_shift_alpha);
    }
    int8_t clamped_output = std::min(quantized_max, std::max(quantized_min, unclamped_output));
    output_data[i] = clamped_output;
  }
}

}  // namespace reference_ops
}  // namespace tflite

#endif  // TENSORFLOW_LITE_KERNELS_INTERNAL_REFERENCE_LEAKY_RELU_H_
