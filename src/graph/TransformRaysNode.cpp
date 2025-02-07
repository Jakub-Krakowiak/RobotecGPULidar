// Copyright 2022 Robotec.AI
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <graph/NodesCore.hpp>
#include <gpu/nodeKernels.hpp>

void TransformRaysNode::validate()
{
	input = getValidInput<IRaysNode>();
}

void TransformRaysNode::schedule(cudaStream_t stream)
{
	rays->resize(getRayCount());
	gpuTransformRays(stream, getRayCount(), input->getRays()->getDevicePtr(), rays->getDevicePtr(), transform);
}
