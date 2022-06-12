const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const StructField = std.builtin.Type.StructField;

const Entities = @import("entities.zig").Entities;

pub fn Adapter(modules: anytype) type {
    return struct {
        world: *World(modules),

        const Self = @This();
        pub const Iterator = Entities(modules).Iterator;

        pub fn query(adapter: *Self, components: []const []const u8) Iterator {
            return adapter.world.entities.query(components);
        }
    };
}

/// An ECS module can provide components, systems, and state values.
pub fn Module(comptime Params: anytype) @TypeOf(Params) {
    // TODO: validate Params.components is the right type
    // TODO: validate Params.globals is the right type
    // TODO: validate Params.systems is the right type.
    // TODO: validate no unexpected fields exist.
    return Params;
}

pub fn Modules(modules: anytype) @TypeOf(modules) {
    // TODO: validate it's a tuple of Module(anytype)
    return modules;
}

/// Extracts namespaces components from modules like this:
///
/// ```
/// .{
///     .renderer = .{
///         .components = .{
///             .location = Vec3,
///             .rotation = Vec3,
///         },
///         ...
///     },
///     .physics2d = .{
///         .components = .{
///             .location = Vec2
///             .velocity = Vec2,
///         },
///         ...
///     },
/// }
/// ```
///
/// Into a namespaced component type like this:
///
/// ```
/// .{
///     .renderer = .{
///         .location = Vec3,
///         .rotation = Vec3,
///     },
///     .physics2d = .{
///         .location = Vec2
///         .velocity = Vec2,
///     },
/// }
/// ```
///
fn NamespacedComponents(comptime modules: anytype) type {
    var fields: []const StructField = &[0]StructField{};
    inline for (std.meta.fields(@TypeOf(modules))) |module_field| {
        const module = @field(modules, module_field.name);
        if (@hasField(@TypeOf(module), "components")) {
            fields = fields ++ [_]std.builtin.Type.StructField{.{
                .name = module_field.name,
                .field_type = @TypeOf(module.components),
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(@TypeOf(module.components)),
            }};
        }
    }
    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .is_tuple = false,
            .fields = fields,
            .decls = &[_]std.builtin.Type.Declaration{},
        },
    });
}

/// Extracts namespaced globals from modules like this:
///
/// ```
/// .{
///     .renderer = .{
///         .globals = struct{
///             foo: *Bar,
///             baz: Bam,
///         },
///         ...
///     },
///     .physics2d = .{
///         .globals = struct{
///             foo: *Instance,
///         },
///         ...
///     },
/// }
/// ```
///
/// Into a namespaced global type like this:
///
/// ```
/// struct{
///     renderer: struct{
///         foo: *Bar,
///         baz: Bam,
///     },
///     physics2d: struct{
///         foo: *Instance,
///     },
/// }
/// ```
///
fn NamespacedGlobals(comptime modules: anytype) type {
    var fields: []const StructField = &[0]StructField{};
    inline for (std.meta.fields(@TypeOf(modules))) |module_field| {
        const module = @field(modules, module_field.name);
        if (@hasField(@TypeOf(module), "globals")) {
            fields = fields ++ [_]std.builtin.Type.StructField{.{
                .name = module_field.name,
                .field_type = module.globals,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(module.globals),
            }};
        }
    }
    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .is_tuple = false,
            .fields = fields,
            .decls = &[_]std.builtin.Type.Declaration{},
        },
    });
}

pub fn World(comptime modules: anytype) type {
    const all_components = NamespacedComponents(modules);
    return struct {
        allocator: Allocator,
        systems: std.StringArrayHashMapUnmanaged(System) = .{},
        entities: Entities(all_components),
        globals: NamespacedGlobals(modules),

        const Self = @This();
        pub const System = fn (adapter: *Adapter(modules)) void;

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .allocator = allocator,
                .entities = try Entities(all_components).init(allocator),
                .globals = undefined,
            };
        }

        pub fn deinit(world: *Self) void {
            world.systems.deinit(world.allocator);
            world.entities.deinit();
        }

        /// Gets a global value called `.global_tag` from the module named `.module_tag`
        pub fn get(world: *Self, module_tag: anytype, global_tag: anytype) @TypeOf(@field(
            @field(world.globals, std.meta.tagName(module_tag)),
            std.meta.tagName(global_tag),
        )) {
            return comptime @field(
                @field(world.globals, std.meta.tagName(module_tag)),
                std.meta.tagName(global_tag),
            );
        }

        pub fn register(world: *Self, name: []const u8, system: System) !void {
            try world.systems.put(world.allocator, name, system);
        }

        pub fn unregister(world: *Self, name: []const u8) void {
            world.systems.orderedRemove(name);
        }

        pub fn tick(world: *Self) void {
            var i: usize = 0;
            while (i < world.systems.count()) : (i += 1) {
                const system = world.systems.entries.get(i).value;

                var adapter = Adapter(modules){
                    .world = world,
                };
                system(&adapter);
            }
        }
    };
}
