const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const os = std.os;
const io = std.io;
const testing = std.testing;
const hash = std.crypto.hash;

const clap = @import("clap.zig");
const fileinfo = @import("util/fileinfo.zig");
const version = @import("util/version.zig");

const Allocator = std.mem.Allocator;
const LinkError = os.LinkError;
const Md5 = hash.Md5;

const default_allocator = std.heap.page_allocator;
const print = std.debug.print;

const application_name = "md5sum";
const HASH_BYTE_SIZE = 16;
const block_read = 1 << 22;

const help_message =
    \\Usage: md5sum [OPTION]... [FILE]...
    \\Print or check MD5 (128-bit) checksums.
    \\
    \\With no FILE, or when FILE is -, read standard input.
    \\
    \\  -b, --binary         does nothing (compatibility)
    \\  -c, --check          read MD5 sums from the FILEs and check them
    \\      --tag            create a BSD-style checksum
    \\  -t, --text           does nothing (compatibility)
    \\  -z, --zero           end each output line with NUL, not newline,
    \\                       and disable file name escaping
    \\
    \\The following five options are useful only when verifying checksums:
    \\      --ignore-missing  don't fail or report status for missing files
    \\      --quiet          don't print OK for each successfully verified file
    \\      --status         don't output anything, status code shows success
    \\      --strict         exit non-zero for improperly formatted checksum lines
    \\  -w, --warn           warn about improperly formatted checksum lines
    \\
    \\      --help     display this help and exit
    \\      --version  output version information and exit
    \\
    \\The sums are computed as described in RFC 1321.  When checking, the input
    \\should be a former output of this program.  The default mode is to print a
    \\line with checksum, a space, a character indicating input mode ('*' for binary,
    \\' ' for text or where binary is insignificant), and name for each FILE.
    \\
;

var handled_stdin = false;

const HashError = error{ FileDoesNotExist, IsDir, FileAccessFailed, OtherError };

pub fn main() !void {
    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("--help") catch unreachable,
        clap.parseParam("--version") catch unreachable,
        clap.parseParam("-b, --binary") catch unreachable,
        clap.parseParam("-c, --check") catch unreachable,
        clap.parseParam("--tag") catch unreachable,
        clap.parseParam("-t, --text") catch unreachable,
        clap.parseParam("-z, --zero") catch unreachable,
        clap.parseParam("--ignore-missing") catch unreachable,
        clap.parseParam("--quiet") catch unreachable,
        clap.parseParam("--status") catch unreachable,
        clap.parseParam("--strict") catch unreachable,
        clap.parseParam("-w, --warn") catch unreachable,
        clap.parseParam("<STRING>") catch unreachable,
    };

    var diag = clap.Diagnostic{};
    var args = clap.parseAndHandleErrors(clap.Help, &params, .{ .diagnostic = &diag }, application_name, 1);
    defer args.deinit();

    if (args.flag("--help")) {
        std.debug.print(help_message, .{});
        std.os.exit(0);
    } else if (args.flag("--version")) {
        version.printVersionInfo(application_name);
        std.os.exit(0);
    }

    const check = args.flag("-c");
    const bsd = args.flag("--tag");
    const zero_terminated = args.flag("-z");
    const ignore_missing = args.flag("--ignore-missing");
    const quiet = args.flag("--quiet");
    const status_only = args.flag("--status");
    const strict = args.flag("--strict");
    const warn = args.flag("-w");

    const terminator: []const u8 = if (zero_terminated) "\x00" else "\n";

    if (!check and (ignore_missing or quiet or status_only or strict or warn)) {
        print("When '--check' is not set, non-check flags may not be active.\n", .{});
        std.os.exit(1);
    }

    const positionals = args.positionals();
    var clean = true;
    if (check) {
        for (positionals) |arg| {
            clean = checkFile(arg, ignore_missing, quiet, status_only, strict, warn) and clean;
        }
    } else {
        for (positionals) |arg| {
            clean = hashFile(arg, bsd, terminator) and clean;
        }
    }
    if (!clean) {
        std.os.exit(1);
    }
}

fn checkFile(path: []const u8, ignore_missing: bool, quiet: bool, status: bool, strict: bool, warn: bool) bool {
    if (mem.eql(u8, "-", path)) {
        if (!handled_stdin) {
            const stdin = std.io.getStdIn().reader();
            const bytes = stdin.readAllAlloc(default_allocator, 1 << 30) catch {
                std.debug.print("Reading stdin failed\n", .{});
                return false;
            };
            defer default_allocator.free(bytes);            
            handled_stdin = true;
            return checkBytes(bytes, ignore_missing, quiet, status, strict, warn);
        }
    } else {
        const stat = fileinfo.getLstat(path) catch |err| {
            print("{s}\n", .{err});
            return false;
        };
        if (!fileinfo.fileExists(stat)) {
            print("{s}: File '{s}' does not exist\n", .{ application_name, path });
            return false;
        }

        if (fileinfo.isDir(stat)) {
            print("{s}: '{s}' is a directory.\n", .{ application_name, path });
            return false;
        }

        const file = fs.cwd().openFile(path, .{ .read = true }) catch {
            print("Could not read file.\n", .{});
            return false;
        };
        defer file.close();
        const bytes = file.readToEndAlloc(default_allocator, 1 << 30) catch return false;        
        defer default_allocator.free(bytes);
        return checkBytes(bytes, ignore_missing, quiet, status, strict, warn);
    }
    return true;

}

fn checkBytes(bytes: []const u8, ignore_missing: bool, quiet: bool, status_only: bool, strict: bool, warn: bool) bool {
    _ = bytes;
    _ = quiet;
    _ = warn;
    var result = true;
    var missing: u32 = 0;
    var incorrect: u32 = 0;
    var format: u32 = 0;
    if ((missing > 0 and !ignore_missing) or incorrect > 0 or (format > 0 and strict)) {
        result = false;
    }
    if (missing > 0 and !status_only and !ignore_missing) {
        print("{s}: WARNING: {d} files could not be read\n", .{application_name, missing});
    }

    if (incorrect > 0 and !status_only) {
        print("{s}: WARNING: {d} hashes did not match\n", .{application_name, missing});
    }

    if (format > 0 and !status_only) {
        print("{s}: WARNING: {d} lines are improperly formatted\n", .{application_name, missing});
    }
    return result;
}

fn hashFile(path: []const u8, bsd: bool, terminator: []const u8) bool {
    if (mem.eql(u8, "-", path)) {
        if (!handled_stdin) {
            const stdin = std.io.getStdIn().reader();
            const bytes = stdin.readAllAlloc(default_allocator, 1 << 30) catch {
                std.debug.print("Reading stdin failed\n", .{});
                return false;
            };
            var hash_result: [HASH_BYTE_SIZE]u8 = undefined;
            Md5.hash(bytes, &hash_result, .{});
            var hash_string: [2 * HASH_BYTE_SIZE]u8 = undefined;
            digest_to_hex_string(&hash_result, &hash_string);
            if (bsd) {
                print("MD5 (-) = {s}{s}", .{ hash_string, terminator });
            } else {
                print("{s}  -{s}", .{ hash_string, terminator });
            }
            handled_stdin = true;
        }
    } else {
        const hash_string = digestFromFile(path) catch unreachable;
        if (bsd) {
            print("MD5 ({s}) = {s}{s}", .{ path, hash_string, terminator });
        } else {
            print("{s}  {s}{s}", .{ hash_string, path, terminator });
        }
    }
    return true;
}

fn digestFromFile(path: []const u8) HashError![2 * HASH_BYTE_SIZE]u8 {
    const stat = fileinfo.getLstat(path) catch |err| {
        print("{s}\n", .{err});
        return HashError.OtherError;
    };
    if (!fileinfo.fileExists(stat)) {
        print("{s}: File '{s}' does not exist\n", .{ application_name, path });
        return HashError.FileDoesNotExist;
    }

    if (fileinfo.isDir(stat)) {
        print("{s}: '{s}' is a directory.\n", .{ application_name, path });
        return HashError.IsDir;
    }

    const file_size = @intCast(u64, stat.size);

    const file = fs.cwd().openFile(path, .{ .read = true }) catch {
        print("Could not read file.\n", .{});
        return HashError.FileAccessFailed;
    };
    defer file.close();

    var offset: usize = 0;
    var file_buffer = default_allocator.alloc(u8, block_read) catch return HashError.OtherError;
    defer default_allocator.free(file_buffer);
    var hash_processor = Md5.init(.{});
    while (offset < file_size) {
        const read = file.pread(file_buffer[0..], offset) catch return HashError.OtherError;
        hash_processor.update(file_buffer[0..read]);
        offset += block_read;
    }
    var hash_result: [HASH_BYTE_SIZE]u8 = undefined;
    hash_processor.final(&hash_result);
    var hash_string: [2 * HASH_BYTE_SIZE]u8 = undefined;
    digest_to_hex_string(&hash_result, &hash_string);
    return hash_string;
}

fn digest_to_hex_string(digest: *[HASH_BYTE_SIZE]u8, string: *[2 * HASH_BYTE_SIZE]u8) void {
    var range: [16]u8 = .{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
    var i: usize = 0;
    while (i < digest.len) : (i += 1) {
        var upper: u8 = digest[i] >> 4;
        var lower: u8 = digest[i] & 15;

        string[2 * i] = range[upper];
        string[(2 * i) + 1] = range[lower];
    }
}
