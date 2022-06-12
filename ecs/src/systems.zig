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

/// A Module that represents a singleton global value.
pub fn Singleton(comptime T: type) type {
    return struct {
        pub const singleton = T;
    };
}

/// A generic ECS module which provides components and systems.
pub fn Module(comptime components: anytype) type {
    return struct {
        pub const components = components;
        // TODO: ...
    };
}

fn MergeAllComponents(comptime modules: anytype) type {
    var fields: []const StructField = &[0]StructField{};
    inline for (std.meta.fields(@TypeOf(modules))) |module_field| {
        const module = @field(modules, module_field.name);
        if (@hasDecl(module, "components")) {
            inline for (std.meta.fields(@TypeOf(module.components))) |component_field| {
                fields = fields ++ [_]std.builtin.Type.StructField{component_field};
            }
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

fn Singletons(comptime modules: anytype) type {
    var fields: []const StructField = &[0]StructField{};
    inline for (std.meta.fields(@TypeOf(modules))) |module_field| {
        const module = @field(modules, module_field.name);
        if (@hasDecl(module, "singleton")) {
            // TODO: unpack singleton
            fields = fields ++ [_]std.builtin.Type.StructField{.{
                .name = module_field.name,
                .field_type = module.singleton,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(module.singleton),
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
    const all_components = MergeAllComponents(modules);
    return struct {
        allocator: Allocator,
        systems: std.StringArrayHashMapUnmanaged(System) = .{},
        entities: Entities(all_components),
        singletons: Singletons(modules),

        const Self = @This();
        pub const System = fn (adapter: *Adapter(modules)) void;

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .allocator = allocator,
                .entities = try Entities(all_components).init(allocator),
                .singletons = undefined,
            };
        }

        pub fn deinit(world: *Self) void {
            world.systems.deinit(world.allocator);
            world.entities.deinit();
        }

        pub fn get(world: *Self, module_tag: anytype) @TypeOf(@field(world.singletons, std.meta.tagName(module_tag))) {
            return comptime @field(world.singletons, std.meta.tagName(module_tag));
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
