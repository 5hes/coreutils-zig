const std = @import("std");
const linux = std.os.linux;
const fs = std.fs;

const mem = std.mem;
const uid = linux.uid_t;
const gid = linux.gid_t;

const clap = @import("clap.zig");
const version = @import("util/version.zig");
const users = @import("util/users.zig");
const strings = @import("util/strings.zig");
const time_info = @import("util/time.zig");
const utmp = @import("util/utmp.zig");


const Allocator = std.mem.Allocator;
const print = std.debug.print;
const UtType = utmp.UtType;

const default_allocator = std.heap.page_allocator;

const application_name = "who";

const help_message =
\\Usage: who [OPTION]... [ FILE | ARG1 ARG2 ]
\\Print information about users who are currently logged in.
\\
\\  -a, --all         same as -b -d --login -p -r -t -T -u
\\  -b, --boot        time of last system boot
\\  -d, --dead        print dead processes
\\  -H, --heading     print line of column headings
\\      --ips         print ips instead of hostnames. with --lookup,
\\                    canonicalizes based on stored IP, if available,
\\                    rather than stored hostname
\\  -l, --login       print system login processes
\\      --lookup      attempt to canonicalize hostnames via DNS
\\  -m                only hostname and user associated with stdin
\\  -p, --process     print active processes spawned by init
\\  -q, --count       all login names and number of users logged on
\\  -r, --runlevel    print current runlevel
\\  -s, --short       print only name, line, and time (default)
\\  -t, --time        print last system clock change
\\  -T, -w, --mesg    add user's message status as +, - or ?
\\  -u, --users       list users logged in
\\      --message     same as -T
\\      --writable    same as -T
\\      --help     display this help and exit
\\      --version  output version information and exit
\\
\\If FILE is not specified, use /var/run/utmp first and /var/log/wtmp second.  /var/log/wtmp as FILE is common.
\\If ARG1 ARG2 given, -m presumed: 'am i' or 'mom likes' are usual.
\\
;

extern fn getgrouplist(user: [*:0]const u8, group: gid, groups: [*]gid, ngroups: *c_int) callconv(.C) c_int;

pub fn main() !void {

    const params = comptime [_]clap.Param(clap.Help){
        clap.parseParam("--help") catch unreachable,
        clap.parseParam("--version") catch unreachable,
        clap.parseParam("-a, --all") catch unreachable,
        clap.parseParam("-b, --boot") catch unreachable,
        clap.parseParam("-d, --dead") catch unreachable,
        clap.parseParam("-H, --heading") catch unreachable,
        clap.parseParam("--ips") catch unreachable,
        clap.parseParam("-l, --login") catch unreachable,
        clap.parseParam("--lookup") catch unreachable,
        clap.parseParam("-m") catch unreachable,
        clap.parseParam("-p, --process") catch unreachable,
        clap.parseParam("-q, --count") catch unreachable,
        clap.parseParam("-r, --runlevel") catch unreachable,
        clap.parseParam("-s, --short") catch unreachable,
        clap.parseParam("-t, --time") catch unreachable,
        clap.parseParam("-T -w, --mesg") catch unreachable,
        clap.parseParam("-u, --users") catch unreachable,
        clap.parseParam("--message") catch unreachable,
        clap.parseParam("--writable") catch unreachable,
        clap.parseParam("-v, --verbose") catch unreachable,
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
    
    const all = args.flag("-a");
    const boot = args.flag("-b") or all;
    const dead = args.flag("-d") or all;
    const heading = args.flag("-H");
    const ips = args.flag("--ips");
    const login = args.flag("-l") or all;
    const lookup = args.flag("--lookup");
    const stdin_users = args.flag("-m");
    const processes = args.flag("-p") or all;
    const count = args.flag("-q");
    const runlevel = args.flag("-r") or all;
    const short = args.flag("-s");
    const time = args.flag("-t") or all;
    const message_status = args.flag("-T") or args.flag("--message") or args.flag("--writable") or all;
    const list_users = args.flag("-u") or all;
  
    checkConflicts(boot, dead, heading, ips, login, lookup, stdin_users, processes, count, runlevel, short, time, message_status, list_users);


    const arguments = args.positionals();
    

    if (arguments.len == 0) {
        try printInformation(default_allocator, utmp.determine_utmp_file(), boot, dead, heading, ips, login, lookup, stdin_users, processes, count, runlevel, short, time, message_status, list_users);   
    } else if (arguments.len == 1) {
        try printInformation(default_allocator, arguments[0], boot, dead, heading, ips, login, lookup, stdin_users, processes, count, runlevel, short, time, message_status, list_users);   
    } else if (arguments.len == 2){
        
    } else {
        std.debug.print("Zero, one or two arguments expected.\n", .{});
        std.os.exit(1);
    }
}

fn checkConflicts(boot: bool, dead: bool, heading: bool, ips: bool, login: bool, lookup: bool, stdin_users: bool, processes: bool, count_users: bool, runlevel: bool, short: bool, time: bool, message_status: bool, list_users: bool) void {
    if (count_users and (boot or dead or heading or ips or login or stdin_users or processes or runlevel or short or time or message_status or list_users)) {
        print("{s}: \"-q\" cannot be combined with other output flags", .{application_name});
        std.os.exit(1);
    }
}

fn intOfBool(boolean: bool) u8 {
    if (boolean) {
        return 1;
    } else {
        return 0;
    }
}


fn printInformation(alloc: *std.mem.Allocator, file_name: []const u8, boot: bool, dead: bool, heading: bool, ips: bool, login: bool, lookup: bool, stdin_users: bool, processes: bool, count_users: bool, runlevel: bool, short: bool, time: bool, message_status: bool, list_users: bool) !void {
    const file_contents = fs.cwd().readFileAlloc(alloc, file_name, 1 << 20) catch "";
    if (file_contents.len > 0 and file_contents.len % @sizeOf(utmp.Utmp) == 0) {
        const utmp_logs = utmp.convertBytesToUtmpRecords(file_contents);
        var count: u32 = 0;
        for (utmp_logs) |log| {
            //print("{s}\n", .{log});
            if (log.ut_type == UtType.USER_PROCESS) {
                count += 1;
            }
        }
        if (count_users) {
            var login_info = try alloc.alloc([]const u8, count);
            var insert_index: usize = 0;
            for (utmp_logs) |log| {
                if (log.ut_type == UtType.USER_PROCESS) {
                    var null_index = strings.indexOf(log.ut_user[0..], 0);
                    if (null_index == null) null_index = 32;
                    const copy = try alloc.alloc(u8, null_index.?);
                    std.mem.copy(u8, copy, log.ut_user[0..null_index.?]);
                    var check_index: usize = 0;
                    var insert = true;
                    while (check_index < insert_index) {
                        if (std.mem.eql(u8, copy, login_info[check_index])) {
                            insert = false;
                        }
                        check_index += 1;
                    }
                    if (insert) {
                        login_info[insert_index] = copy;
                        insert_index+=1;
                    }
                }
            }
            for (login_info[0..insert_index]) |user, i| {
                print("{s}", .{user});
                if (i != login_info[0..insert_index].len - 1) {
                    std.debug.print(" ", .{});
                }
            }
            print("\n# users={d}\n", .{insert_index});
        } else {
            if (heading) {
                print("{s: <8} {s: <12} {s: <16}", .{"NAME", "LINE", "TIME"});
                if (login or runlevel or stdin_users) {
                    print("{s: <13}", .{"IDLE"});
                }
                if (login or processes or stdin_users) {
                    print("{s: <4}", .{"PID"});
                }
                print("{s: <8}", .{"COMMENT"});
                print("\n", .{});
            }
            for (utmp_logs) |log| {
                if (log.ut_type == UtType.USER_PROCESS) {
                    const username = strings.substringFromNullTerminatedSlice(log.ut_user[0..]);
                    const term = strings.substringFromNullTerminatedSlice(log.ut_line[0..]);
                    const time_struct = time_info.getLocalTimeStructFromi32(log.ut_tv.tv_sec);
                    const time_string = time_info.toLocalDateTimeStringAlloc(default_allocator, time_struct);       
                    //print("{s: <8} {s: <12} {s: <16} {s: <13} {s: <4} {s: <8} {s}\n", .{username, term, time_string, "", pid, log.ut_id, ""});
                    print("{s: <8} {s: <12} {s: <16}", .{username, term, time_string});
                    try printConditionalDetails(alloc, log, login, runlevel, stdin_users, processes);
                } else if (log.ut_type == UtType.BOOT_TIME and boot) {
                
                } else if (log.ut_type == UtType.RUN_LVL and runlevel) {
                
                } else if (log.ut_type == UtType.LOGIN_PROCESS and login) {
                
                } else if (log.ut_type == UtType.DEAD_PROCESS and dead) {
                
                }
            }
            
        }
        
    }
}

fn printConditionalDetails(alloc: *std.mem.Allocator, utmp_log: utmp.Utmp, login: bool, runlevel: bool, stdin_users: bool, processes: bool) !void {
    if (login or runlevel or stdin_users) {
        print("{s: <13}", .{""});
    }
    if (login or processes or stdin_users) {
        var pid: []const u8 = "";
        if (utmp_log.ut_pid != 0) {
            var buffer: [10]u8 = undefined;
            pid = std.fmt.bufPrintIntToSlice(buffer[0..], utmp_log.ut_pid, 10, false, std.fmt.FormatOptions{});
        }
        print("{s: <4}", .{pid});
    }
    print("{s: <8}", .{""});
    print("\n", .{});
}
