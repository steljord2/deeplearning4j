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
// Created by raver on 4/9/2018.
//
#include <helpers/DebugHelper.h>
#include <system/Environment.h>
#include <system/op_boilerplate.h>
#include <types/types.h>

#include "../indexreduce.h"
#include "../legacy_ops.h"

using namespace simdOps;

template <typename X, typename Z>
static SD_KERNEL void simpleIndexReduceGeneric(const int op, void const *dx, sd::LongType const *xShapeInfo,
                                               sd::LongType xRank,
                                               void *extraParams, void *result, sd::LongType const *zShapeInfo, sd::LongType zRank,
                                               sd::LongType *dimension, sd::LongType dimensionLength, int postProcessOrNot, sd::LongType *allocationBuffer, void *reductionBuffer,
                                               sd::LongType const *tadOnlyShapeInfo, sd::LongType const *tadOffsets) {
  functions::indexreduce::IndexReduce<X, Z>::transform(op, dx, xShapeInfo, extraParams, result, zShapeInfo, dimension,
                                                       dimensionLength, postProcessOrNot, allocationBuffer,
                                                       reductionBuffer, tadOnlyShapeInfo, tadOffsets);
}

namespace functions {
namespace indexreduce {

template <typename X, typename Z>
SD_HOST void IndexReduce<X, Z>::executeIndexReduceScalar(
    dim3 launchDims, cudaStream_t *stream, const int opNum, void const *dx, sd::LongType const *xShapeInfo,
    sd::LongType xRank,
    void *extraParams, void *result, sd::LongType const *zShapeInfo, sd::LongType zRank,
    sd::LongType *dimension, sd::LongType dimensionLength,
    int postProcessOrNot,sd::LongType *allocationBuffer, void *reductionBuffer, sd::LongType const *tadOnlyShapeInfo,
    sd::LongType const *tadOffsets) {
  simpleIndexReduceGeneric<X, Z><<<launchDims.x, launchDims.y, launchDims.z, *stream>>>(
      opNum, dx, xShapeInfo, xRank, extraParams, result, zShapeInfo, 0, nullptr, 0, 1, allocationBuffer,
      reductionBuffer, tadOnlyShapeInfo, tadOffsets);
}

template <typename X, typename Z>
SD_HOST void IndexReduce<X, Z>::executeIndexReduce(dim3 launchDims, cudaStream_t *stream, const int opNum,
                                                   void const *dx, sd::LongType const *xShapeInfo,
                                                   sd::LongType xRank,
                                                   void *extraParams, void *result, sd::LongType const *zShapeInfo, sd::LongType zRank,
                                                   sd::LongType *dimension, sd::LongType dimensionLength,
                                                   int postProcessOrNot,
                                                   sd::LongType *allocationBuffer,
                                                   void *reductionBuffer,
                                                   sd::LongType const *tadOnlyShapeInfo,
                                                   sd::LongType const *tadOffsets) {
  simpleIndexReduceGeneric<X, Z><<<launchDims.x, launchDims.y, launchDims.z, *stream>>>(
      opNum, dx, xShapeInfo, xRank, extraParams, result, zShapeInfo, zRank, dimension, dimensionLength, postProcessOrNot,
      allocationBuffer, reductionBuffer, tadOnlyShapeInfo, tadOffsets);
}

// This is the un-specialized struct.  Note that we prevent instantiation of this
// struct by putting an undefined symbol in the function body so it won't compile.
template <typename T>
struct SharedIndexValue {
  // Ensure that we won't compile any un-specialized types
  SD_DEVICE T *getPointer() {
    extern SD_DEVICE void error(void);
    error();
    return 0;
  }
};

// Following are the specializations for the following types.
// int, sd::Unsigned, char, uchar, short, ushort, long long, ulong long, bool, float, and double
// One could also specialize it for user-defined types.

template <>
struct SharedIndexValue<float> {
  SD_DEVICE IndexValue<float> *getPointer() {
    extern __shared__ IndexValue<float> s_int2[];
    return s_int2;
  }
};
// Following are the specializations for the following types.
// int, sd::Unsigned, char, uchar, short, ushort, long long, ulong long, bool, float, and double
// One could also specialize it for user-defined types.

template <>
struct SharedIndexValue<double> {
  SD_DEVICE IndexValue<double> *getPointer() {
    extern __shared__ IndexValue<double> s_int6[];
    return s_int6;
  }
};

template <typename X, typename Z>
template <typename OpType>
SD_DEVICE void IndexReduce<X, Z>::aggregatePartials(IndexValue<X> *sPartials, sd::LongType tid,
                                                    sd::LongType numElements, void *vextraParams) {
  // start the shared memory loop on the next power of 2 less
  // than the block size.  If block size is not a power of 2,
  // accumulate the intermediate sums in the remainder range.
  auto extraParams = static_cast<X *>(vextraParams);
  sd::LongType floorPow2 = blockDim.x;

  if (floorPow2 & (floorPow2 - 1)) {
    while (floorPow2 & (floorPow2 - 1)) {
      floorPow2 &= floorPow2 - 1;
    }

    if (tid >= floorPow2) {
      IndexValue<X> prev = sPartials[tid - floorPow2];
      IndexValue<X> curr = sPartials[tid];
      sPartials[tid - floorPow2] = OpType::update(prev, curr, extraParams);
    }
    __syncthreads();
  }

  for (int activeThreads = floorPow2 >> 1; activeThreads; activeThreads >>= 1) {
    if (tid < activeThreads && tid + activeThreads < numElements) {
      IndexValue<X> curr = sPartials[tid];
      IndexValue<X> next = sPartials[tid + activeThreads];
      sPartials[tid] = OpType::update(curr, next, extraParams);
    }
    __syncthreads();
  }
}

template <typename X, typename Y>
SD_DEVICE void IndexReduce<X, Y>::transform(int opNum, void const *x, sd::LongType const *xShapeInfo,
                                            void *extraParams, void *result, sd::LongType const *zShapeInfo, sd::LongType *dimension,
                                            sd::LongType dimensionLength, int postProcessOrNot,
                                            sd::LongType *allocationBuffer, void *reductionBuffer,
                                            sd::LongType const *tadShapeInfo, sd::LongType const *tadOffset) {
  DISPATCH_BY_OPNUM_TT(transform,
                       PARAMS(x, xShapeInfo, extraParams, result, zShapeInfo, dimension, dimensionLength,
                              postProcessOrNot, allocationBuffer, reductionBuffer, tadShapeInfo, tadOffset),
                       INDEX_REDUCE_OPS);
}

template <typename X, typename Z>
template <typename OpType>
SD_DEVICE void IndexReduce<X, Z>::transform(void const *vdx, sd::LongType const *xShapeInfo, void *vextraParams,
                                            void *vz, sd::LongType const *zShapeInfo, sd::LongType *dimension,
                                            sd::LongType dimensionLength, int postProcessOrNot,
                                            sd::LongType *allocationBuffer,
                                            void *vreductionBuffer, sd::LongType const *tadOnlyShapeInfo,
                                            sd::LongType const *tadOffsets) {
  /**int
   * Gpu information for the problem
   */
  auto dx = reinterpret_cast<X const *>(vdx);
  auto z = reinterpret_cast<Z *>(vz);
  auto extraParams = static_cast<X *>(vextraParams);
  auto reductionBuffer = static_cast<X *>(vreductionBuffer);
  auto order = shape::order(xShapeInfo);
  int tid = blockIdx.x * blockDim.x + threadIdx.x;
  __shared__ volatile bool resultScalar;

  // shared memory space for storing intermediate results
  __shared__ IndexValue<X> sPartials[SD_CUDA_BLOCK_SIZE];

  sPartials[threadIdx.x] = OpType::startingIndexValue(dx);

  // length for the tad
  __shared__ volatile sd::LongType xLength;

  __shared__ volatile sd::LongType zLen;

  // only compute the tad indexes once
  IndexValue<X> reduction = OpType::startingIndexValue(dx);

  if (threadIdx.x == 0) {
    if (zShapeInfo != nullptr)
      zLen = shape::length(zShapeInfo);
    else
      zLen = 1;

    if (zLen == 1)
      resultScalar = true;
    else
      resultScalar = false;

    xLength = shape::length(xShapeInfo);
  }
  __syncthreads();

  if (sd::ArrayOptions::arrayType(xShapeInfo) == sd::ArrayType::EMPTY) {
    if (sd::ArrayOptions::arrayType(zShapeInfo) == sd::ArrayType::EMPTY) return;

    for (sd::Unsigned i = blockIdx.x * blockDim.x + threadIdx.x; i < zLen; i += gridDim.x * blockDim.x)
      z[i] = (Z)reduction.index;

    return;
  }

  if (!resultScalar) {
    __shared__ sd::LongType tadLength;
    __shared__ int tadEWS;
    __shared__ int numTads;

    if (threadIdx.x == 0) {
      tadLength = shape::length(tadOnlyShapeInfo);
      tadEWS = shape::elementWiseStride(tadOnlyShapeInfo);
      numTads = shape::length(xShapeInfo) / tadLength;
    }
    __syncthreads();

    if (dimensionLength > 1 || tadEWS < 1) {
      for (int r = blockIdx.x; r < numTads; r += gridDim.x) {
        auto tadOffsetForBlock = tadOffsets[r];
        sPartials[threadIdx.x] = OpType::startingIndexValue(dx);

        for (int i = threadIdx.x; i < tadLength; i += blockDim.x) {
          auto xOffset = tadOffsetForBlock + shape::getIndexOffset(i, tadOnlyShapeInfo);
          IndexValue<X> comp{dx[xOffset], i};
          sPartials[threadIdx.x] = OpType::update(sPartials[threadIdx.x], comp, extraParams);
        }

        __syncthreads();
        aggregatePartials<OpType>(sPartials, threadIdx.x, sd::math::sd_min<int>(blockDim.x, tadLength), extraParams);

        __syncthreads();
        if (threadIdx.x == 0) {
          z[r] = (Z)sPartials[threadIdx.x].index;
        }
        __syncthreads();
      }
    } else {
      for (int i = blockIdx.x; i < numTads; i += gridDim.x) {
        sd::LongType tadOffsetForBlock = tadOffsets[i];

        sPartials[threadIdx.x] = OpType::startingIndexValue(dx);

        for (int x = threadIdx.x; x < tadLength; x += blockDim.x) {
          IndexValue<X> comp{dx[tadOffsetForBlock + x * tadEWS], x};
          sPartials[threadIdx.x] = OpType::update(sPartials[threadIdx.x], comp, extraParams);
        }

        __syncthreads();
        aggregatePartials<OpType>(sPartials, threadIdx.x, sd::math::sd_min<int>(blockDim.x, tadLength), extraParams);

        __syncthreads();
        if (threadIdx.x == 0) {
          z[i] = (Z)sPartials[threadIdx.x].index;  // postProcess(sPartials[0],tadLength ,extraParams);
        }
        __syncthreads();
      }
    }
  } else {
    auto n = shape::length(xShapeInfo);
    auto xElementWiseStride = shape::elementWiseStride(xShapeInfo);

    if (xElementWiseStride >= 1 && order == 'c') {
      for (sd::LongType i = tid; i < n; i += (blockDim.x * gridDim.x)) {
        IndexValue<X> indexVal = {dx[i * xElementWiseStride], i};
        reduction = OpType::update(reduction, indexVal, extraParams);
      }
    } else {
      for (sd::LongType i = tid; i < n; i += blockDim.x * gridDim.x) {
        auto offset = shape::getIndexOffset(i, xShapeInfo);
        IndexValue<X> indexVal = {dx[offset], i};
        reduction = OpType::update(reduction, indexVal, extraParams);
      }
    }

    sPartials[threadIdx.x] = reduction;
    __syncthreads();

    aggregatePartials<OpType>(sPartials, threadIdx.x, sd::math::sd_min<int>(blockDim.x, (int)n), extraParams);
    __syncthreads();

    if (gridDim.x > 1) {
      __shared__ bool amLast;
      unsigned int *tc = (unsigned int *)reductionBuffer;
      tid = threadIdx.x;
      if (threadIdx.x == 0) {
        auto pBuffer = reinterpret_cast<IndexValue<X> *>(reductionBuffer);
        pBuffer[blockIdx.x] = {sPartials[0].value, sPartials[0].index};
      }
      __threadfence();
      __syncthreads();

      if (tid == 0) {
        unsigned int ticket = atomicInc(&tc[16384], gridDim.x);
        amLast = (ticket == gridDim.x - 1);
      }

      __syncthreads();

      if (amLast) {
        tc[16384] = 0;
        IndexValue<X> *pBuffer = (IndexValue<X> *)reductionBuffer;

        sPartials[threadIdx.x] = OpType::startingIndexValue(dx);

        for (sd::LongType i = threadIdx.x; i < gridDim.x; i += blockDim.x) {
          sPartials[threadIdx.x] = OpType::update(sPartials[threadIdx.x], pBuffer[i], extraParams);
        }

        __syncthreads();
        aggregatePartials<OpType>(sPartials, threadIdx.x, sd::math::sd_min<int>(gridDim.x, blockDim.x), extraParams);

        __syncthreads();
        if (tid == 0) {
          z[0] = (Z)sPartials[0].index;
        }
      }
    } else {
      if (tid == 0) {
        auto tc = reinterpret_cast<unsigned int *>(reductionBuffer);
        tc[16384] = 0;
        z[0] = (Z)sPartials[0].index;
      }
    }
  }
}

BUILD_DOUBLE_TEMPLATE(template class IndexReduce, , SD_COMMON_TYPES, SD_INDEXING_TYPES);
}  // namespace indexreduce
}  // namespace functions
