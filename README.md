# Ray Tracing in One Weekend

This project is an implementation of the "Ray Tracing in One Weekend" series using the Odin programming language.

url: https://raytracing.github.io/books/RayTracingInOneWeekend.html
![Rendered Image](output.png)

## Getting Started

### Prerequisites

- [Odin Programming Language](https://odin-lang.org/)
- [Visual Studio Code](https://code.visualstudio.com/)

### Building the Project

To build the project, run the following command in the terminal:

```sh
mkdir build
odin build . -debug -out:build/debug.exe
```

Alternatively, you can use the provided VS Code tasks:

Open the Command Palette (Ctrl+Shift+P) and select Tasks: Run Task.
Choose Build.
Running the Project
To run the project, you can use the provided VS Code launch configurations:

Open the Command Palette (Ctrl+Shift+P) and select Run: Start Debugging.
Choose either Debug - default or Debug - test.
Output
The rendered image will be saved as hello_image.ppm in the project root directory.
 
## Code Overview
Main Components
`main.odin`: Entry point of the application. Initializes the scene and starts the rendering process.
`camera.odin`: Defines the camera and its properties.
`hittable.odin`: Defines the objects that can be hit by rays.
`interval.odin`: Provides utility functions for handling intervals.
`material.odin`: Defines the materials and their properties.
`utils.odin`: Contains utility functions.
`vector3.odin`: Provides vector operations.

### Example Code
Here is an example of how materials are added to the scene in main.odin:

```odin
material1 := material(dieletric{1.5})
append(&world, Sphere{[3]f32{0, 1, 0}, 1.0, material1})

material2 := material(lambertian{[3]f32{0.4, 0.2, 0.1}})
append(&world, Sphere{[3]f32{-4, 1, 0}, 1.0, material2})

material3 := material(metalic{[3]f32{0.7, 0.6, 0.5}, 0.0})
append(&world, Sphere{[3]f32{4, 1, 0}, 1.0, material3})
```
