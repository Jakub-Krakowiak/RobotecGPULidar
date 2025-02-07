# Change Log

## [0.14.1] 5 July 2023

### Fixed
- Fixed building `PCL` on Windows
  - `vcpkg` tag has been updated
  - `PCL` version has been upgraded (1.12.0 -> 1.13.0)
- Fixed `rclcpp` (`ROS2` package) initialization
  - `RGL` checks whether `rclcpp` is already initialized
  - Resolved `spdlog` conflict between `RGL` and `rclcpp` by downgrading its version on the `RGL` site (1.10.0 -> 1.9.2)

## [0.14.0] 22 June 2023

### Added

- Added feature to query in runtime if specific extensions were compiled in the binary
  - Added API call:
    - `rgl_get_extension_info`
  - Created a tool that prints all the extensions in the given RGL binary:
    - `inspectLibRGL`
- Added instance/semantic segmentation feature
  - Added API call to set the ID of the entity:
    - `rgl_entity_set_id`
  - Added a new field that can be returned:
    - `RGL_FIELD_ENTITY_ID_I32`
- Added material information reading and converting to intensity based on intensity texture assigned to the entity:
  - Added API calls:
    - `rgl_mesh_set_texture_coords`
    - `rgl_entity_set_intensity_texture`
    - `rgl_texture_create`
    - `rgl_texture_destroy`
- Added publishing raw lidar packets via UDP
  - In the closed-source version only
- Added unity tests to field `RGL_FIELD_DISTANCE_F32`

### Changed

- Changed value of non-hits points from `CUDART_INF_F` to `FLT_MAX`
- Updated docker README information

### Known Issues
- `rclcpp` (`ROS2` package) is always initialized by `RGL`. It could cause a double initialization if the client's code also did it before `RGL`.
  - Fixed in v0.14.1

## [0.13.1] 19 April 2023

### Fixed
- Improved performance of temporal merge node.
  - The node doubles the array capacity if it's running out (instead of reallocating every iteration).

### Changed
- Point cloud formatting for `rgl_graph_write_pcd_file` is performed on the CPU now.
  - We prefer to avoid transferring huge point cloud to GPU (risk of cuda out of memory error).

### Known Issues
- `rgl_graph_write_pcd_file` causes SEH exception on Windows when trying to save point cloud with ~375 000 000 or more points.
  - The issue has been reported to PCL ([link](https://github.com/PointCloudLibrary/pcl/issues/5674)).
- `rclcpp` (`ROS2` package) is always initialized by `RGL`. It could cause a double initialization if the client's code also did it before `RGL`.
  - Fixed in v0.14.1

## [0.13.0] 29 March 2023

### Added
- Reimplemented Gaussian Noise from RGL v10
  - Added API calls:
    - `rgl_node_gaussian_noise_angular_ray`
    - `rgl_node_gaussian_noise_angular_hitpoint`
    - `rgl_node_gaussian_noise_distance`
- Added nodes for spatial and temporal point clouds merge
  - Added API calls:
    - `rgl_node_points_spatial_merge`
    - `rgl_node_points_temporal_merge`
- Added node providing a user-defined point cloud to the RGL pipeline (for testing purposes)
  - Added API call:
    - `rgl_node_points_from_array`
- Added parameterized tests for:
  - `rgl_node_points_from_array`
  - `rgl_node_points_transform`
- Updated API surface tests
- Added support for multi-raytrace graphs

### Changed
- Separated PCL nodes and created PCL extension
- Converted node `WritePCDFilePointsNode` into single API call
  - Removed API call `rgl_node_points_write_pcd_file`
  - Added API call `rgl_graph_write_pcd_file`

### Fixed
- Fixed `--build-dir` flag in `setup.py` script

### Removed
- Removed `rgl_graph_node_set_active` API call

### Known Issues
- `rclcpp` (`ROS2` package) is always initialized by `RGL`. It could cause a double initialization if the client's code also did it before `RGL`.
  - Fixed in v0.14.1

## [0.12.0] 8 March 2023

### Added
- ROS2 extension providing a node to publish point cloud into ROS2 topic
  - Added API calls (`rgl/api/extensions/ros2.h`):
    - `rgl_node_points_ros2_publish`
    - `rgl_node_points_ros2_publish_with_qos`
  - Necessary scripting to build ROS2 integration in the standalone mode (not requiring ROS2 installation)
- API call for setting time on the scene
- TapeVisualizer tool (PoC)
  - Currently, it does not handle multiple graphs in the tape, to be improved

### Changed
- Rewritten build script from bash to python to enable easy building on Windows

### Fixed
- Minor fixes and refactor in the Tape code
  - Use safer .at() instead of operator[]
  - Using alias type APIObjectID instead of size_t

### Known Issues
- `rclcpp` (`ROS2` package) is always initialized by `RGL`. It could cause a double initialization if the client's code also did it before `RGL`.
  - Fixed in v0.14.1

## [0.11.3] 11 January 2023

### Added
- API call for tape recording activation status

### Fixed
- Fixed dependencies for tapePlayer tool
- Handle invalid logger configuration properly
- Handle empty path passed to tape

## [0.11.2] 1 December 2022

### Added
- RGL Auto Tape - feature to start Tape on the first API call writing to a path given in compile-time. 

### Changed
- Improved control flow around API initialization and error reporting

### Fixed
- Release build on Linux no longer use debug builds of dependencies (e.g., libPCL)
- Fixed a hidden bug in CacheManager - unsafe removing while iterating

## [0.11.1] 28 November 2022

### Fixed
- CUDA Runtime is now linked statically.

## [0.11.0] - 22 November 2022

The initial release.
