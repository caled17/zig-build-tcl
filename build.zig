const std = @import("std");

const build_zon = @import("build.zig.zon");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dllfile_opt = b.option(
        []const u8,
        "dllfile",
        "Tcl shared-library basename at runtime",
    ) orelse switch (target.result.os.tag) {
        .windows => "tcl90.dll",
        .macos => "libtcl9.0.dylib",
        else => "libtcl9.0.so",
    };
    const libdir_opt = b.option(
        []const u8,
        "libdir",
        "Runtime library directory; shared-library loading fallback on UNIX",
    ) orelse "/usr/local/lib";
    const bindir_opt = b.option(
        []const u8,
        "bindir",
        "Runtime binary directory; shared-library loading fallback on Windows",
    ) orelse "C:\\Tcl\\bin";

    const translate_c = b.dependency("translate_c", .{});
    const upstream = b.dependency("tcl", .{});

    const tclstub_lib = b.addLibrary(.{
        .name = "tclstub",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = .static,
        .version = comptime std.SemanticVersion.parse(build_zon.dependencies.tcl.version) catch unreachable,
    });
    tclstub_lib.root_module.addCMacro("CFG_RUNTIME_DLLFILE", escapePathLiteral(b, dllfile_opt));
    tclstub_lib.root_module.addCMacro("CFG_RUNTIME_LIBDIR", escapePathLiteral(b, libdir_opt));
    tclstub_lib.root_module.addCMacro("CFG_RUNTIME_BINDIR", escapePathLiteral(b, bindir_opt));
    tclstub_lib.root_module.addIncludePath(upstream.path("generic"));
    tclstub_lib.root_module.addIncludePath(upstream.path("libtommath"));
    tclstub_lib.root_module.addCSourceFiles(.{
        .root = upstream.path("generic"),
        .files = &.{
            "tclOOStubLib.c",
            "tclStubCall.c",
            "tclStubLib.c",
            "tclStubLibTbl.c",
            "tclTomMathStubLib.c",
        },
    });
    switch (target.result.os.tag) {
        .windows => {
            tclstub_lib.root_module.addIncludePath(upstream.path("win"));
            tclstub_lib.root_module.addCSourceFile(.{ .file = upstream.path("win/tclWinPanic.c") });
        },
        else => {
            tclstub_lib.root_module.addIncludePath(upstream.path("unix"));
        },
    }
    b.installArtifact(tclstub_lib);
    const tclstub_install = b.addInstallArtifact(tclstub_lib, .{});
    const tclstub_step = b.step("tclstub", "Build libtclstub.a");
    tclstub_step.dependOn(&tclstub_install.step);

    const tcl_h: Translator = .init(translate_c, .{
        .c_source_file = upstream.path("generic/tcl.h"),
        .target = target,
        .optimize = optimize,
    });
    tcl_h.defineCMacro("USE_TCL_STUBS", null);
    tcl_h.linkLibrary(tclstub_lib);

    const example_lib = b.addLibrary(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = .dynamic, // Tcl extensions are loaded dynamically
    });
    example_lib.root_module.addImport("tcl", tcl_h.mod);
    const example_install = b.addInstallArtifact(example_lib, .{});
    const example_step = b.step("example", "Build example extension with libtclstub");
    example_step.dependOn(&example_install.step);
}

fn escapePathLiteral(b: *std.Build, path_literal: []const u8) []const u8 {
    const backslashes = std.mem.replaceOwned(u8, b.allocator, path_literal, "\\", "\\\\") catch @panic("OOM");
    defer b.allocator.free(backslashes);
    const quotes = std.mem.replaceOwned(u8, b.allocator, path_literal, "\"", "\\\"") catch @panic("OOM");
    defer b.allocator.free(quotes);
    return b.fmt("\"{s}\"", .{quotes});
}
