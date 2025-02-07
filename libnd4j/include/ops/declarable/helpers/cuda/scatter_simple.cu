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
// @author Yurii Shyrma (iuriish@yahoo.com), created on 20.04.2018
//

#include <array/NDArrayFactory.h>
#include <array/ResultSet.h>
#include <exceptions/cuda_exception.h>
#include <helpers/ConstantTadHelper.h>
#include <helpers/PointersManager.h>
#include <helpers/ShapeUtils.h>
#include <helpers/TAD.h>
#include <ops/declarable/helpers/transforms.h>

#include <numeric>

namespace sd {
namespace ops {
namespace helpers {
template <typename X, typename Y>
static SD_KERNEL void scatterSimpleKernel(void* vx, const sd::LongType* xTadShape, const sd::LongType* xTadOffsets,
                                          sd::LongType xLength, sd::LongType numTads, const void* vi,
                                          const sd::LongType* iShapeInfo, sd::LongType iLength, const void* vu,
                                          const sd::LongType* uShapeInfo, sd::LongType uLength) {
  auto u = reinterpret_cast<const X*>(vu);
  auto indices = reinterpret_cast<const Y*>(vi);

  auto tid = threadIdx.x + blockIdx.x * blockDim.x;
  for (int i = tid; i < iLength; i += blockDim.x * gridDim.x) {
    auto x = reinterpret_cast<X*>(vx) + xTadOffsets[i];
    auto idx = indices[shape::getIndexOffset(i, iShapeInfo)];

    x[shape::getIndexOffset(idx, xTadShape)] = u[shape::getIndexOffset(i, uShapeInfo)];
  }
}

template <typename X, typename Y>
void scatterSimple_(sd::LaunchContext* context, const int opId, NDArray& input, const NDArray& updates,
                    const NDArray& indices, const std::vector<sd::LongType>& dimensions) {
  auto dims = ShapeUtils::evalDimsToExclude(input.rankOf(), dimensions);
  auto packX = ConstantTadHelper::getInstance().tadForDimensions(input.shapeInfo(), dims);

  auto xLength = shape::length(packX.primaryShapeInfo());
  auto iLength = indices.lengthOf();
  auto uLength = updates.lengthOf();

  scatterSimpleKernel<X, Y><<<256, 256, 1024, *context->getCudaStream()>>>(
      input.specialBuffer(), packX.platformShapeInfo(), packX.platformOffsets(), xLength, packX.numberOfTads(),
      indices.specialBuffer(), indices.specialShapeInfo(), iLength, updates.specialBuffer(), updates.specialShapeInfo(),
      uLength);
}

void scatterSimple(sd::LaunchContext* context, const int opId, NDArray& input, const NDArray& updates,
                   const NDArray& indices, const std::vector<sd::LongType>& dimensions) {
  auto xType = input.dataType();
  auto yType = indices.dataType();

  if (opId != 6) throw std::runtime_error("scatterSimple: only copy op is supported");

  NDArray::prepareSpecialUse({&input}, {&updates, &indices});

  BUILD_DOUBLE_SELECTOR(xType, yType, scatterSimple_, (context, opId, input, updates, indices, dimensions),
                        SD_COMMON_TYPES, SD_INDEXING_TYPES);

  NDArray::registerSpecialUse({&input}, {&updates, &indices});
}
}  // namespace helpers
}  // namespace ops
}  // namespace sd
