// Copyright 2023 Robotec.AI
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
#include <gpu/gaussianNoiseKernels.hpp>

void GaussianNoiseAngularHitpointNode::setParameters(float mean, float stDev, rgl_axis_t rotationAxis)
{
	this->mean = mean;
	this->stDev = stDev;
	this->rotationAxis = rotationAxis;
}

void GaussianNoiseAngularHitpointNode::validate()
{
	input = getValidInput<IPointsNode>();
	lookAtOriginTransform = input->getLookAtOriginTransform();

	// This node will modifty field DISTANCE_F32 if present.
	// In the future: only one field should be modified.
	// Other fields that depend on the main field (for now, it's XYZ_F32) should be calculated somewhere else (e.g., in data getters nodes).
	if (input->hasField(DISTANCE_F32)) {
		if (outDistance == nullptr) {
			outDistance = VArrayProxy<Field<DISTANCE_F32>::type>::create();
		}
	} else {
		outDistance.reset();
	}
}

void GaussianNoiseAngularHitpointNode::schedule(cudaStream_t stream)
{
	auto pointCount = input->getPointCount();
	outXyz->resize(pointCount, false, false);

	Field<DISTANCE_F32>::type* outDistancePtr = nullptr;
	if (outDistance != nullptr) {
		outDistance->resize(pointCount, false, false);
		outDistancePtr = outDistance->getDevicePtr();
	}

	if (randomizationStates->getCount() < pointCount) {
		randomizationStates->resize(pointCount, false, false);
		gpuSetupGaussianNoiseGenerator(nullptr, pointCount, randomDevice(), randomizationStates->getDevicePtr());
	}

	const auto inXyz = input->getFieldDataTyped<XYZ_F32>(stream);
	const auto* inXyzPtr = inXyz->getDevicePtr();
	auto* outXyzPtr = outXyz->getDevicePtr();
	gpuAddGaussianNoiseAngularHitpoint(stream, pointCount, mean, stDev, rotationAxis, lookAtOriginTransform, randomizationStates->getDevicePtr(), inXyzPtr, outXyzPtr, outDistancePtr);
}

VArray::ConstPtr GaussianNoiseAngularHitpointNode::getFieldData(rgl_field_t field, cudaStream_t stream) const
{
	if (field == XYZ_F32) {
		// TODO(msz-rai): check sync is necessary
		CHECK_CUDA(cudaStreamSynchronize(stream));
		return outXyz->untyped();
	}
	if (field == DISTANCE_F32 && outDistance != nullptr) {
		// TODO(msz-rai): check sync is necessary
		CHECK_CUDA(cudaStreamSynchronize(stream));
		return outDistance->untyped();
	}
	return input->getFieldData(field, stream);
}

std::vector<rgl_field_t> GaussianNoiseAngularHitpointNode::getRequiredFieldList() const
{
	return {XYZ_F32};
}
