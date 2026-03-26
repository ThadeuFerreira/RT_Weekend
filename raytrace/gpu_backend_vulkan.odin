package raytrace

import "core:fmt"
import "core:math"
import "core:mem"
import "core:time"

import vk "vendor:vulkan"

import "RT_Weekend:vk_ctx"

RAYTRACE_VK_SPV :: #load("../assets/shaders/raytrace_vk.comp.spv")

VulkanGPUBackend :: struct {
    ctx:            vk_ctx.VulkanContext,
    pipeline:       vk_ctx.VulkanComputePipeline,
    buffers:        [8]vk_ctx.VulkanBuffer, // 0=ubo, 1=spheres, 2=bvh, 3=output, 4=quads, 5=volumes, 6=volume_quads, 7=image_textures
    command_buffer: vk.CommandBuffer,
    width:          int,
    height:         int,
    current_sample: int,
    total_samples:  int,
    cached_uniforms: GPUCameraUniforms,
    dispatch_total_ns: i64,
    readback_total_ns: i64,
}

@(private)
_vk_create_ssbo_with_header :: proc(
    ctx: ^vk_ctx.VulkanContext,
    body: rawptr,
    body_size: int,
) -> (vk_ctx.VulkanBuffer, bool) {
    total := size_of([4]i32) + max(body_size, 1)
    buf, ok := vk_ctx.create_host_visible_buffer(
        ctx.device,
        ctx.physical_device,
        vk.DeviceSize(total),
        {.STORAGE_BUFFER},
    )
    if !ok {
        return buf, false
    }
    header := [4]i32{0, 0, 0, 0}
    mem.copy(buf.mapped, &header, size_of([4]i32))
    if body_size > 0 && body != nil {
        dst := rawptr(uintptr(buf.mapped) + uintptr(size_of([4]i32)))
        mem.copy(dst, body, body_size)
    }
    return buf, true
}

@(private)
_vk_backend_init :: proc(
    cam:          ^Camera,
    world:        []Object,
    spheres:      []GPUSphere,
    quads:        []GPUQuad,
    bvh:          []LinearBVHNode,
    volumes:      []GPUVolume,
    volume_quads: []GPUQuad,
    total:        int,
    image_list:   []^Texture_Image,
) -> (rawptr, bool) {
    _ = world

    b := new(VulkanGPUBackend)
    b.width = cam.image_width
    b.height = cam.image_height
    b.total_samples = total
    b.cached_uniforms = _camera_to_gpu_uniforms(cam, total, 0)

    // In the editor process, avoid GLFW null platform mode to preserve UI/input behavior.
    // Use Vulkan loader directly; avoid touching GLFW state in the editor process.
    ctx, ok := vk_ctx.vulkan_context_init_headless(false, false)
    if !ok {
        free(b)
        return nil, false
    }
    b.ctx = ctx
    // Raylib owns the application's windowing lifecycle.
    b.ctx.glfw_owned = false

    pipe, pipe_ok := vk_ctx.create_vulkan_compute_pipeline(b.ctx.device, RAYTRACE_VK_SPV)
    if !pipe_ok {
        vk_ctx.vulkan_context_destroy(&b.ctx)
        free(b)
        return nil, false
    }
    b.pipeline = pipe

    // Buffer 0: camera UBO
    ubo, ubo_ok := vk_ctx.create_host_visible_buffer(
        b.ctx.device,
        b.ctx.physical_device,
        vk.DeviceSize(size_of(GPUCameraUniforms)),
        {.UNIFORM_BUFFER},
    )
    if !ubo_ok {
        vk_ctx.destroy_vulkan_compute_pipeline(b.ctx.device, &b.pipeline)
        vk_ctx.vulkan_context_destroy(&b.ctx)
        free(b)
        return nil, false
    }
    b.buffers[0] = ubo
    vk_ctx.update_buffer_data(&b.buffers[0], 0, &b.cached_uniforms, size_of(GPUCameraUniforms))

    // Buffers 1/2/4/5/6: scene SSBOs
    sphere_size := len(spheres) * size_of(GPUSphere)
    s_buf, s_ok := _vk_create_ssbo_with_header(&b.ctx, raw_data(spheres), sphere_size)
    if !s_ok { _vk_destroy((^VulkanGPUBackend)(b)); return nil, false }
    b.buffers[1] = s_buf
    s_header := [4]i32{i32(len(spheres)), 0, 0, 0}
    vk_ctx.update_buffer_data(&b.buffers[1], 0, &s_header, size_of([4]i32))

    bvh_size := len(bvh) * size_of(LinearBVHNode)
    bvh_buf, bvh_ok := _vk_create_ssbo_with_header(&b.ctx, raw_data(bvh), bvh_size)
    if !bvh_ok { _vk_destroy((^VulkanGPUBackend)(b)); return nil, false }
    b.buffers[2] = bvh_buf
    bvh_header := [4]i32{i32(len(bvh)), 0, 0, 0}
    vk_ctx.update_buffer_data(&b.buffers[2], 0, &bvh_header, size_of([4]i32))

    quad_size := len(quads) * size_of(GPUQuad)
    q_buf, q_ok := _vk_create_ssbo_with_header(&b.ctx, raw_data(quads), quad_size)
    if !q_ok { _vk_destroy((^VulkanGPUBackend)(b)); return nil, false }
    b.buffers[4] = q_buf
    q_header := [4]i32{i32(len(quads)), 0, 0, 0}
    vk_ctx.update_buffer_data(&b.buffers[4], 0, &q_header, size_of([4]i32))

    vol_size := len(volumes) * size_of(GPUVolume)
    v_buf, v_ok := _vk_create_ssbo_with_header(&b.ctx, raw_data(volumes), vol_size)
    if !v_ok { _vk_destroy((^VulkanGPUBackend)(b)); return nil, false }
    b.buffers[5] = v_buf
    v_header := [4]i32{i32(len(volumes)), 0, 0, 0}
    vk_ctx.update_buffer_data(&b.buffers[5], 0, &v_header, size_of([4]i32))

    vq_size := len(volume_quads) * size_of(GPUQuad)
    vq_buf, vq_ok := _vk_create_ssbo_with_header(&b.ctx, raw_data(volume_quads), vq_size)
    if !vq_ok { _vk_destroy((^VulkanGPUBackend)(b)); return nil, false }
    b.buffers[6] = vq_buf
    vq_header := [4]i32{i32(len(volume_quads)), 0, 0, 0}
    vk_ctx.update_buffer_data(&b.buffers[6], 0, &vq_header, size_of([4]i32))

    // Buffer 7: image textures (packed metadata + RGB pixel data)
    img_data := pack_image_textures_for_gpu(image_list)
    defer if img_data != nil { delete(img_data) }
    img_body_size := len(img_data) * size_of(i32)
    img_buf, img_ok := _vk_create_ssbo_with_header(&b.ctx, raw_data(img_data), img_body_size)
    if !img_ok { _vk_destroy((^VulkanGPUBackend)(b)); return nil, false }
    b.buffers[7] = img_buf
    img_header := [4]i32{i32(len(image_list)), 0, 0, 0}
    vk_ctx.update_buffer_data(&b.buffers[7], 0, &img_header, size_of([4]i32))

    // Buffer 3: output accumulation
    pixel_count := b.width * b.height
    out_size := pixel_count * size_of([4]f32)
    out_buf, out_ok := vk_ctx.create_host_visible_buffer(
        b.ctx.device,
        b.ctx.physical_device,
        vk.DeviceSize(out_size),
        {.STORAGE_BUFFER},
    )
    if !out_ok { _vk_destroy((^VulkanGPUBackend)(b)); return nil, false }
    b.buffers[3] = out_buf
    mem.set(b.buffers[3].mapped, 0, out_size)

    vk_ctx.write_raytrace_descriptors(b.ctx.device, b.pipeline.descriptor_set, b.buffers)

    // Reuse compute command pool owned by vk_ctx.
    alloc := vk.CommandBufferAllocateInfo{
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = b.ctx.compute_command_pool,
        level = .PRIMARY,
        commandBufferCount = 1,
    }
    if vk.AllocateCommandBuffers(b.ctx.device, &alloc, &b.command_buffer) != .SUCCESS {
        _vk_destroy((^VulkanGPUBackend)(b))
        return nil, false
    }

    when VERBOSE_OUTPUT {
        fmt.printf("[GPU] Vulkan compute ready — %d spheres, %d quads, %d volumes, %d BVH nodes, %d image textures, %dx%d px\n",
            len(spheres), len(quads), len(volumes), len(bvh), len(image_list), b.width, b.height)
    }
    return b, true
}

@(private)
_vk_dispatch :: proc(state: rawptr) {
    b := (^VulkanGPUBackend)(state)
    if b == nil { return }
    if b.current_sample >= b.total_samples { return }
    // Re-bind global Vulkan dispatch to this compute device (see imgui_vk_end_frame comment).
    vk.load_proc_addresses_device(b.ctx.device)

    t0 := time.now()
    defer {
        b.dispatch_total_ns += time.duration_nanoseconds(time.diff(t0, time.now()))
    }

    b.current_sample += 1
    b.cached_uniforms.current_sample = i32(b.current_sample)
    vk_ctx.update_buffer_data(&b.buffers[0], 0, &b.cached_uniforms, size_of(GPUCameraUniforms))

    vk.ResetCommandBuffer(b.command_buffer, {})
    begin := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    }
    if vk.BeginCommandBuffer(b.command_buffer, &begin) != .SUCCESS { return }

    vk.CmdBindPipeline(b.command_buffer, .COMPUTE, b.pipeline.pipeline)
    vk.CmdBindDescriptorSets(
        b.command_buffer,
        .COMPUTE,
        b.pipeline.pipeline_layout,
        0,
        1,
        &b.pipeline.descriptor_set,
        0,
        nil,
    )
    groups_x := u32((b.width + 7) / 8)
    groups_y := u32((b.height + 7) / 8)
    vk.CmdDispatch(b.command_buffer, groups_x, groups_y, 1)

    out_barrier := vk.BufferMemoryBarrier{
        sType = .BUFFER_MEMORY_BARRIER,
        srcAccessMask = {.SHADER_WRITE},
        dstAccessMask = {.HOST_READ},
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        buffer = b.buffers[3].buffer,
        offset = 0,
        size = b.buffers[3].size,
    }
    vk.CmdPipelineBarrier(
        b.command_buffer,
        {.COMPUTE_SHADER},
        {.HOST},
        {},
        0, nil,
        1, &out_barrier,
        0, nil,
    )

    if vk.EndCommandBuffer(b.command_buffer) != .SUCCESS { return }
    if vk.ResetFences(b.ctx.device, 1, &b.ctx.fence) != .SUCCESS { return }
    submit := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &b.command_buffer,
    }
    if vk.QueueSubmit(b.ctx.compute_queue, 1, &submit, b.ctx.fence) != .SUCCESS { return }
    _ = vk.WaitForFences(b.ctx.device, 1, &b.ctx.fence, true, ~u64(0))
}

@(private)
_vk_readback :: proc(state: rawptr, out: [][4]u8) {
    b := (^VulkanGPUBackend)(state)
    if b == nil { return }
    pixel_count := b.width * b.height
    if len(out) < pixel_count { return }

    t0 := time.now()
    defer {
        b.readback_total_ns += time.duration_nanoseconds(time.diff(t0, time.now()))
    }

    tmp := ([^][4]f32)(b.buffers[3].mapped)[:pixel_count]
    inv := f32(1.0) / f32(max(b.current_sample, 1))
    for i in 0 ..< pixel_count {
        r := math.sqrt(clamp(tmp[i][0] * inv, 0, 1))
        g := math.sqrt(clamp(tmp[i][1] * inv, 0, 1))
        bl := math.sqrt(clamp(tmp[i][2] * inv, 0, 1))
        out[i] = [4]u8{
            u8(r * 255.999),
            u8(g * 255.999),
            u8(bl * 255.999),
            255,
        }
    }
}

@(private)
_vk_final_readback :: proc(state: rawptr, out: [][4]u8) {
    _vk_readback(state, out)
}

@(private)
_vk_get_samples :: proc(state: rawptr) -> (int, int) {
    b := (^VulkanGPUBackend)(state)
    if b == nil { return 0, 0 }
    return b.current_sample, b.total_samples
}

@(private)
_vk_get_timings :: proc(state: rawptr) -> (i64, i64) {
    b := (^VulkanGPUBackend)(state)
    if b == nil { return 0, 0 }
    return b.dispatch_total_ns, b.readback_total_ns
}

@(private)
_vk_reset :: proc(state: rawptr) {
    b := (^VulkanGPUBackend)(state)
    if b == nil { return }
    mem.set(b.buffers[3].mapped, 0, int(b.buffers[3].size))
    b.current_sample = 0
    b.cached_uniforms.current_sample = 0
    vk_ctx.update_buffer_data(&b.buffers[0], 0, &b.cached_uniforms, size_of(GPUCameraUniforms))
}

@(private)
_vk_destroy :: proc(b: ^VulkanGPUBackend) {
    if b == nil { return }
    vk.load_proc_addresses_device(b.ctx.device)
    if b.command_buffer != vk.CommandBuffer({}) && b.ctx.compute_command_pool != vk.CommandPool({}) {
        vk.FreeCommandBuffers(b.ctx.device, b.ctx.compute_command_pool, 1, &b.command_buffer)
        b.command_buffer = {}
    }
    for i in 0 ..< len(b.buffers) {
        if b.buffers[i].buffer != vk.Buffer({}) {
            vk_ctx.destroy_buffer(b.ctx.device, &b.buffers[i])
        }
    }
    vk_ctx.destroy_vulkan_compute_pipeline(b.ctx.device, &b.pipeline)
    vk_ctx.vulkan_context_destroy(&b.ctx)
    free(b)
}

@(private)
_vk_destroy_state :: proc(state: rawptr) {
    _vk_destroy((^VulkanGPUBackend)(state))
}

VULKAN_RENDERER_API :: GpuRendererApi{
    init          = _vk_backend_init,
    dispatch      = _vk_dispatch,
    readback      = _vk_readback,
    final_readback = _vk_final_readback,
    destroy       = _vk_destroy_state,
    get_samples   = _vk_get_samples,
    get_timings   = _vk_get_timings,
    reset         = _vk_reset,
}

