# Multi-Core Parallel Processing Implementation Plan

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [Parallelization Strategy](#parallelization-strategy)
4. [Thread Safety Analysis](#thread-safety-analysis)
5. [Step-by-Step Implementation Plan](#step-by-step-implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Performance Considerations](#performance-considerations)
8. [Risk Assessment](#risk-assessment)
9. [References](#references)

---

## Executive Summary

This document outlines a safe, step-by-step plan to add multi-core parallel processing to the Ray Tracing in One Weekend implementation written in Odin. The goal is to parallelize the rendering loop to utilize all available CPU cores, significantly reducing rendering time while maintaining correctness and image quality.

**Key Objectives:**
- Parallelize pixel rendering across multiple CPU cores
- Maintain thread safety and avoid race conditions
- Preserve image quality and correctness
- Achieve near-linear speedup with core count
- Keep the code maintainable and well-documented

---

## Current Architecture Analysis

### Current Rendering Pipeline

The current implementation follows a sequential rendering approach:

1. **Scene Setup** (`main.odin`):
   - Creates world geometry (spheres with various materials)
   - Configures camera parameters
   - Initializes output file

2. **Rendering Loop** (`camera.odin::render`):
   ```odin
   for j in 0..<camera.image_height {
       for i in 0..<camera.image_width {
           pixel_color := [3]f32{0, 0, 0}
           for s in 0..<camera.samples_per_pixel {
               r := get_ray(camera, f32(i), f32(j))
               pixel_color += ray_color(r, camera.max_depth, world)
           }
           pixel_color = pixel_color * camera.pixel_samples_scale
           write_color(&sb, pixel_color)
       }
   }
   ```

3. **Ray Tracing** (`vector3.odin::ray_color`):
   - Recursive ray tracing with depth limit
   - Intersection testing with world objects
   - Material scattering calculations

### Key Components

| Component | File | Thread Safety Status |
|-----------|------|---------------------|
| `render()` | `camera.odin` | **NOT THREAD-SAFE** - Sequential loop |
| `ray_color()` | `vector3.odin` | **THREAD-SAFE** - Pure function, read-only world |
| `get_ray()` | `camera.odin` | **NOT THREAD-SAFE** - Uses global RNG |
| `random_float()` | `utils.odin` | **NOT THREAD-SAFE** - Global RNG state |
| `write_color()` | `utils.odin` | **NOT THREAD-SAFE** - Shared string builder |
| `world` array | `main.odin` | **THREAD-SAFE** - Read-only after initialization |
| `Camera` struct | `camera.odin` | **THREAD-SAFE** - Read-only during rendering |

### Bottlenecks Identified

1. **Sequential Pixel Rendering**: Each pixel is rendered one at a time
2. **Global Random Number Generator**: Shared RNG state causes race conditions
3. **Shared String Builder**: Concurrent writes to output buffer
4. **Progress Bar Updates**: Concurrent updates may cause display issues

---

## Parallelization Strategy

### Approach: Tile-Based Parallel Rendering

**Rationale:**
- Divides image into rectangular tiles (e.g., 32x32 or 64x64 pixels)
- Each thread processes one tile at a time
- Better cache locality than row-based or pixel-based approaches
- Easier load balancing with work-stealing

### Alternative Approaches Considered

1. **Row-Based Parallelization**:
   - ✅ Simple to implement
   - ❌ Poor cache locality
   - ❌ Uneven workload (top/bottom rows may finish faster)

2. **Pixel-Based Parallelization**:
   - ✅ Fine-grained parallelism
   - ❌ High overhead from task scheduling
   - ❌ Poor cache locality

3. **Tile-Based Parallelization** (CHOSEN):
   - ✅ Good cache locality
   - ✅ Balanced workload
   - ✅ Reasonable task granularity
   - ✅ Easy to implement work-stealing

### Thread Pool Architecture

```
Main Thread
    │
    ├─> Create Thread Pool (N threads, N = CPU cores)
    │
    ├─> Divide image into tiles
    │
    ├─> Create work queue with all tiles
    │
    └─> Wait for all threads to complete
         │
         └─> Write results to output file
```

---

## Thread Safety Analysis

### Thread-Safe Components ✅

1. **`world: [dynamic]Object`**:
   - Read-only after scene initialization
   - No modifications during rendering
   - Safe for concurrent reads

2. **`Camera` struct**:
   - Immutable during rendering
   - All fields are read-only
   - Safe for concurrent reads

3. **`ray_color()` function**:
   - Pure function (no side effects)
   - Only reads from world array
   - Safe for concurrent execution

### Thread-Unsafe Components ❌

1. **Global Random Number Generator**:
   - **Problem**: `core:math/rand` uses global state
   - **Solution**: Per-thread RNG instances with unique seeds
   - **Implementation**: Thread-local storage or pass RNG as parameter

2. **String Builder in `render()`**:
   - **Problem**: Concurrent writes cause corruption
   - **Solution**: Per-thread pixel buffers, merge at end
   - **Implementation**: Array of pixel colors, write sequentially

3. **Progress Bar Updates**:
   - **Problem**: Concurrent updates cause flickering
   - **Solution**: Atomic counter or mutex-protected updates
   - **Implementation**: Atomic integer for completed tiles

4. **File Writing**:
   - **Problem**: Concurrent writes to same file
   - **Solution**: Collect all results, write sequentially
   - **Implementation**: Final sequential write after all threads complete

### Data Structures Needed

```odin
// Per-thread rendering context
RenderContext :: struct {
    camera: ^Camera,
    world: [dynamic]Object,
    rng: rand.Rand,  // Per-thread RNG
    tile_start_x: int,
    tile_start_y: int,
    tile_width: int,
    tile_height: int,
}

// Pixel buffer for collecting results
PixelBuffer :: struct {
    width: int,
    height: int,
    pixels: [][]f32,  // 2D array of [3]f32 colors
}

// Work queue for tiles
Tile :: struct {
    start_x: int,
    start_y: int,
    width: int,
    height: int,
}
```

---

## Step-by-Step Implementation Plan

### Phase 1: Preparation and Infrastructure

#### Step 1.1: Add Threading Imports
- **File**: `camera.odin`
- **Action**: Add `core:thread` and `core:sync` imports
- **Risk**: Low
- **Dependencies**: None

#### Step 1.2: Create Per-Thread RNG System
- **File**: `utils.odin`
- **Action**: 
  - Create `ThreadRNG` struct wrapping `rand.Rand`
  - Create `create_thread_rng(seed: u64)` procedure
  - Modify `random_float()` to accept optional RNG parameter
  - Keep backward compatibility with global RNG for non-parallel code
- **Risk**: Medium (must ensure all random calls use thread-local RNG)
- **Dependencies**: None
- **Testing**: Verify deterministic results with same seed

#### Step 1.3: Create Pixel Buffer Structure
- **File**: `camera.odin` or new `render_buffer.odin`
- **Action**:
  - Define `PixelBuffer` struct
  - Implement `create_pixel_buffer(width, height)`
  - Implement `set_pixel(buffer, x, y, color)`
  - Implement `write_buffer_to_ppm(buffer, file)`
- **Risk**: Low
- **Dependencies**: None

### Phase 2: Tile-Based Rendering Infrastructure

#### Step 2.1: Create Tile Structure and Work Queue
- **File**: `camera.odin`
- **Action**:
  - Define `Tile` struct
  - Create `generate_tiles(image_width, image_height, tile_size)` function
  - Create thread-safe work queue using `core:sync`
- **Risk**: Medium (must ensure thread-safe queue operations)
- **Dependencies**: Step 1.1

#### Step 2.2: Create Render Context Structure
- **File**: `camera.odin`
- **Action**:
  - Define `RenderContext` struct
  - Include camera, world, RNG, and tile information
- **Risk**: Low
- **Dependencies**: Step 1.2

#### Step 2.3: Extract Tile Rendering Function
- **File**: `camera.odin`
- **Action**:
  - Create `render_tile(context: RenderContext, buffer: ^PixelBuffer)` function
  - Extract pixel rendering logic from current `render()` loop
  - Ensure all random calls use context RNG
- **Risk**: Medium (must verify correctness)
- **Dependencies**: Steps 1.2, 2.1, 2.2
- **Testing**: Compare output with sequential version

### Phase 3: Thread Pool Implementation

#### Step 3.1: Create Thread Pool Wrapper
- **File**: `camera.odin` or new `thread_pool.odin`
- **Action**:
  - Create `ThreadPool` struct
  - Implement `create_thread_pool(num_threads: int)`
  - Implement `destroy_thread_pool(pool: ^ThreadPool)`
- **Risk**: Low
- **Dependencies**: Step 1.1

#### Step 3.2: Implement Worker Thread Function
- **File**: `camera.odin`
- **Action**:
  - Create `worker_thread(thread_id: int, work_queue: ^WorkQueue, ...)` procedure
  - Each thread:
     1. Creates its own RNG with unique seed
     2. Pulls tiles from work queue
     3. Renders tile to shared pixel buffer (with synchronization)
     4. Updates progress counter
     5. Repeats until queue is empty
- **Risk**: High (thread synchronization complexity)
- **Dependencies**: Steps 1.2, 2.1, 2.2, 2.3, 3.1
- **Testing**: Verify no race conditions with thread sanitizer (if available)

#### Step 3.3: Implement Progress Tracking
- **File**: `camera.odin`
- **Action**:
  - Use atomic integer for completed tile count
  - Update progress bar from main thread periodically
  - Or use mutex-protected progress counter
- **Risk**: Low
- **Dependencies**: Step 1.1

### Phase 4: Parallel Render Function

#### Step 4.1: Create Parallel Render Function
- **File**: `camera.odin`
- **Action**:
  - Create `render_parallel(camera, output, world, num_threads)` function
  - Steps:
     1. Create pixel buffer
     2. Generate tiles
     3. Create work queue
     4. Create thread pool
     5. Launch worker threads
     6. Wait for completion
     7. Write buffer to file
- **Risk**: Medium
- **Dependencies**: All previous steps

#### Step 4.2: Add Thread Count Configuration
- **File**: `main.odin` or `camera.odin`
- **Action**:
  - Add `num_threads` parameter to camera or render function
  - Default to `runtime.num_cores()` or `runtime.num_cores() - 1`
  - Allow command-line override
- **Risk**: Low
- **Dependencies**: None

#### Step 4.3: Update Main Function
- **File**: `main.odin`
- **Action**:
  - Replace `render()` call with `render_parallel()`
  - Or add flag to choose between sequential/parallel
- **Risk**: Low
- **Dependencies**: Step 4.1

### Phase 5: Optimization and Refinement

#### Step 5.1: Optimize Tile Size
- **File**: `camera.odin`
- **Action**:
  - Experiment with different tile sizes (16x16, 32x32, 64x64, 128x128)
  - Profile and choose optimal size
  - Consider making it configurable
- **Risk**: Low
- **Dependencies**: Step 4.1

#### Step 5.2: Implement Work Stealing (Optional)
- **File**: `camera.odin`
- **Action**:
  - If using work queue, implement work-stealing for better load balancing
  - Or use simpler approach: static tile assignment
- **Risk**: Medium (complexity)
- **Dependencies**: Step 3.2

#### Step 5.3: Memory Optimization
- **File**: `camera.odin`
- **Action**:
  - Review memory allocations in hot path
  - Consider object pooling for temporary structures
  - Profile memory usage
- **Risk**: Low
- **Dependencies**: Step 4.1

### Phase 6: Testing and Validation

#### Step 6.1: Correctness Testing
- **Action**:
  - Render same scene with sequential and parallel versions
  - Compare output images pixel-by-pixel
  - Account for floating-point differences (use epsilon comparison)
  - Test with different thread counts (1, 2, 4, 8, etc.)
- **Risk**: Medium (must handle non-determinism from RNG)
- **Dependencies**: All previous steps

#### Step 6.2: Performance Benchmarking
- **Action**:
  - Measure rendering time for various configurations
  - Test with different image sizes
  - Test with different sample counts
  - Calculate speedup ratio
- **Risk**: Low
- **Dependencies**: Step 6.1

#### Step 6.3: Thread Safety Testing
- **Action**:
  - Run with thread sanitizer (if available in Odin)
  - Stress test with many threads
  - Test edge cases (single pixel, very small images)
- **Risk**: Medium
- **Dependencies**: Step 4.1

---

## Testing Strategy

### Unit Tests

1. **Per-Thread RNG Test**:
   - Verify each thread produces different random sequences
   - Verify same seed produces same sequence

2. **Tile Generation Test**:
   - Verify all pixels are covered
   - Verify no overlapping tiles
   - Verify edge cases (image size < tile size)

3. **Pixel Buffer Test**:
   - Verify pixel setting and retrieval
   - Verify bounds checking

### Integration Tests

1. **Sequential vs Parallel Comparison**:
   - Render identical scene with both methods
   - Compare output images (allow small floating-point differences)
   - Verify visual correctness

2. **Multi-Thread Correctness**:
   - Render with 1, 2, 4, 8 threads
   - Verify all produce identical (or acceptably similar) results

3. **Progress Tracking Test**:
   - Verify progress bar updates correctly
   - Verify no race conditions in progress updates

### Performance Tests

1. **Speedup Measurement**:
   - Measure time for sequential rendering
   - Measure time for parallel rendering (various thread counts)
   - Calculate speedup: `T_sequential / T_parallel`
   - Target: Near-linear speedup up to core count

2. **Scalability Test**:
   - Test with different image sizes (400x225, 800x450, 1600x900)
   - Test with different sample counts (10, 50, 100, 200)
   - Verify performance scales appropriately

3. **Overhead Measurement**:
   - Measure thread creation overhead
   - Measure synchronization overhead
   - Identify bottlenecks

### Stress Tests

1. **High Thread Count**:
   - Test with more threads than CPU cores
   - Verify graceful degradation

2. **Edge Cases**:
   - Very small images (1x1, 10x10)
   - Very large images (4K, 8K)
   - Single tile scenarios

---

## Performance Considerations

### Expected Performance Gains

- **Theoretical Maximum**: N× speedup with N cores (ignoring overhead)
- **Realistic Expectation**: 70-90% efficiency (0.7N to 0.9N speedup)
- **Bottlenecks**:
  - Thread synchronization overhead
  - Memory bandwidth limitations
  - Cache misses
  - Load imbalance

### Optimization Opportunities

1. **Tile Size Tuning**:
   - Too small: High overhead, poor cache usage
   - Too large: Load imbalance, less parallelism
   - Optimal: Usually 32×32 to 128×128 pixels

2. **Memory Access Patterns**:
   - Tiles improve cache locality
   - Consider prefetching for next tile

3. **RNG Performance**:
   - Per-thread RNG avoids contention
   - Consider faster RNG algorithms if bottleneck

4. **Progress Updates**:
   - Update less frequently to reduce overhead
   - Use atomic operations for counter

### Monitoring and Profiling

- Profile with Odin's built-in profiler (if available)
- Measure time spent in:
  - Ray tracing (should dominate)
  - Synchronization (should be minimal)
  - Memory allocation (should be minimal)
  - File I/O (sequential, acceptable)

---

## Risk Assessment

### High Risk Areas

1. **Thread Synchronization**:
   - **Risk**: Race conditions, deadlocks
   - **Mitigation**: 
     - Use well-tested synchronization primitives
     - Keep critical sections minimal
     - Test thoroughly with thread sanitizer

2. **Random Number Generation**:
   - **Risk**: Non-deterministic results, thread safety issues
   - **Mitigation**:
     - Per-thread RNG with unique seeds
     - Document seed strategy
     - Test determinism

3. **Memory Safety**:
   - **Risk**: Buffer overflows, use-after-free
   - **Mitigation**:
     - Use Odin's bounds checking
     - Careful array indexing
     - Test edge cases

### Medium Risk Areas

1. **Performance Regression**:
   - **Risk**: Overhead makes parallel version slower for small images
   - **Mitigation**:
     - Keep sequential version as fallback
     - Auto-select based on image size
     - Profile and optimize hot paths

2. **Load Imbalance**:
   - **Risk**: Some threads finish early, reducing efficiency
   - **Mitigation**:
     - Use work-stealing or dynamic scheduling
     - Smaller tiles for better distribution

### Low Risk Areas

1. **Code Complexity**:
   - **Risk**: Harder to maintain
   - **Mitigation**:
     - Clear documentation
     - Well-commented code
     - Separation of concerns

2. **Platform Differences**:
   - **Risk**: Different behavior on different OS/architectures
   - **Mitigation**:
     - Test on multiple platforms
     - Use Odin's cross-platform abstractions

---

## Implementation Checklist

### Pre-Implementation
- [ ] Review Odin threading documentation
- [ ] Set up test environment
- [ ] Create backup of current working version
- [ ] Set up version control branch

### Phase 1: Preparation
- [ ] Add threading imports
- [ ] Implement per-thread RNG system
- [ ] Create pixel buffer structure
- [ ] Test per-thread RNG correctness

### Phase 2: Tile Infrastructure
- [ ] Create tile structure
- [ ] Implement tile generation
- [ ] Create work queue
- [ ] Create render context
- [ ] Extract tile rendering function
- [ ] Test tile rendering correctness

### Phase 3: Threading
- [ ] Create thread pool wrapper
- [ ] Implement worker thread function
- [ ] Implement progress tracking
- [ ] Test thread safety

### Phase 4: Integration
- [ ] Create parallel render function
- [ ] Add thread count configuration
- [ ] Update main function
- [ ] Test end-to-end functionality

### Phase 5: Optimization
- [ ] Optimize tile size
- [ ] Profile performance
- [ ] Optimize hot paths
- [ ] Memory optimization

### Phase 6: Testing
- [ ] Correctness tests
- [ ] Performance benchmarks
- [ ] Thread safety tests
- [ ] Edge case tests
- [ ] Documentation updates

---

## References

### Ray Tracing Resources
- [Ray Tracing in One Weekend](https://raytracing.github.io/books/RayTracingInOneWeekend.html) - Main reference book
- [Ray Tracing: The Next Week](https://raytracing.github.io/books/RayTracingTheNextWeek.html) - Advanced techniques
- [Ray Tracing: The Rest of Your Life](https://raytracing.github.io/books/RayTracingTheRestOfYourLife.html) - Advanced topics

### Odin Language Resources
- [Odin Language Documentation](https://odin-lang.org/docs/) - Official documentation
- [Odin GitHub Repository](https://github.com/odin-lang/Odin) - Source code and examples
- Odin `core:thread` package documentation
- Odin `core:sync` package documentation

### Parallel Ray Tracing Examples
- [GPSnoopy's RayTracingInOneWeekend](https://github.com/GPSnoopy/RayTracingInOneWeekend) - C++ implementation with multi-threading
- Various other implementations on GitHub with parallel processing

### Threading Best Practices
- "The Art of Multiprocessor Programming" by Herlihy & Shavit
- "C++ Concurrency in Action" by Anthony Williams (concepts apply generally)

---

## Appendix: Code Structure Preview

### Proposed File Structure

```
RT_Weekend/
├── main.odin              # Entry point, scene setup
├── camera.odin            # Camera, rendering (parallel version)
├── hittable.odin          # Geometry, intersections
├── material.odin          # Materials, scattering
├── vector3.odin           # Vector math, ray_color
├── utils.odin             # Utilities, RNG (thread-safe version)
├── interval.odin          # Interval math
└── PARALLELIZATION_PLAN.md # This document
```

### Key Function Signatures (Proposed)

```odin
// Per-thread RNG
ThreadRNG :: struct {
    rng: rand.Rand,
}

create_thread_rng :: proc(seed: u64) -> ThreadRNG
random_float_threaded :: proc(rng: ^ThreadRNG) -> f32

// Tile rendering
Tile :: struct {
    start_x, start_y: int,
    width, height: int,
}

RenderContext :: struct {
    camera: ^Camera,
    world: [dynamic]Object,
    rng: ThreadRNG,
    tile: Tile,
}

render_tile :: proc(context: RenderContext, buffer: ^PixelBuffer)

// Parallel rendering
render_parallel :: proc(
    camera: ^Camera,
    output: Output,
    world: [dynamic]Object,
    num_threads: int = 0,  // 0 = auto-detect
)
```

---

## Conclusion

This plan provides a comprehensive, step-by-step approach to adding multi-core parallel processing to the ray tracer. By following this plan carefully and testing at each phase, we can safely implement parallelization while maintaining correctness and achieving significant performance improvements.

The key to success is:
1. **Incremental development** - One step at a time
2. **Thorough testing** - Verify correctness at each phase
3. **Thread safety first** - Address all thread safety concerns before optimization
4. **Performance measurement** - Profile and optimize based on data

Good luck with the implementation!

