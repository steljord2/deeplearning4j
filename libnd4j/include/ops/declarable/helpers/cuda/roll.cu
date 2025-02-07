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
//  @author raver119@gmail.com
//
#include <helpers/ConstantTadHelper.h>
#include <helpers/PointersManager.h>
#include <ops/declarable/helpers/roll.h>

namespace sd {
namespace ops {
namespace helpers {

template <typename T>
static void SD_DEVICE rollKernelLinearStage1Dev(const void *vx, const sd::LongType *xShapeInfo, void *vz,
                                                const sd::LongType *zShapeInfo, sd::LongType fullLength,
                                                int actualShift) {
  auto x = reinterpret_cast<const T *>(vx);
  auto z = reinterpret_cast<T *>(vz);

  auto xEws = shape::elementWiseStride(xShapeInfo);
  auto zEws = shape::elementWiseStride(zShapeInfo);

  auto xOrder = shape::order(xShapeInfo);
  auto zOrder = shape::order(zShapeInfo);

  auto tid = threadIdx.x + blockIdx.x * blockDim.x;

  if (xEws > 0 && zEws > 0 && xOrder == zOrder) {
    for (int i = tid; i < actualShift; i += blockDim.x * gridDim.x) {
      int sourceIndex = fullLength - actualShift + i;

      auto eA = x[sourceIndex * xEws];
      auto eB = x[i * xEws];

      z[i * zEws] = eA;
      z[sourceIndex * zEws] = eB;
    }
  } else {
    for (sd::LongType i = tid; i < actualShift; i += blockDim.x * gridDim.x) {
      int sourceIndex = fullLength - actualShift + i;

      auto xOffsetA = shape::getIndexOffset(i, xShapeInfo);
      auto xOffsetB = shape::getIndexOffset(sourceIndex, xShapeInfo);

      auto zOffsetA = shape::getIndexOffset(i, zShapeInfo);
      auto zOffsetB = shape::getIndexOffset(sourceIndex, zShapeInfo);

      auto eA = x[xOffsetA];
      auto eB = x[xOffsetB];

      z[zOffsetA] = eB;
      z[zOffsetB] = eA;
    }
  }
}

template <typename T>
static void SD_KERNEL rollKernelLinearStage1(const void *vx, const sd::LongType *xShapeInfo, void *vz,
                                             const sd::LongType *zShapeInfo, sd::LongType fullLength, int actualShift) {
  rollKernelLinearStage1Dev<T>(vx, xShapeInfo, vz, zShapeInfo, fullLength, actualShift);
}

template <typename T>
static void SD_KERNEL rollKernelLinearStage2(const void *vx, const sd::LongType *xShapeInfo, void *vz,
                                             const sd::LongType *zShapeInfo, sd::LongType fullLength, int actualShift,
                                             int shiftCount) {
  auto x = reinterpret_cast<const T *>(vx);
  auto z = reinterpret_cast<T *>(vz);

  auto xEws = shape::elementWiseStride(xShapeInfo);
  auto zEws = shape::elementWiseStride(zShapeInfo);

  auto xOrder = shape::order(xShapeInfo);
  auto zOrder = shape::order(zShapeInfo);

  auto tid = threadIdx.x + blockIdx.x * blockDim.x;

  if (xEws > 0 && zEws > 0 && xOrder == zOrder) {
    for (int count = 1; count < shiftCount; ++count) {
      for (int i = tid; i < actualShift; i += blockDim.x * gridDim.x) {
        int destinationIndex = fullLength - (count + 1) * actualShift + i;
        int sourceIndex = fullLength - count * actualShift + i;

        auto eA = x[sourceIndex * xEws];
        auto eB = x[destinationIndex * xEws];

        z[destinationIndex * zEws] = eA;
        z[sourceIndex * zEws] = eB;
      }

      __syncthreads();
    }
  } else {
    for (int count = 1; count < shiftCount; ++count) {
      for (int i = tid; i < actualShift; i += blockDim.x * gridDim.x) {
        int destinationIndex = fullLength - (count + 1) * actualShift + i;
        int sourceIndex = fullLength - count * actualShift + i;

        auto xOffsetA = shape::getIndexOffset(destinationIndex, xShapeInfo);
        auto xOffsetB = shape::getIndexOffset(sourceIndex, xShapeInfo);

        auto zOffsetA = shape::getIndexOffset(destinationIndex, zShapeInfo);
        auto zOffsetB = shape::getIndexOffset(sourceIndex, zShapeInfo);

        auto eA = x[xOffsetA];
        auto eB = x[xOffsetB];

        z[zOffsetA] = eB;
        z[zOffsetB] = eA;
      }

      __syncthreads();
    }
  }
}

template <typename T>
static void SD_KERNEL rollKernelLinearStage3(const void *vx, const sd::LongType *xShapeInfo, void *vz,
                                             const sd::LongType *zShapeInfo, sd::LongType fullLength, int actualShift,
                                             int remainShift) {
  auto x = reinterpret_cast<const T *>(vx);
  auto z = reinterpret_cast<T *>(vz);

  auto xEws = shape::elementWiseStride(xShapeInfo);
  auto zEws = shape::elementWiseStride(zShapeInfo);

  auto xOrder = shape::order(xShapeInfo);
  auto zOrder = shape::order(zShapeInfo);

  auto tid = threadIdx.x + blockIdx.x * blockDim.x;

  if (xEws > 0 && zEws > 0 && xOrder == zOrder) {
    for (int i = tid; i < actualShift; i += blockDim.x * gridDim.x) {
      int remainIdx = i + actualShift;
      int sourceIndex = remainIdx + remainShift;

      auto eA = x[sourceIndex * xEws];
      auto eB = x[remainIdx * xEws];

      z[remainIdx * zEws] = eA;
      z[sourceIndex * zEws] = eB;
    }
  } else {
    for (int i = tid; i < actualShift; i += blockDim.x * gridDim.x) {
      int remainIdx = i + actualShift;
      int sourceIndex = remainIdx + remainShift;

      auto xOffsetA = shape::getIndexOffset(remainIdx, xShapeInfo);
      auto xOffsetB = shape::getIndexOffset(sourceIndex, xShapeInfo);

      auto zOffsetA = shape::getIndexOffset(remainIdx, zShapeInfo);
      auto zOffsetB = shape::getIndexOffset(sourceIndex, zShapeInfo);

      auto eA = x[xOffsetA];
      auto eB = x[xOffsetB];

      z[zOffsetA] = eB;
      z[zOffsetB] = eA;
    }
  }
}

template <typename T>
static void SD_DEVICE swapTadsKernel(void *vx, void *vz, const sd::LongType *zShapeInfo, sd::LongType tadLength) {
  auto x = reinterpret_cast<T *>(vx);
  auto z = reinterpret_cast<T *>(vz);

  auto zEws = shape::elementWiseStride(zShapeInfo);

  auto zOrder = shape::order(zShapeInfo);

  auto tid = threadIdx.x + blockIdx.x * blockDim.x;

  if (zEws > 0) {
    for (int e = threadIdx.x; e < tadLength; e += blockDim.x) {
      auto eA = x[e * zEws];
      auto eB = z[e * zEws];

      x[e * zEws] = eB;
      z[e * zEws] = eA;
    }
  } else {
    for (int e = threadIdx.x; e < tadLength; e += blockDim.x) {
      auto zOffset = shape::getIndexOffset(e, zShapeInfo);

      auto eA = x[zOffset];
      auto eB = z[zOffset];

      x[zOffset] = eB;
      z[zOffset] = eA;
    }
  }
}

template <typename T>
static void SD_KERNEL rollKernelFullAnyDimensionStage1(const void *vx, const sd::LongType *xTadShapeInfo,
                                                       const sd::LongType *xTadOffsets, void *vz,
                                                       const sd::LongType *zTadShapeInfo,
                                                       const sd::LongType *zTadOffsets, int numTads,
                                                       sd::LongType tadLength, int dim, sd::LongType sizeAt,
                                                       int theShift) {
  auto x = reinterpret_cast<const T *>(vx);
  auto z = reinterpret_cast<T *>(vz);

  for (int e = blockIdx.x + theShift; e < sizeAt - theShift; e += gridDim.x) {
    int sourceIndex = dim * sizeAt + e - theShift;
    int targetIndex = dim * sizeAt + e;

    swapTadsKernel<T>(z + xTadOffsets[sourceIndex], z + xTadOffsets[targetIndex], zTadShapeInfo, tadLength);
  }
}

template <typename T>
static void SD_KERNEL rollKernelFullAnyDimensionStage2(void *vx, const sd::LongType *xTadShapeInfo,
                                                       const sd::LongType *xTadOffsets, void *vz,
                                                       const sd::LongType *zTadShapeInfo,
                                                       const sd::LongType *zTadOffsets, int numTads,
                                                       sd::LongType tadLength, int dim, sd::LongType sizeAt,
                                                       int theShift) {
  auto x = reinterpret_cast<const T *>(vx);
  auto z = reinterpret_cast<T *>(vz);

  for (int e = blockIdx.x; e < theShift; e += gridDim.x) {
    int sourceIndex = dim * sizeAt + sizeAt - theShift + e;
    int targetIndex = dim * sizeAt + e;

    swapTadsKernel<T>(z + zTadOffsets[sourceIndex], z + zTadOffsets[targetIndex], zTadShapeInfo, tadLength);
  }
}

template <typename T>
static void rollFunctorFull_(NDArray *input, NDArray *output, std::vector<sd::LongType> const &shifts,
                             std::vector<sd::LongType> const &axes, bool inplace) {
  if (!inplace) output->assign(input);

  for (size_t i = 0; i < axes.size(); i++) {
    int axe = axes[i];
    if (axe == input->rankOf() - 1) {  // last dimension
      ResultSet listOfTensors = output->allTensorsAlongDimension({axe});
      ResultSet listOfOutTensors = output->allTensorsAlongDimension({axe});
      int fullLen = listOfTensors.size();
      int theShift = shifts[i];
      for (int k = 0; k < fullLen; k++) {
        rollFunctorLinear(output->getContext(), listOfTensors.at(k), listOfOutTensors.at(k), theShift, true);
      }
    } else {
      std::vector<sd::LongType> dims(input->rankOf() - axe - 1);
      for (int i = 0; i < dims.size(); ++i) dims[i] = axe + 1 + i;

      auto packZ = ConstantTadHelper::getInstance().tadForDimensions(output->shapeInfo(), dims);

      int numTads = packZ.numberOfTads();
      int sizeAt = input->sizeAt(axe);
      auto tadLength = shape::length(packZ.primaryShapeInfo());

      int theShift = shifts[i];

      if (theShift) {
        for (int dim = 0; dim < numTads / sizeAt; ++dim) {
          rollKernelFullAnyDimensionStage1<T><<<1, 256, 1024, *(output->getContext()->getCudaStream())>>>(
              output->specialBuffer(), packZ.platformShapeInfo(), packZ.platformOffsets(), output->specialBuffer(),
              packZ.platformShapeInfo(), packZ.platformOffsets(), numTads, tadLength, dim, sizeAt, theShift);

          rollKernelFullAnyDimensionStage2<T><<<1, 256, 1024, *(output->getContext()->getCudaStream())>>>(
              output->specialBuffer(), packZ.platformShapeInfo(), packZ.platformOffsets(), output->specialBuffer(),
              packZ.platformShapeInfo(), packZ.platformOffsets(), numTads, tadLength, dim, sizeAt, theShift);
        }
      }
    }
  }
}

template <typename T>
static void rollFunctorLinear_(NDArray *input, NDArray *output, int shift, bool inplace) {
  if (!inplace) output->assign(input);

  auto fullLen = input->lengthOf();
  int actualShift = shift;  // % fullLen; // shift already non-negative then
  if (actualShift < 0) {
    actualShift -= fullLen * (actualShift / fullLen - 1);
  } else
    actualShift %= fullLen;

  if (actualShift) {
    int shiftCount = fullLen / actualShift - 1;
    int remainShift = fullLen % actualShift;

    // stage 1) swap last actualShift elements with first ones.
    rollKernelLinearStage1<T><<<1, 1, 1024, *(output->getContext()->getCudaStream())>>>(
        output->specialBuffer(), output->specialShapeInfo(), output->specialBuffer(), output->specialShapeInfo(),
        fullLen, actualShift);

    // stage 2) swap swapped actualShift elements with rest remainShiftCount times.
    rollKernelLinearStage2<T><<<1, 1, 1024, *(output->getContext()->getCudaStream())>>>(
        output->specialBuffer(), output->specialShapeInfo(), output->specialBuffer(), output->specialShapeInfo(),
        fullLen, actualShift, shiftCount);

    // FIXME: no parallelism here :(
    // stage 3) swap remainer of items.
    if (remainShift && shiftCount)
      rollKernelLinearStage3<T><<<1, 1, 1024, *(output->getContext()->getCudaStream())>>>(
          output->specialBuffer(), output->specialShapeInfo(), output->specialBuffer(), output->specialShapeInfo(),
          fullLen, actualShift, remainShift);
  }
}

void rollFunctorFull(sd::LaunchContext *context, NDArray *input, NDArray *output, std::vector<sd::LongType> const &shifts,
                     std::vector<sd::LongType> const &axes, bool inplace) {
  input->syncToDevice();

  BUILD_SINGLE_SELECTOR(input->dataType(), rollFunctorFull_, (input, output, shifts, axes, inplace), SD_COMMON_TYPES);

  output->tickWriteDevice();
}

void rollFunctorLinear(sd::LaunchContext *context, NDArray *input, NDArray *output, int shift, bool inplace) {
  input->syncToDevice();

  BUILD_SINGLE_SELECTOR(input->dataType(), rollFunctorLinear_, (input, output, shift, inplace), SD_COMMON_TYPES);

  output->tickWriteDevice();
}

BUILD_SINGLE_TEMPLATE(template void rollFunctorLinear_, (NDArray * input, NDArray *output, int shift, bool inplace),
                      SD_COMMON_TYPES);
BUILD_SINGLE_TEMPLATE(template void rollFunctorFull_,
                      (NDArray * input, NDArray *output, std::vector<sd::LongType> const &shifts, std::vector<sd::LongType> const &axes,
                       bool inplace),
                      SD_COMMON_TYPES);
}  // namespace helpers
}  // namespace ops
}  // namespace sd
