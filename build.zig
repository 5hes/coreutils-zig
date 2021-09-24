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

    const dirname = b.addExecutable("dirname", "src/dirname.zig");
    dirname.setTarget(target);
    dirname.setBuildMode(mode);
    dirname.install();

    const false_app = b.addExecutable("false", "src/false.zig");
    false_app.setTarget(target);
    false_app.setBuildMode(mode);
    false_app.install();

    const groups = b.addExecutable("groups", "src/groups.zig");
    groups.setTarget(target);
    groups.setBuildMode(mode);
    groups.install();

    const hostid = b.addExecutable("hostid", "src/hostid.zig");
    hostid.setTarget(target);
    hostid.setBuildMode(mode);
    hostid.install();

    const logname = b.addExecutable("logname", "src/logname.zig");
    logname.setTarget(target);
    logname.setBuildMode(mode);
    logname.install();

    const nproc = b.addExecutable("nproc", "src/nproc.zig");
    nproc.setTarget(target);
    nproc.setBuildMode(mode);
    nproc.install();

    const printenv = b.addExecutable("printenv", "src/printenv.zig");
    printenv.setTarget(target);
    printenv.setBuildMode(mode);
    printenv.install();

    const pwd = b.addExecutable("pwd", "src/pwd.zig");
    pwd.setTarget(target);
    pwd.setBuildMode(mode);
    pwd.install();

    const sleep = b.addExecutable("sleep", "src/sleep.zig");
    sleep.setTarget(target);
    sleep.setBuildMode(mode);
    sleep.install();

    const true_app = b.addExecutable("true", "src/true.zig");
    true_app.setTarget(target);
    true_app.setBuildMode(mode);
    true_app.install();

    const tty = b.addExecutable("tty", "src/tty.zig");
    tty.setTarget(target);
    tty.setBuildMode(mode);
    tty.install();

    const whoami = b.addExecutable("whoami", "src/whoami.zig");
    whoami.setTarget(target);
    whoami.setBuildMode(mode);
    whoami.install();

    const yes = b.addExecutable("yes", "src/yes.zig");
    yes.setTarget(target);
    yes.setBuildMode(mode);
    yes.install();

    if (os == .linux) {
        groups.linkSystemLibrary("c");
        hostid.linkSystemLibrary("c");
        logname.linkSystemLibrary("c");
        nproc.linkSystemLibrary("c");
        printenv.linkSystemLibrary("c");
        tty.linkSystemLibrary("c");
        whoami.linkSystemLibrary("c");
    }

}
