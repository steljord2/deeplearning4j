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
//  @author sgazeos@gmail.com
//
#include <helpers/ConstantTadHelper.h>
#include <helpers/PointersManager.h>
#include <helpers/TAD.h>
#include <ops/declarable/helpers/axis.h>

#include <array>

namespace sd {
namespace ops {
namespace helpers {
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// extract patches kernel
//      - theSame - SAME or VALID - output format
//      - batchCount - batches - the first dimension of input
//      - sizeRow, sizeCol - rows and cols sizes for batch
//      - rowDim, colDim - rows and cols dimensions for input patches
//      - outRowDim, outColDim - rows and cols dimensions for output patches
//      - strideRow, strideCol - step between input elements with patches
//      - rateRow, rateCol - counts for input patches
//      - rowCast, colCast - shifts for output placement (1 or 0)
//      - lastDim - last dimension of input/output
//      - input - input tensor buffer
//      - patchShape - input patch TAD shape
//      - inputOffsets - input TAD offsets
//      - output - output tensor buffer
//      - outTadShape - output TAD shape
//      - outputOffsets - output TAD offsets
//
template <typename T>
static SD_KERNEL void globalExtractPatchesKernel(bool theSame, int batchCount, int sizeRow, int sizeCol, int rowDim,
                                                 int colDim, int outRowDim, int outColDim, int strideRow, int strideCol,
                                                 int rateRow, int rateCol, int rowCast, int colCast, int lastDim,
                                                 const T* input, const sd::LongType* patchShape,
                                                 const sd::LongType* inputOffsets, T* output,
                                                 const sd::LongType* outTadShape, const sd::LongType* outputOffsets) {
  auto start = threadIdx.x + blockIdx.x * blockDim.x;

  auto step = blockDim.x * gridDim.x;
  // batch  input by 3 last dims and extrapole input onto output with outColDim/outRowDim
  for (sd::LongType batch = start; batch < batchCount; batch += step) {
    auto patch = input + inputOffsets[batch];        // listOfMatricies->at(batch);
    auto outMatrix = output + outputOffsets[batch];  // listOfOutputs->at(batch);

    for (sd::LongType i = 0; i < outRowDim; i++) {
      for (sd::LongType j = 0; j < outColDim; j++) {
        sd::LongType pos = 0;
        auto rowStart = i * strideRow - (theSame ? rowCast : 0);
        auto colStart = j * strideCol - (theSame ? colCast : 0);
        auto rowEnd = rowStart + sizeRow * rateRow;
        auto colEnd = colStart + sizeCol * rateCol;
        if (!theSame) {
          rowEnd = math::sd_min(rowStart + sizeRow * rateRow, sd::LongType(rowDim));
          colEnd = math::sd_min(colStart + sizeCol * rateCol, sd::LongType(colDim));
        }

        for (auto row = rowStart; row < rowEnd; row += rateRow) {
          for (auto col = colStart; col < colEnd; col += rateCol) {
            for (auto pixel = 0; pixel < lastDim; pixel++) {
              sd::LongType zPos[] = {i, j, pos};
              sd::LongType xPos[] = {row, col, pixel};
              bool setUp = (theSame && row >= 0 && col >= 0 && row < rowDim && col < colDim) || (!theSame);

              if (setUp) {  // VALID or SAME cases
                outMatrix[shape::getOffset(outTadShape, zPos)] = patch[shape::getOffset(patchShape, xPos)];
              }
              pos++;
            }
          }
        }
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
template <typename T>
static void _extractPatches(sd::LaunchContext* context, NDArray* images, NDArray* output, int sizeRow, int sizeCol,
                            int strideRow, int strideCol, int rateRow, int rateCol, bool theSame) {
  NDArray::prepareSpecialUse({output}, {images});
  std::vector<sd::LongType> restDims({1, 2, 3});  // the first and the last dims
  // 3D matricies - 2D matricies of vectors (if last dim is greater than 1)
  // int e = 0;
  const int ksizeRowsEffective = sizeRow + (sizeRow - 1) * (rateRow - 1);
  const int ksizeColsEffective = sizeCol + (sizeCol - 1) * (rateCol - 1);
  const int ksize = ksizeRowsEffective * ksizeColsEffective;
  sd::LongType lastDim = images->sizeAt(3);
  sd::LongType outLastDim = output->sizeAt(3);
  sd::LongType rowDim = images->sizeAt(1);
  sd::LongType colDim = images->sizeAt(2);
  sd::LongType outRowDim = output->sizeAt(1);
  sd::LongType outColDim = output->sizeAt(2);
  auto rowCast = 1;
  auto colCast = 1;
  // validate shifts
  if (sizeRow * rateRow < 3) rowCast = 0;
  if (sizeCol * rateCol < 3) colCast = 0;

  auto packX =
      sd::ConstantTadHelper::getInstance().tadForDimensions(images->shapeInfo(), restDims.data(), restDims.size());
  auto packZ =
      sd::ConstantTadHelper::getInstance().tadForDimensions(output->shapeInfo(), restDims.data(), restDims.size());
  int batchCount = packX.numberOfTads();

  PointersManager manager(context, "helpers::extractPatches");

  auto stream = context->getCudaStream();
  auto imagesBuffer = reinterpret_cast<T*>(images->specialBuffer());
  auto outputBuffer = reinterpret_cast<T*>(output->specialBuffer());

  globalExtractPatchesKernel<T><<<128, 128, 1024, *stream>>>(
      theSame, batchCount, sizeRow, sizeCol, rowDim, colDim, outRowDim, outColDim, strideRow, strideCol, rateRow,
      rateCol, rowCast, colCast, lastDim, imagesBuffer, packX.specialShapeInfo(), packX.specialOffsets(), outputBuffer,
      packZ.specialShapeInfo(), packZ.specialOffsets());

  manager.synchronize();
  NDArray::registerSpecialUse({output}, {images});
}
BUILD_SINGLE_TEMPLATE(template void _extractPatches,
                      (sd::LaunchContext * context, NDArray* input, NDArray* output, int sizeRow, int sizeCol,
                       int stradeRow, int stradeCol, int rateRow, int rateCol, bool theSame),
                      SD_COMMON_TYPES);

void extractPatches(sd::LaunchContext* context, NDArray* images, NDArray* output, int sizeRow, int sizeCol,
                    int stradeRow, int stradeCol, int rateRow, int rateCol, bool theSame) {
  auto xType = images->dataType();

  BUILD_SINGLE_SELECTOR(xType, _extractPatches,
                        (context, images, output, sizeRow, sizeCol, stradeRow, stradeCol, rateRow, rateCol, theSame),
                        SD_COMMON_TYPES);
}
}  // namespace helpers
}  // namespace ops
}  // namespace sd
