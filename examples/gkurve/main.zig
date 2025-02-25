// TODO:
// - handle textures better with texture atlas
// - handle adding and removing triangles and quads better

const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");
const zigimg = @import("zigimg");
const glfw = @import("glfw");
const draw = @import("draw.zig");
const Atlas = @import("atlas.zig").Atlas;
const ft = @import("freetype");
const Label = @import("label.zig");
const ResizableLabel = @import("resizable_label.zig");

pub const App = @This();

const AtlasRGB8 = Atlas(zigimg.color.Rgba32);

pipeline: gpu.RenderPipeline,
queue: gpu.Queue,
vertex_buffer: gpu.Buffer,
vertices: std.ArrayList(draw.Vertex),
update_vertex_buffer: bool,
vertex_uniform_buffer: gpu.Buffer,
update_vertex_uniform_buffer: bool,
frag_uniform_buffer: gpu.Buffer,
fragment_uniform_list: std.ArrayList(draw.FragUniform),
update_frag_uniform_buffer: bool,
bind_group: gpu.BindGroup,
texture_atlas_data: AtlasRGB8,

pub fn init(app: *App, engine: *mach.Engine) !void {
    try engine.setOptions(.{
        .width = 640,
        .height = 480,
        .size_min = .{ .width = 20, .height = 20 },
    });

    const queue = engine.device.getQueue();

    // TODO: Refactor texture atlas size number
    app.texture_atlas_data = try AtlasRGB8.init(engine.allocator, 1280);
    const atlas_size = gpu.Extent3D{ .width = app.texture_atlas_data.size, .height = app.texture_atlas_data.size };
    const atlas_float_size = @intToFloat(f32, app.texture_atlas_data.size);

    const texture = engine.device.createTexture(&.{
        .size = atlas_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });
    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @intCast(u32, atlas_size.width * 4),
        .rows_per_image = @intCast(u32, atlas_size.height),
    };

    const img = try zigimg.Image.fromMemory(engine.allocator, @embedFile("../assets/gotta-go-fast.png"));
    defer img.deinit();

    const atlas_img_region = try app.texture_atlas_data.reserve(engine.allocator, @truncate(u32, img.width), @truncate(u32, img.height));
    const img_uv_data = atlas_img_region.getUVData(atlas_float_size);

    switch (img.pixels.?) {
        .Rgba32 => |pixels| app.texture_atlas_data.set(atlas_img_region, pixels),
        .Rgb24 => |pixels| {
            const data = try rgb24ToRgba32(engine.allocator, pixels);
            defer data.deinit(engine.allocator);
            app.texture_atlas_data.set(atlas_img_region, data.Rgba32);
        },
        else => @panic("unsupported image color format"),
    }

    const white_tex_scale = 80;
    var atlas_white_region = try app.texture_atlas_data.reserve(engine.allocator, white_tex_scale, white_tex_scale);
    atlas_white_region.x += 1;
    atlas_white_region.y += 1;
    atlas_white_region.width -= 2;
    atlas_white_region.height -= 2;
    const white_texture_uv_data = atlas_white_region.getUVData(atlas_float_size);
    var white_tex_data = try engine.allocator.alloc(zigimg.color.Rgba32, white_tex_scale * white_tex_scale);
    std.mem.set(zigimg.color.Rgba32, white_tex_data, zigimg.color.Rgba32.initRGB(0xff, 0xff, 0xff));
    app.texture_atlas_data.set(atlas_white_region, white_tex_data);

    app.vertices = try std.ArrayList(draw.Vertex).initCapacity(engine.allocator, 9);
    app.fragment_uniform_list = try std.ArrayList(draw.FragUniform).initCapacity(engine.allocator, 3);

    // Quick test for using freetype
    const lib = try ft.Library.init();
    defer lib.deinit();

    const size_multiplier = 5;
    const character = "è";
    var label = try Label.init(lib, "freetype/upstream/assets/FiraSans-Regular.ttf", 0, 110 * size_multiplier, engine.allocator);
    defer label.deinit();
    // try label.print(app, "All your game's bases are belong to us èçòà", .{}, @Vector(2, f32){ 0, 420 }, @Vector(4, f32){ 1, 1, 1, 1 });
    try label.print(app, character, .{}, @Vector(2, f32){ 50 * size_multiplier, 40 }, @Vector(4, f32){ 1, 1, 1, 1 });

    var resizable_label: ResizableLabel = undefined;
    try resizable_label.init(lib, "freetype/upstream/assets/FiraSans-Regular.ttf", 0, engine.allocator, white_texture_uv_data);
    defer resizable_label.deinit();
    try resizable_label.print(app, character, .{}, @Vector(4, f32){ 0, 40, 0, 0 }, @Vector(4, f32){ 1, 1, 1, 1 }, 80 * size_multiplier);

    queue.writeTexture(
        &.{ .texture = texture },
        &data_layout,
        &.{ .width = app.texture_atlas_data.size, .height = app.texture_atlas_data.size },
        zigimg.color.Rgba32,
        app.texture_atlas_data.data,
    );

    const wsize = engine.getWindowSize();
    const window_width = @intToFloat(f32, wsize.width);
    const window_height = @intToFloat(f32, wsize.height);
    const triangle_scale = 250;
    _ = window_width;
    _ = window_height;
    _ = triangle_scale;
    _ = img_uv_data;
    _ = white_texture_uv_data;
    // try draw.equilateralTriangle(app, .{ window_width / 2, window_height / 2 }, triangle_scale, .{}, img_uv_data);
    // try draw.equilateralTriangle(app, .{ window_width / 2, window_height / 2 - triangle_scale }, triangle_scale, .{ .type = .concave }, img_uv_data);
    // try draw.equilateralTriangle(app, .{ window_width / 2 - triangle_scale, window_height / 2 - triangle_scale / 2 }, triangle_scale, .{ .type = .convex }, white_texture_uv_data);
    // try draw.quad(app, .{ 0, 0 }, .{ 480, 480 }, .{}, .{ .bottom_left = .{ 0, 0 }, .width_and_height = .{ 1, 1 } });
    // try draw.circle(app, .{ window_width / 2, window_height / 2 }, window_height / 2 - 10, .{ 0, 0.5, 0.75, 1.0 }, white_texture_uv_data);

    const vs_module = engine.device.createShaderModule(&.{
        .label = "my vertex shader",
        .code = .{ .wgsl = @embedFile("vert.wgsl") },
    });

    const fs_module = engine.device.createShaderModule(&.{
        .label = "my fragment shader",
        .code = .{ .wgsl = @embedFile("frag.wgsl") },
    });

    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .one,
            .dst_factor = .zero,
        },
    };

    const color_target = gpu.ColorTargetState{
        .format = engine.swap_chain_format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMask.all,
    };
    const fragment = gpu.FragmentState{
        .module = fs_module,
        .entry_point = "main",
        .targets = &.{color_target},
        .constants = null,
    };

    const vbgle = gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .uniform, true, 0);
    const fbgle = gpu.BindGroupLayout.Entry.buffer(1, .{ .fragment = true }, .read_only_storage, true, 0);
    const sbgle = gpu.BindGroupLayout.Entry.sampler(2, .{ .fragment = true }, .filtering);
    const tbgle = gpu.BindGroupLayout.Entry.texture(3, .{ .fragment = true }, .float, .dimension_2d, false);
    const bgl = engine.device.createBindGroupLayout(
        &gpu.BindGroupLayout.Descriptor{
            .entries = &.{ vbgle, fbgle, sbgle, tbgle },
        },
    );
    const bind_group_layouts = [_]gpu.BindGroupLayout{bgl};
    const pipeline_layout = engine.device.createPipelineLayout(&.{
        .bind_group_layouts = &bind_group_layouts,
    });

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .layout = pipeline_layout,
        .depth_stencil = null,
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffers = &.{draw.VERTEX_BUFFER_LAYOUT},
        },
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alpha_to_coverage_enabled = false,
        },
        .primitive = .{
            .front_face = .ccw,
            .cull_mode = .none,
            .topology = .triangle_list,
            .strip_index_format = .none,
        },
    };

    const vertex_buffer = engine.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = @sizeOf(draw.Vertex) * app.vertices.items.len,
        .mapped_at_creation = false,
    });

    const vertex_uniform_buffer = engine.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = @sizeOf(draw.VertexUniform),
        .mapped_at_creation = false,
    });

    const frag_uniform_buffer = engine.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .storage = true },
        .size = @sizeOf(draw.FragUniform) * app.fragment_uniform_list.items.len,
        .mapped_at_creation = false,
    });

    const sampler = engine.device.createSampler(&.{
        // .mag_filter = .linear,
        // .min_filter = .linear,
    });

    const bind_group = engine.device.createBindGroup(
        &gpu.BindGroup.Descriptor{
            .layout = bgl,
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, vertex_uniform_buffer, 0, @sizeOf(draw.VertexUniform)),
                gpu.BindGroup.Entry.buffer(1, frag_uniform_buffer, 0, @sizeOf(draw.FragUniform) * app.vertices.items.len / 3),
                gpu.BindGroup.Entry.sampler(2, sampler),
                gpu.BindGroup.Entry.textureView(3, texture.createView(&gpu.TextureView.Descriptor{ .dimension = .dimension_2d })),
            },
        },
    );

    app.pipeline = engine.device.createRenderPipeline(&pipeline_descriptor);
    app.queue = queue;
    app.vertex_buffer = vertex_buffer;
    app.vertex_uniform_buffer = vertex_uniform_buffer;
    app.frag_uniform_buffer = frag_uniform_buffer;
    app.bind_group = bind_group;
    app.update_vertex_buffer = true;
    app.update_vertex_uniform_buffer = true;
    app.update_frag_uniform_buffer = true;

    vs_module.release();
    fs_module.release();
    pipeline_layout.release();
    bgl.release();
}

pub fn deinit(app: *App, engine: *mach.Engine) void {
    app.vertex_buffer.release();
    app.vertex_uniform_buffer.release();
    app.frag_uniform_buffer.release();
    app.bind_group.release();
    app.vertices.deinit();
    app.fragment_uniform_list.deinit();
    app.texture_atlas_data.deinit(engine.allocator);
}

pub fn update(app: *App, engine: *mach.Engine) !void {
    while (engine.pollEvent()) |event| {
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space)
                    engine.setShouldClose(true);
            },
            else => {},
        }
    }

    const back_buffer_view = engine.swap_chain.?.getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = engine.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassEncoder.Descriptor{
        .color_attachments = &.{color_attachment},
    };

    {
        if (app.update_vertex_buffer) {
            encoder.writeBuffer(app.vertex_buffer, 0, draw.Vertex, app.vertices.items);
            app.update_vertex_buffer = false;
        }
        if (app.update_frag_uniform_buffer) {
            encoder.writeBuffer(app.frag_uniform_buffer, 0, draw.FragUniform, app.fragment_uniform_list.items);
            app.update_frag_uniform_buffer = false;
        }
        if (app.update_vertex_uniform_buffer) {
            encoder.writeBuffer(app.vertex_uniform_buffer, 0, draw.VertexUniform, &.{try getVertexUniformBufferObject(engine)});
            app.update_vertex_uniform_buffer = false;
        }
    }

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(draw.Vertex) * app.vertices.items.len);
    pass.setBindGroup(0, app.bind_group, &.{ 0, 0 });
    pass.draw(@truncate(u32, app.vertices.items.len), 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    app.queue.submit(&.{command});
    command.release();
    engine.swap_chain.?.present();
    back_buffer_view.release();
}

pub fn resize(app: *App, _: *mach.Engine, _: u32, _: u32) !void {
    app.update_vertex_uniform_buffer = true;
}

fn rgb24ToRgba32(allocator: std.mem.Allocator, in: []zigimg.color.Rgb24) !zigimg.color.ColorStorage {
    const out = try zigimg.color.ColorStorage.init(allocator, .Rgba32, in.len);
    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        out.Rgba32[i] = zigimg.color.Rgba32{ .R = in[i].R, .G = in[i].G, .B = in[i].B, .A = 255 };
    }
    return out;
}

// Move to draw.zig
pub fn getVertexUniformBufferObject(engine: *mach.Engine) !draw.VertexUniform {
    // Note: We use window width/height here, not framebuffer width/height.
    // On e.g. macOS, window size may be 640x480 while framebuffer size may be
    // 1280x960 (subpixels.) Doing this lets us use a pixel, not subpixel,
    // coordinate system.
    const window_size = engine.getWindowSize();
    const proj = zm.orthographicRh(
        @intToFloat(f32, window_size.width),
        @intToFloat(f32, window_size.height),
        -100,
        100,
    );

    const mvp = zm.mul(proj, zm.translation(-1, -1, 0));
    return draw.VertexUniform{
        .mat = mvp,
    };
}
