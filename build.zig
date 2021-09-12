const std = @import("std");
const os = std.builtin.os.tag;

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const yes = b.addExecutable("yes", "src/yes.zig");
    yes.setTarget(target);
    yes.setBuildMode(mode);
    yes.install();

    const dirname = b.addExecutable("dirname", "src/dirname.zig");
    dirname.setTarget(target);
    dirname.setBuildMode(mode);
    dirname.install();

    const whoami = b.addExecutable("whoami", "src/whoami.zig");
    whoami.setTarget(target);
    whoami.setBuildMode(mode);
    whoami.install();

    const groups = b.addExecutable("groups", "src/groups.zig");
    groups.setTarget(target);
    groups.setBuildMode(mode);
    groups.install();

    if (os == .linux) {
        whoami.linkSystemLibrary("c");
        groups.linkSystemLibrary("c");
    }

}
