/* ******************************************************************************
 *
 *
 * This program and the accompanying materials are made available under the
 * terms of the Apache License, Version 2.0 which is available at
 * https://www.apache.org/licenses/LICENSE-2.0.
 *
 *  See the NOTICE file distributed with this work for additional
 *  information regarding copyright ownership.
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations
 * under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 ******************************************************************************/

//
// @author raver119@gmail.com
//
#include <helpers/DebugHelper.h>
#include <loops/legacy_ops.h>
#include <loops/transform_any.h>
#include <system/Environment.h>
#include <system/op_boilerplate.h>
#include <types/types.h>

using namespace simdOps;

template <typename X, typename Z, typename OpType>
SD_KERNEL void transformAnySimple(const void *x, const sd::LongType *xShapeInfo,sd::LongType xRank, void *params, void *z,
                                  const sd::LongType *zShapeInfo, sd::LongType zRank,
                                  sd::LongType *allocationPointer,
                                  void *reductionPointer, const sd::LongType *tadShapeInfo,
                                  const sd::LongType *tadOffsets) {
  functions::transform::TransformAny<X, Z>::template transformCuda<OpType>(
      x, xShapeInfo, params, z, zShapeInfo, allocationPointer, reductionPointer, tadShapeInfo, tadOffsets);
}

namespace functions {
namespace transform {

template <typename X, typename Y>
SD_HOST void TransformAny<X, Y>::executeTransformShaped(dim3 launchDims, cudaStream_t *stream, const int opNum,
                                                        const void *x, const sd::LongType *xShape, sd::LongType xRank,
                                                        void *extraParams, void *z, const sd::LongType *zShape,
                                                        sd::LongType zRank, sd::LongType *allocationPointer, void *reductionPointer,
                                                        const sd::LongType *tadShapeInfo,
                                                        const sd::LongType *tadOffsets) {
  DISPATCH_BY_OPNUM_TT(intermediateShaped,
                       PARAMS(launchDims, stream, x, xShape, xRank, extraParams, z, zShape, zRank, allocationPointer,
                              reductionPointer, tadShapeInfo, tadOffsets),
                       TRANSFORM_ANY_OPS);

  DEBUG_KERNEL(stream, opNum);
}

template <typename X, typename Z>
template <typename OpType>
SD_DEVICE void TransformAny<X, Z>::transformCuda(const void *vx, const sd::LongType *xShapeInfo, void *vparams,
                                                 void *vz, const sd::LongType *zShapeInfo,
                                                 sd::LongType *allocationPointer,
                                                 void *vreductionPointer, const sd::LongType *tadShapeInfo,
                                                 const sd::LongType *tadOffsets) {
  auto x = reinterpret_cast<const X *>(vx);
  auto z = reinterpret_cast<Z *>(vz);
  auto params = reinterpret_cast<X *>(vparams);
  auto reductionPointer = reinterpret_cast<Z *>(vreductionPointer);

  __shared__ sd::LongType xEws;
  __shared__ sd::LongType zEws;
  __shared__ char xOrder;
  __shared__ char zOrder;
  __shared__ sd::LongType length;

  if (threadIdx.x == 0) {
    xEws = shape::elementWiseStride(xShapeInfo);
    zEws = shape::elementWiseStride(zShapeInfo);
    xOrder = shape::order(xShapeInfo);
    zOrder = shape::order(zShapeInfo);
    length = shape::length(xShapeInfo);
  }
  __syncthreads();

  auto tid = blockIdx.x * blockDim.x + threadIdx.x;
  int totalThreads = gridDim.x * blockDim.x;

  if (xEws > 0 && zEws > 0 && xOrder == zOrder && xOrder == 'c') {
    for (int i = tid; i < length; i += totalThreads) z[i * zEws] = OpType::op(x[i * xEws], params);
  } else {
    if (vx == vz) {
      for (sd::LongType i = tid; i < length; i += totalThreads) {
        auto xOffset = shape::getIndexOffset(i, xShapeInfo);
        z[xOffset] = OpType::op(x[xOffset], params);
      }
    } else {
      for (sd::LongType i = tid; i < length; i += totalThreads) {
        auto xOffset = shape::getIndexOffset(i, xShapeInfo);
        auto zOffset = shape::getIndexOffset(i, zShapeInfo);
        z[zOffset] = OpType::op(x[xOffset], params);
      }
    }
  }
};

template <typename X, typename Z>
template <typename OpType>
SD_HOST void TransformAny<X, Z>::intermediateShaped(dim3 launchDims, cudaStream_t *stream, const void *x,
                                                    const sd::LongType *xShape, sd::LongType xRank, void *extraParams, void *z,
                                                    const sd::LongType *zShape, sd::LongType zRank,
                                                    sd::LongType *allocationPointer,
                                                    void *reductionPointer, const sd::LongType *tadShapeInfo,
                                                    const sd::LongType *tadOffsets) {
  transformAnySimple<X, Z, OpType><<<launchDims.x, launchDims.y, launchDims.z, *stream>>>(
      x, xShape, xRank, extraParams, z, zShape, zRank, allocationPointer, reductionPointer, tadShapeInfo, tadOffsets);

  sd::DebugHelper::checkErrorCode(stream, "transformAny(...) failed");
}

BUILD_DOUBLE_TEMPLATE(template class TransformAny, , SD_COMMON_TYPES, SD_COMMON_TYPES);
}  // namespace transform
}  // namespace functions
