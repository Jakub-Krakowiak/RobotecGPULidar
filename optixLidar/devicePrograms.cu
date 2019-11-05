// ======================================================================== //
// Copyright 2018-2019 Ingo Wald                                            //
//                                                                          //
// Licensed under the Apache License, Version 2.0 (the "License");          //
// you may not use this file except in compliance with the License.         //
// You may obtain a copy of the License at                                  //
//                                                                          //
//     http://www.apache.org/licenses/LICENSE-2.0                           //
//                                                                          //
// Unless required by applicable law or agreed to in writing, software      //
// distributed under the License is distributed on an "AS IS" BASIS,        //
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. //
// See the License for the specific language governing permissions and      //
// limitations under the License.                                           //
// ======================================================================== //

#include <optix_device.h>
#include <cuda_runtime.h>

#include "LaunchParams.h"
  
/*! launch parameters in constant memory, filled in by optix upon
    optixLaunch (this gets filled in from the buffer we pass to
    optixLaunch) */
extern "C" __constant__ LaunchParams optixLaunchParams;
extern "C" __constant__ LaunchLidarParams optixLaunchLidarParams;
  
static __forceinline__ __device__
void *unpackPointer( uint32_t i0, uint32_t i1 )
{
    const uint64_t uptr = static_cast<uint64_t>( i0 ) << 32 | i1;
    void*           ptr = reinterpret_cast<void*>( uptr ); 
    return ptr;
}

static __forceinline__ __device__
void  packPointer( void* ptr, uint32_t& i0, uint32_t& i1 )
{
    const uint64_t uptr = reinterpret_cast<uint64_t>( ptr );
    i0 = uptr >> 32;
    i1 = uptr & 0x00000000ffffffff;
}

template<typename T>
static __forceinline__ __device__ T *getPRD()
{ 
    const uint32_t u0 = optixGetPayload_0();
    const uint32_t u1 = optixGetPayload_1();
    return reinterpret_cast<T*>( unpackPointer( u0, u1 ) );
}
  
//------------------------------------------------------------------------------
// closest hit and anyhit programs for radiance-type rays.
//
// Note eventually we will have to create one pair of those for each
// ray type and each geometry type we want to render; but this
// simple example doesn't use any actual geometries yet, so we only
// create a single, dummy, set of them (we do have to have at least
// one group of them to set up the SBT)
//------------------------------------------------------------------------------
  
extern "C" __global__ void __closesthit__shadow()
{
    /* not going to be used ... */
}
  
extern "C" __global__ void __closesthit__radiance()
{
    
    // download model triangles
    const TriangleMeshSBTData &sbtData
      = *(const TriangleMeshSBTData*)optixGetSbtDataPointer();

    // compute normal:
    const int   primID = optixGetPrimitiveIndex(); // this trinagle we hit
    const vec3i index  = sbtData.index[primID];
    const vec3f &A     = sbtData.vertex[index.x];
    const vec3f &B     = sbtData.vertex[index.y];
    const vec3f &C     = sbtData.vertex[index.z];
    const float u = optixGetTriangleBarycentrics().x;
    const float v = optixGetTriangleBarycentrics().y;
    
    vec3f hitPoint = vec3f((1-u-v)*A + u*B + v*C);
    
    // variable packed in raycasting, for coloring, we have to set it here, so color can be set later in rendering program
    vec3f &prd = *(vec3f*)getPRD<vec3f>(); 
    
    // check in position buffer if this point is hit by lidar
    // if yes, set it to red
    // if no, continue calculating color
    
    // change points precision
    vec3i hitPointI = vec3i((int)(hitPoint.x*1), (int)(hitPoint.y*1), (int)(hitPoint.z*1));
    vec3f hitPointF = vec3f(hitPointI.x/1.f, hitPointI.y/1.f, hitPointI.z/1.f);
    
    for (int i = 0; i < optixLaunchParams.frame.lidarSize; ++i)
    {
        if ((hitPointF.x == optixLaunchParams.frame.lidarBuffer[i*3+0]) &&
            (hitPointF.y == optixLaunchParams.frame.lidarBuffer[i*3+1]) &&
            (hitPointF.z == optixLaunchParams.frame.lidarBuffer[i*3+2]))
        {
//printf("lidar point!\n%f %f %f\n%f %f %f\n%f %f %f\n\n", hitPoint.x, hitPoint.y, hitPoint.z, hitPointF.x, hitPointF.y, hitPointF.z, optixLaunchParams.frame.lidarBuffer[i*3+0], optixLaunchParams.frame.lidarBuffer[i*3+1], optixLaunchParams.frame.lidarBuffer[i*3+2]);
            prd = vec3f(1.f, 0.f, 0.f);
            return;
        }
    }
    
    vec3f Ng = cross(B-A,C-A);
    vec3f Ns = (sbtData.normal)
        ? ((1.f-u-v) * sbtData.normal[index.x]
           +       u * sbtData.normal[index.y]
           +       v * sbtData.normal[index.z])
        : Ng;
      
    const vec3f rayDir = optixGetWorldRayDirection();
    
    if (dot(rayDir,Ng) > 0.f) Ng = -Ng;
    Ng = normalize(Ng);
    
    if (dot(Ng,Ns) < 0.f)
        Ns -= 2.f*dot(Ng,Ns)*Ng;
    Ns = normalize(Ns);
    
    vec3f diffuseColor = sbtData.color;
    if (sbtData.hasTexture && sbtData.texcoord)
    {
        const vec2f tc
            = (1.f-u-v) * sbtData.texcoord[index.x]
            +         u * sbtData.texcoord[index.y]
            +         v * sbtData.texcoord[index.z];
      
      vec4f fromTexture = tex2D<float4>(sbtData.texture,tc.x,tc.y);
      diffuseColor *= (vec3f)fromTexture;
    }
    
    // ------------------------------------------------------------------
    // compute shadow
    // ------------------------------------------------------------------
    const vec3f surfPos
        = (1.f-u-v) * sbtData.vertex[index.x]
        +         u * sbtData.vertex[index.y]
        +         v * sbtData.vertex[index.z];
    const vec3f lightPos(-907.108f, 2205.875f, -400.0267f);
    const vec3f lightDir = lightPos - surfPos;
    
    // trace shadow ray:
    vec3f lightVisibility = 0.f;
    // the values we store the PRD pointer in:
    uint32_t u0, u1;
    packPointer( &lightVisibility, u0, u1 );
/*
    optixTrace(optixLaunchParams.traversable,
               surfPos + 1e-3f * Ng,
               lightDir,
               1e-3f,      // tmin
               1.f-1e-3f,  // tmax
               0.0f,       // rayTime
               OptixVisibilityMask( 255 ),
               // For shadow rays: skip any/closest hit shaders and terminate on first
               // intersection with anything. The miss shader is used to mark if the
               // light was visible.
               OPTIX_RAY_FLAG_DISABLE_ANYHIT
               | OPTIX_RAY_FLAG_TERMINATE_ON_FIRST_HIT
               | OPTIX_RAY_FLAG_DISABLE_CLOSESTHIT,
               SHADOW_RAY_TYPE,            // SBT offset
               RAY_TYPE_COUNT,               // SBT stride
               SHADOW_RAY_TYPE,            // missSBTIndex 
               u0, u1 );
*/
    // ------------------------------------------------------------------
    // final shading: a bit of ambient, a bit of directional ambient,
    // and directional component based on shadowing
    // ------------------------------------------------------------------
    const float cosDN
        = 1.f
        + .8f*fabsf(dot(rayDir,Ns));
    
    prd = (.1f + (.2f + .8f*lightVisibility) * cosDN) * diffuseColor;
}

extern "C" __global__ void __anyhit__radiance()
{ /*! for this simple example, this will remain empty */ }

extern "C" __global__ void __anyhit__shadow()
{ /*! not going to be used */ }
  
//------------------------------------------------------------------------------
// miss program that gets called for any ray that did not have a
// valid intersection
//
// this is background
// ------------------------------------------------------------------------------

extern "C" __global__ void __miss__radiance()
{
    vec3f &prd = *(vec3f*)getPRD<vec3f>();
    // set to constant white as background color
    prd = vec3f(1.f);
}

extern "C" __global__ void __miss__shadow()
{
    // we didn't hit anything, so the light is visible
    vec3f &prd = *(vec3f*)getPRD<vec3f>();
    prd = vec3f(1.f);
}

//------------------------------------------------------------------------------
// ray gen program - the actual rendering happens in here
//------------------------------------------------------------------------------
extern "C" __global__ void __raygen__renderFrame()
{
    const int ix = optixGetLaunchIndex().x;
    const int iy = optixGetLaunchIndex().y;

    const auto &camera = optixLaunchParams.camera;

    // our per-ray data for this example. what we initialize it to
    // won't matter, since this value will be overwritten by either
    // the miss or hit program, anyway
    vec3f pixelColorPRD = vec3f(0.f);

    // the values we store the PRD pointer in:
    uint32_t u0, u1;
    packPointer( &pixelColorPRD, u0, u1 );

    // normalized screen plane position, in [0,1]^2
    const vec2f screen(vec2f(ix+.5f,iy+.5f)
                       / vec2f(optixLaunchParams.frame.size));
    
    // generate ray direction
    vec3f rayDir = normalize(camera.direction
                             + (screen.x - 0.5f) * camera.horizontal
                             + (screen.y - 0.5f) * camera.vertical);

    optixTrace(optixLaunchParams.traversable,
               camera.position, // from
               rayDir, // direction
               0.f,    // tmin
               1e20f,  // tmax
               0.0f,   // rayTime
               OptixVisibilityMask( 255 ),
               OPTIX_RAY_FLAG_DISABLE_ANYHIT,//OPTIX_RAY_FLAG_NONE,
               RADIANCE_RAY_TYPE,             // SBT offset
               RAY_TYPE_COUNT,               // SBT stride
               RADIANCE_RAY_TYPE,             // missSBTIndex 
               u0, u1 );

    const int r = int(255.99f*pixelColorPRD.x);
    const int g = int(255.99f*pixelColorPRD.y);
    const int b = int(255.99f*pixelColorPRD.z);

    // convert to 32-bit rgba value (alpha set to 0xff)
    const uint32_t rgba = 0xff000000 | (r<<0) | (g<<8) | (b<<16);

    // and write to frame buffer ...
    const uint32_t fbIndex = ix+iy*optixLaunchParams.frame.size.x;
    optixLaunchParams.frame.colorBuffer[fbIndex] = rgba;
}

//-------------------------------- lidar part --------------------------------

  template<typename T>
  static __forceinline__ __device__ T *getHitPRD()
  { 
    const uint32_t u2 = optixGetPayload_2();
    return reinterpret_cast<T*>( unpackPointer( u2 ) );
  }
  
  extern "C" __global__ void __closesthit__lidar()
  {
//printf("hit\n");
    const TriangleMeshSBTData &sbtData
      = *(const TriangleMeshSBTData*)optixGetSbtDataPointer();
    
    const int   primID = optixGetPrimitiveIndex();
    const vec3i index  = sbtData.index[primID];
    const float u = optixGetTriangleBarycentrics().x;
    const float v = optixGetTriangleBarycentrics().y;

    const vec3f &A     = sbtData.vertex[index.x];
    const vec3f &B     = sbtData.vertex[index.y];
    const vec3f &C     = sbtData.vertex[index.z];
    
    vec3f &prd = *(vec3f*)getPRD<vec3f>();
    prd = vec3f((1-u-v)*A + u*B + v*C);
    
//printf("A %f, %f, %f\n", A.x, A.y, A.z);
//printf("B %f, %f, %f\n", B.x, B.y, B.z);
//printf("C %f, %f, %f\n", C.x, C.y, C.z);
//printf("bary %f %f\n", u, v);
//printf("%f, %f, %f\n", prd.x, prd.y, prd.z);
    
    optixSetPayload_2(1);
    
  }
  
  extern "C" __global__ void __anyhit__lidar()
  { /*! for this simple example, this will remain empty */ }


  extern "C" __global__ void __miss__lidar()
  {
//printf("miss\n");
    vec3f &prd = *(vec3f*)getPRD<vec3f>();
    // set to constant white as background color
    prd = vec3f(0.f);
    optixSetPayload_2(0);
  }
  
  extern "C" __global__ void __raygen__renderLidar()
  {
    const int ix = optixGetLaunchIndex().x;

    vec3f pixelPositionPRD = vec3f(0.f);
    pixelPositionPRD.x = 0.f;
    pixelPositionPRD.y = 0.f;
    pixelPositionPRD.z = 0.f;

    // the values we store the PRD pointer in:
    uint32_t u0, u1, u2;
    packPointer( &pixelPositionPRD, u0, u1 );
    
    vec3f from = vec3f(optixLaunchLidarParams.rayBuffer[ix*6], optixLaunchLidarParams.rayBuffer[ix*6+1], optixLaunchLidarParams.rayBuffer[ix*6+2]);
    vec3f dir = vec3f(optixLaunchLidarParams.rayBuffer[ix*6+3], optixLaunchLidarParams.rayBuffer[ix*6+4], optixLaunchLidarParams.rayBuffer[ix*6+5]);

//printf("from %f %f %f\n", from.x, from.y, from.z);
//printf("direction %f %f %f\n", dir.x, dir.y, dir.z);

    optixTrace(optixLaunchLidarParams.traversable,
               from, // from
               dir, // direction
               0.f,    // tmin
               1e20f,  // tmax
               0.0f,   // rayTime
               OptixVisibilityMask( 255 ),
               OPTIX_RAY_FLAG_DISABLE_ANYHIT,//OPTIX_RAY_FLAG_NONE,
               LIDAR_RAY_TYPE,               // SBT offset
               LIDAR_RAY_TYPE_COUNT,               // SBT stride
               LIDAR_RAY_TYPE,               // missSBTIndex 
               u0, u1, u2 );

    if (u2)
    {
        // change points precision
        vec3i pixelPositionI = vec3i((int)(pixelPositionPRD.x*1), (int)(pixelPositionPRD.y*1), (int)(pixelPositionPRD.z*1));
        pixelPositionPRD.x = pixelPositionI.x/1.f;
        pixelPositionPRD.y = pixelPositionI.y/1.f;
        pixelPositionPRD.z = pixelPositionI.z/1.f;
        
      optixLaunchLidarParams.positionBuffer[ix*3  ] = pixelPositionPRD.x;
      optixLaunchLidarParams.positionBuffer[ix*3+1] = pixelPositionPRD.y;
      optixLaunchLidarParams.positionBuffer[ix*3+2] = pixelPositionPRD.z;
      optixLaunchLidarParams.hitBuffer[ix] = 1;
    }
    else
    {
      optixLaunchLidarParams.hitBuffer[ix] = 0;
    }
    
  }
