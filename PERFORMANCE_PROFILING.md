# Performance Profiling Guide

This document explains how to measure and profile the performance of the ray tracer.

## Built-in Timing

The ray tracer includes built-in timing functionality that automatically measures rendering performance.

### What Gets Measured

After each render, the program displays:
- **Total rendering time** - How long the rendering took
- **Image statistics** - Image dimensions and total pixels
- **Sample statistics** - Samples per pixel and total samples
- **Performance metrics**:
  - Pixels per second
  - Samples per second
  - Formatted with K (thousands) or M (millions) prefixes when appropriate

### Example Output

```
============================================================
Performance Statistics:
============================================================
  Total rendering time: 1.23 s
  Image size: 50x50 pixels (2500 total pixels)
  Samples per pixel: 5
  Total samples: 12500
  Rendering speed: 2037.14 pixels/sec
  Sample rate: 10185.72 samples/sec
  Rendering speed: 2.04 K pixels/sec
============================================================
```

## Using the Timing Functions

The timing utilities are located in `utils.odin`:

### Basic Usage

```odin
// Start a timer
timer := start_timer()

// ... do work ...

// Stop the timer
stop_timer(&timer)

// Get elapsed time
elapsed_seconds := get_elapsed_seconds(timer)
elapsed_ms := get_elapsed_milliseconds(timer)

// Format duration as string
duration_str := format_duration(timer)  // e.g., "1.23 s", "45.67 ms"

// Print comprehensive statistics
print_timing_stats(timer, width, height, samples_per_pixel)
```

### Timer Structure

```odin
Timer :: struct {
    start_time: time.Time,
    end_time: time.Time,
    elapsed: time.Duration,
}
```

## Advanced Profiling Options

### 1. Tracy Profiler (External)

For detailed, real-time profiling with nanosecond resolution:

1. **Install Tracy**:
   ```bash
   git clone --recurse-submodules https://github.com/oskarnp/odin-tracy
   ```

2. **Build Tracy Server** (Linux):
   ```bash
   cd tracy/profiler/build/unix
   make release LEGACY=1
   ./Tracy-release
   ```

3. **Integrate into your code**:
   ```odin
   import "tracy"
   
   main :: proc() {
       tracy.init()
       defer tracy.shutdown()
       
       // Your code here
       tracy.frame_mark()
   }
   ```

4. **Compile with Tracy enabled**:
   ```bash
   odin build . -define:TRACY_ENABLE=true
   ```

### 2. Spall Profiler

Odin has built-in support for Spall, a lightweight profiler:

1. Enable Spall in your build:
   ```bash
   odin build . -spall
   ```

2. View the profile with Spall viewer

### 3. Valgrind (Linux)

For memory and performance profiling:

```bash
valgrind --tool=callgrind ./build/debug -w 100 -h 100 -s 10
kcachegrind callgrind.out.*
```

## Benchmarking Tips

### 1. Consistent Testing

- Use the same scene configuration
- Test on the same hardware
- Close other applications
- Run multiple times and average results

### 2. What to Measure

- **Rendering time** - Total time to render the image
- **Pixels per second** - Throughput metric
- **Samples per second** - Ray tracing performance
- **Memory usage** - Use system tools (htop, valgrind)

### 3. Comparing Performance

Before and after optimizations:

```bash
# Baseline
./build/debug -w 800 -h 450 -s 100 -o baseline.ppm

# After optimization
./build/debug -w 800 -h 450 -s 100 -o optimized.ppm
```

Compare the "Total rendering time" and "Sample rate" metrics.

### 4. Scaling Tests

Test performance at different scales:

```bash
# Small image
./build/debug -w 100 -h 100 -s 10

# Medium image
./build/debug -w 400 -h 225 -s 50

# Large image
./build/debug -w 1600 -h 900 -s 100
```

This helps identify performance bottlenecks and scalability issues.

## Performance Metrics Explained

### Pixels per Second

Measures how many pixels are rendered per second. Higher is better.
- Typical range: 1,000 - 100,000 pixels/sec (depends on hardware and scene complexity)

### Samples per Second

Measures how many ray samples are processed per second. This is the core ray tracing metric.
- Typical range: 10,000 - 10,000,000 samples/sec (depends on hardware)

### Factors Affecting Performance

1. **Image size** - Larger images take more time (linear scaling)
2. **Samples per pixel** - More samples = better quality but slower (linear scaling)
3. **Scene complexity** - More objects = slower ray-object intersection tests
4. **Ray depth** - Deeper recursion = more computation
5. **Material complexity** - Some materials require more computation

## Example Benchmark Script

```bash
#!/bin/bash

echo "Ray Tracer Performance Benchmark"
echo "================================="
echo ""

# Test 1: Small image, few samples
echo "Test 1: 100x100, 10 samples"
time ./build/debug -w 100 -h 100 -s 10 -o test1.ppm 2>&1 | grep "Total rendering time"

# Test 2: Medium image, medium samples
echo "Test 2: 400x225, 50 samples"
time ./build/debug -w 400 -h 225 -s 50 -o test2.ppm 2>&1 | grep "Total rendering time"

# Test 3: Large image, many samples
echo "Test 3: 800x450, 100 samples"
time ./build/debug -w 800 -h 450 -s 100 -o test3.ppm 2>&1 | grep "Total rendering time"
```

## Troubleshooting

### Timing seems inaccurate

- Make sure you're measuring only the rendering phase (not file I/O)
- Close other applications that might affect CPU time
- Run multiple times and average

### Performance is slower than expected

- Check CPU usage (should be near 100% for single-threaded)
- Check for memory swapping (use `free -h` on Linux)
- Profile with Tracy or Valgrind to find bottlenecks

## Future: Parallel Processing Profiling

When parallel processing is implemented, additional metrics will be useful:

- **Speedup ratio** - Sequential time / Parallel time
- **Efficiency** - Speedup / Number of cores
- **Load balance** - How evenly work is distributed
- **Thread overhead** - Time spent on synchronization

These metrics will help optimize the parallel implementation.

