const std = @import("std");

pub const Profile = enum { coding, iot, robotics };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Feature flags
    const enable_ble = b.option(bool, "ble", "Enable BLE transport support") orelse false;
    const enable_serial = b.option(bool, "serial", "Enable serial/UART transport") orelse false;
    const embedded = b.option(bool, "embedded", "Build for embedded (freestanding, no OS)") orelse false;
    const profile = b.option(Profile, "profile", "Tool profile: coding (default), iot, robotics") orelse .coding;
    const sandbox = b.option(bool, "sandbox", "Enable sandbox mode: restricted execution, no network, simulated backends") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "enable_ble", enable_ble);
    options.addOption(bool, "enable_serial", enable_serial);
    options.addOption(bool, "embedded", embedded);
    options.addOption(Profile, "profile", profile);
    options.addOption(bool, "sandbox", sandbox);

    const exe = b.addExecutable(.{
        .name = "yoctoclaw",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run YoctoClaw");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addOptions("build_options", options);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // Size report step
    const size_step = b.step("size", "Report binary size");
    const size_cmd = b.addSystemCommand(&.{ "ls", "-la" });
    size_cmd.addArtifactArg(exe);
    size_cmd.step.dependOn(b.getInstallStep());
    size_step.dependOn(&size_cmd.step);
}
