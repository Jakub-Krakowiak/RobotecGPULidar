#include <Optix.hpp>

#include <cassert>
#include <stdexcept>
#include <cstring>

#include <cuda.h>
#include <optix.h>
#include <optix_stubs.h>
#include <fmt/format.h>
#include <cuda_runtime_api.h>

#include <macros/optix.hpp>

#include <Logging.h>

#include <optix_function_table_definition.h>

#define OPTIX_LOG_LEVEL_NONE 0
#define OPTIX_LOG_LEVEL_FATAL 1
#define OPTIX_LOG_LEVEL_ERROR 2
#define OPTIX_LOG_LEVEL_WARN 3
#define OPTIX_LOG_LEVEL_INFO 4

extern const char embedded_ptx_code[];
static CUcontext getCurrentDeviceContext();

Optix& Optix::instance()
{
	static Optix instance;
	return instance;
}

Optix::Optix()
{
	CHECK_OPTIX(optixInit());
	CHECK_OPTIX(optixDeviceContextCreate(getCurrentDeviceContext(), nullptr, &context));

	auto cbInfo = [](unsigned level, const char* tag, const char* message, void*) {
		auto fmt = "[RGL][OptiX][{:2}][{:^12}]: {}\n";
		logInfo(fmt, level, tag, message);
	};
	auto cbWarn = [](unsigned level, const char* tag, const char* message, void*) {
		auto fmt = "[RGL][OptiX][{:2}][{:^12}]: {}\n";
		logWarn(fmt, level, tag, message);
	};
	auto cbErr = [](unsigned level, const char* tag, const char* message, void*) {
		auto fmt = "[RGL][OptiX][{:2}][{:^12}]: {}\n";
		logError(fmt, level, tag, message);
	};

	CHECK_OPTIX(optixDeviceContextSetLogCallback(context, cbErr, nullptr, OPTIX_LOG_LEVEL_FATAL));
	CHECK_OPTIX(optixDeviceContextSetLogCallback(context, cbErr, nullptr, OPTIX_LOG_LEVEL_ERROR));
	CHECK_OPTIX(optixDeviceContextSetLogCallback(context, cbWarn, nullptr, OPTIX_LOG_LEVEL_WARN));
	CHECK_OPTIX(optixDeviceContextSetLogCallback(context, cbInfo, nullptr, OPTIX_LOG_LEVEL_INFO));
	initializeStaticOptixStructures();
}

Optix::~Optix()
{
	if (pipeline) {
		optixPipelineDestroy(pipeline);
	}

	for (auto&& programGroup : { raygenPG, missPG, hitgroupPG }) {
		if (programGroup) {
			optixProgramGroupDestroy(programGroup);
		}
	}

	if (module) {
		optixModuleDestroy(module);
	}

	if (context) {
		optixDeviceContextDestroy(context);
	}
}

void Optix::initializeStaticOptixStructures()
{
	OptixModuleCompileOptions moduleCompileOptions = {
		.maxRegisterCount = 100,
#ifdef NDEBUG
		.optLevel = OPTIX_COMPILE_OPTIMIZATION_LEVEL_2,
		.debugLevel = OPTIX_COMPILE_DEBUG_LEVEL_NONE
#else
		.optLevel = OPTIX_COMPILE_OPTIMIZATION_LEVEL_0,
		.debugLevel = OPTIX_COMPILE_DEBUG_LEVEL_FULL
#endif
	};

	OptixPipelineCompileOptions pipelineCompileOptions = {
		.usesMotionBlur = false,
		.traversableGraphFlags = OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_ANY,
		.numPayloadValues = 4,
		.numAttributeValues = 2,
		.exceptionFlags = OPTIX_EXCEPTION_FLAG_NONE,
		.pipelineLaunchParamsVariableName = "optixLaunchLidarParams",
	};

	OptixPipelineLinkOptions pipelineLinkOptions = {
		.maxTraceDepth = 2,
#ifdef NDEBUG
		.debugLevel = OPTIX_COMPILE_DEBUG_LEVEL_NONE,
#else
		.debugLevel = OPTIX_COMPILE_DEBUG_LEVEL_FULL,
#endif
	};

	CHECK_OPTIX(optixModuleCreateFromPTX(context,
		&moduleCompileOptions,
		&pipelineCompileOptions,
		embedded_ptx_code,
		strlen(embedded_ptx_code),
		nullptr, nullptr,
		&module
	));

	OptixProgramGroupOptions pgOptions = {};
	OptixProgramGroupDesc raygenDesc = {
		.kind = OPTIX_PROGRAM_GROUP_KIND_RAYGEN,
		.raygen = {
			.module = module,
			.entryFunctionName = "__raygen__renderLidar" }
	};

	CHECK_OPTIX(optixProgramGroupCreate(
		context, &raygenDesc, 1, &pgOptions, nullptr, nullptr, &raygenPG));

	OptixProgramGroupDesc missDesc = {
		.kind = OPTIX_PROGRAM_GROUP_KIND_MISS,
		.miss = {
			.module = module,
			.entryFunctionName = "__miss__lidar" },
	};

	CHECK_OPTIX(optixProgramGroupCreate(
		context, &missDesc, 1, &pgOptions, nullptr, nullptr, &missPG));

	OptixProgramGroupDesc hitgroupDesc = {
		.kind = OPTIX_PROGRAM_GROUP_KIND_HITGROUP,
		.hitgroup = {
			.moduleCH = module,
			.entryFunctionNameCH = "__closesthit__lidar",
			.moduleAH = module,
			.entryFunctionNameAH = "__anyhit__lidar",
		}
	};

	CHECK_OPTIX(optixProgramGroupCreate(
		context, &hitgroupDesc, 1, &pgOptions, nullptr, nullptr, &hitgroupPG));

	OptixProgramGroup programGroups[] = { raygenPG, missPG, hitgroupPG };

	CHECK_OPTIX(optixPipelineCreate(
		context,
		&pipelineCompileOptions,
		&pipelineLinkOptions,
		programGroups,
		sizeof(programGroups) / sizeof(programGroups[0]),
		nullptr, nullptr,
		&pipeline
	));

	CHECK_OPTIX(optixPipelineSetStackSize(
		pipeline,
		2 * 1024, // directCallableStackSizeFromTraversal
		2 * 1024, // directCallableStackSizeFromState
		2 * 1024, // continuationStackSize
		3 // maxTraversableGraphDepth
	));
}

static CUcontext getCurrentDeviceContext()
{
	const char* error = nullptr;
	CUresult status;

	cudaFree(nullptr); // Force CUDA runtime initialization

	CUdevice device;
	status = cuDeviceGet(&device, 0);
	if (status != CUDA_SUCCESS) {
		cuGetErrorString(status, &error);
		throw std::runtime_error(fmt::format("failed to get current CUDA device: {} ({})\n", error, status));
	}

	CUcontext cudaContext = nullptr;
	CUresult primaryCtxStatus = cuDevicePrimaryCtxRetain(&cudaContext, device);
	if (primaryCtxStatus != CUDA_SUCCESS) {
		cuGetErrorString(status, &error);
		throw std::runtime_error(fmt::format("failed to get primary CUDA context: {} ({})\n", error, status));
	}
	assert(cudaContext != nullptr);
	return cudaContext;
}