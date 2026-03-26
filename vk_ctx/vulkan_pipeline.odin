package vk_ctx

import "core:fmt"

import vk "vendor:vulkan"

// VulkanComputePipeline holds all Vulkan handles for a compute pipeline:
// shader module, descriptor set layout/pool/set, pipeline layout, and pipeline.
VulkanComputePipeline :: struct {
	shader_module:         vk.ShaderModule,
	descriptor_set_layout: vk.DescriptorSetLayout,
	pipeline_layout:       vk.PipelineLayout,
	pipeline:              vk.Pipeline,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_set:        vk.DescriptorSet,
}

// create_shader_module loads a SPIR-V binary (from #load or file) into a VkShaderModule.
create_shader_module :: proc(device: vk.Device, spirv: []u8) -> (vk.ShaderModule, bool) {
	if len(spirv) == 0 || len(spirv) % 4 != 0 {
		fmt.eprintln("vk_ctx: invalid SPIR-V size")
		return {}, false
	}
	ci := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(spirv),
		pCode    = cast([^]u32)raw_data(spirv),
	}
	mod: vk.ShaderModule
	if vk.CreateShaderModule(device, &ci, nil, &mod) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateShaderModule failed")
		return {}, false
	}
	return mod, true
}

// create_raytrace_descriptor_set_layout creates the layout matching the 8 bindings
// in raytrace_vk.comp: 1 UBO + 7 SSBOs.
create_raytrace_descriptor_set_layout :: proc(device: vk.Device) -> (vk.DescriptorSetLayout, bool) {
	bindings := [8]vk.DescriptorSetLayoutBinding {
		// Binding 0: camera uniforms (UBO).
		{
			binding         = 0,
			descriptorType  = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
		// Binding 1: spheres (SSBO, readonly).
		{
			binding         = 1,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
		// Binding 2: BVH nodes (SSBO, readonly).
		{
			binding         = 2,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
		// Binding 3: output accumulation (SSBO, read-write).
		{
			binding         = 3,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
		// Binding 4: quads (SSBO, readonly).
		{
			binding         = 4,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
		// Binding 5: volumes (SSBO, readonly).
		{
			binding         = 5,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
		// Binding 6: volume quads (SSBO, readonly).
		{
			binding         = 6,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
		// Binding 7: image textures (SSBO, readonly).
		{
			binding         = 7,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.COMPUTE},
		},
	}
	ci := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = raw_data(bindings[:]),
	}
	layout: vk.DescriptorSetLayout
	if vk.CreateDescriptorSetLayout(device, &ci, nil, &layout) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateDescriptorSetLayout failed")
		return {}, false
	}
	return layout, true
}

// create_raytrace_pipeline_layout creates a pipeline layout with a single descriptor set.
create_raytrace_pipeline_layout :: proc(
	device: vk.Device,
	set_layout: vk.DescriptorSetLayout,
) -> (vk.PipelineLayout, bool) {
	sl := set_layout
	ci := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &sl,
	}
	layout: vk.PipelineLayout
	if vk.CreatePipelineLayout(device, &ci, nil, &layout) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreatePipelineLayout failed")
		return {}, false
	}
	return layout, true
}

// create_raytrace_compute_pipeline creates a compute pipeline from a shader module.
create_raytrace_compute_pipeline :: proc(
	device: vk.Device,
	layout: vk.PipelineLayout,
	shader_module: vk.ShaderModule,
) -> (vk.Pipeline, bool) {
	stage := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = shader_module,
		pName  = "main",
	}
	ci := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = layout,
		stage  = stage,
	}
	pipeline: vk.Pipeline
	if vk.CreateComputePipelines(device, 0, 1, &ci, nil, &pipeline) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateComputePipelines failed")
		return {}, false
	}
	return pipeline, true
}

// create_raytrace_descriptor_pool creates a pool for 1 UBO + 7 SSBOs (1 set).
create_raytrace_descriptor_pool :: proc(device: vk.Device) -> (vk.DescriptorPool, bool) {
	pool_sizes := [2]vk.DescriptorPoolSize {
		{ type = .UNIFORM_BUFFER,  descriptorCount = 1 },
		{ type = .STORAGE_BUFFER,  descriptorCount = 7 },
	}
	ci := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes[:]),
	}
	pool: vk.DescriptorPool
	if vk.CreateDescriptorPool(device, &ci, nil, &pool) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkCreateDescriptorPool failed")
		return {}, false
	}
	return pool, true
}

// allocate_raytrace_descriptor_set allocates a single descriptor set from the pool.
allocate_raytrace_descriptor_set :: proc(
	device: vk.Device,
	pool: vk.DescriptorPool,
	layout: vk.DescriptorSetLayout,
) -> (vk.DescriptorSet, bool) {
	l := layout
	ai := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool,
		descriptorSetCount = 1,
		pSetLayouts        = &l,
	}
	set: vk.DescriptorSet
	if vk.AllocateDescriptorSets(device, &ai, &set) != .SUCCESS {
		fmt.eprintln("vk_ctx: vkAllocateDescriptorSets failed")
		return {}, false
	}
	return set, true
}

// write_raytrace_descriptors binds 8 buffers to the descriptor set.
// buffers must have exactly 8 entries: [0]=UBO, [1]=spheres, [2]=BVH, [3]=output,
// [4]=quads, [5]=volumes, [6]=volume_quads, [7]=image_textures.
write_raytrace_descriptors :: proc(device: vk.Device, set: vk.DescriptorSet, buffers: [8]VulkanBuffer) {
	buf_infos: [8]vk.DescriptorBufferInfo
	writes: [8]vk.WriteDescriptorSet
	for i in 0 ..< 8 {
		buf_infos[i] = {
			buffer = buffers[i].buffer,
			offset = 0,
			range  = buffers[i].size,
		}
		writes[i] = {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = set,
			dstBinding      = u32(i),
			descriptorCount = 1,
			descriptorType  = .UNIFORM_BUFFER if i == 0 else .STORAGE_BUFFER,
			pBufferInfo     = &buf_infos[i],
		}
	}
	vk.UpdateDescriptorSets(device, u32(len(writes)), raw_data(writes[:]), 0, nil)
}

// create_vulkan_compute_pipeline is a convenience proc that creates the full pipeline
// from SPIR-V bytes: shader module, descriptor layout, pipeline layout, pipeline,
// descriptor pool, and descriptor set.
create_vulkan_compute_pipeline :: proc(device: vk.Device, spirv: []u8) -> (p: VulkanComputePipeline, ok: bool) {
	p = {}
	mod, mod_ok := create_shader_module(device, spirv)
	if !mod_ok { return p, false }
	p.shader_module = mod

	dsl, dsl_ok := create_raytrace_descriptor_set_layout(device)
	if !dsl_ok { destroy_vulkan_compute_pipeline(device, &p); return p, false }
	p.descriptor_set_layout = dsl

	pl, pl_ok := create_raytrace_pipeline_layout(device, dsl)
	if !pl_ok { destroy_vulkan_compute_pipeline(device, &p); return p, false }
	p.pipeline_layout = pl

	pipe, pipe_ok := create_raytrace_compute_pipeline(device, pl, mod)
	if !pipe_ok { destroy_vulkan_compute_pipeline(device, &p); return p, false }
	p.pipeline = pipe

	pool, pool_ok := create_raytrace_descriptor_pool(device)
	if !pool_ok { destroy_vulkan_compute_pipeline(device, &p); return p, false }
	p.descriptor_pool = pool

	set, set_ok := allocate_raytrace_descriptor_set(device, pool, dsl)
	if !set_ok { destroy_vulkan_compute_pipeline(device, &p); return p, false }
	p.descriptor_set = set

	return p, true
}

// destroy_vulkan_compute_pipeline destroys all pipeline handles in reverse creation order.
destroy_vulkan_compute_pipeline :: proc(device: vk.Device, p: ^VulkanComputePipeline) {
	if p.pipeline != vk.Pipeline(0) {
		vk.DestroyPipeline(device, p.pipeline, nil)
		p.pipeline = {}
	}
	if p.pipeline_layout != vk.PipelineLayout(0) {
		vk.DestroyPipelineLayout(device, p.pipeline_layout, nil)
		p.pipeline_layout = {}
	}
	if p.descriptor_pool != vk.DescriptorPool(0) {
		// Implicitly frees all descriptor sets allocated from this pool.
		vk.DestroyDescriptorPool(device, p.descriptor_pool, nil)
		p.descriptor_pool = {}
		p.descriptor_set = {}
	}
	if p.descriptor_set_layout != vk.DescriptorSetLayout(0) {
		vk.DestroyDescriptorSetLayout(device, p.descriptor_set_layout, nil)
		p.descriptor_set_layout = {}
	}
	if p.shader_module != vk.ShaderModule(0) {
		vk.DestroyShaderModule(device, p.shader_module, nil)
		p.shader_module = {}
	}
}
