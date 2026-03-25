# vk_ctx Vulkan Resource Ownership Audit

## Objective

Reduce duplicated Vulkan resource ownership and keep command-pool lifecycle centralized in `vk_ctx`.

## Changes Applied

- GPU backend no longer creates/destroys a dedicated command pool.
- `raytrace/gpu_backend_vulkan.odin` now allocates command buffers from `ctx.compute_command_pool`.
- Command buffer free now uses `ctx.compute_command_pool` and leaves pool destruction to `vk_ctx.vulkan_context_destroy`.

## Ownership Model

- `vk_ctx` owns:
  - logical device
  - queues
  - sync primitives
  - graphics/compute command pools
- `raytrace` Vulkan backend owns:
  - command buffer allocated from `vk_ctx` pool
  - compute pipeline
  - scene/output buffers

## Safety Notes

- Avoid per-backend command-pool duplication to reduce teardown complexity.
- Keep queue-family compatibility aligned with `compute_command_pool` selection in `vk_ctx`.
