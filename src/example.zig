const std = @import("std");
const tcl = @import("tcl");

export fn Example_Init(interp: *tcl.Tcl_Interp) callconv(.c) c_int {
    initTclStubs(interp, "8.6-", false) catch return tcl.TCL_ERROR;
    // Stuck doing this until translate-c allows for redefinition of symbols
    _ = tcl.tclStubsPtr.*.tcl_CreateObjCommand.?(interp, "hello", helloCmd, null, null);
    return tcl.TCL_OK;
}

// Tcl gates this signature behind a macro and some symbol redefinition
// shenanigans that don't mesh well with translate-c, so we're stuck
// writing this signature ourselves for every extension
fn initTclStubs(interp: *tcl.Tcl_Interp, version: [:0]const u8, exact: bool) error{Failed}!void {
    if (tcl.Tcl_InitStubs(
        interp,
        version,
        @intFromBool(exact) | tcl.TCL_MAJOR_VERSION << 8 | tcl.TCL_MINOR_VERSION << 16,
        tcl.TCL_STUB_MAGIC,
    ) == null) return error.Failed;
}

fn helloCmd(_: ?*anyopaque, interp: ?*tcl.Tcl_Interp, objc: c_int, objv: [*c]const [*c]tcl.Tcl_Obj) callconv(.c) c_int {
    const count: u32 = @intCast(objc);
    const args: []const *tcl.Tcl_Obj = @ptrCast(objv[0..count]);
    helloCmdInner(args) catch |err| switch (err) {
        error.TooManyArgs => {
            tcl.tclStubsPtr.*.tcl_WrongNumArgs.?(interp, 1, objv, "?subject?");
            return tcl.TCL_ERROR;
        },
    };
    return tcl.TCL_OK;
}

fn helloCmdInner(args: []const *tcl.Tcl_Obj) error{TooManyArgs}!void {
    const subject: []const u8 = switch (args.len) {
        1 => "World",
        2 => str: {
            var c_len: tcl.Tcl_Size = undefined;
            const c_str = tcl.tclStubsPtr.*.tcl_GetStringFromObj.?(args[1], &c_len);
            const len: u32 = @intCast(c_len);
            break :str c_str[0..len];
        },
        else => return error.TooManyArgs,
    };
    std.debug.print("Hello, {s}!\n", .{subject});
}
