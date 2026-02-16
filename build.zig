const std = @import("std");

/// Tool profile — selects which tool set is available.
pub const ToolProfile = enum { coding, iot, robotics };

/// Deployment profile — Lite (BLE/serial, no HTTP) or Full (everything).
pub const DeployProfile = enum { lite, full };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Feature flags
    const enable_ble = b.option(bool, "ble", "Enable BLE transport support") orelse false;
    const enable_serial = b.option(bool, "serial", "Enable serial/UART transport") orelse false;
    const embedded = b.option(bool, "embedded", "Build for embedded (freestanding, no OS)") orelse false;
    const tool_profile = b.option(ToolProfile, "tool-profile", "Tool profile: coding (default), iot, robotics") orelse .coding;
    const sandbox = b.option(bool, "sandbox", "Enable sandbox mode") orelse false;

    // Deployment profile: lite or full (default: full)
    const deploy_profile = b.option(DeployProfile, "profile", "Deployment profile: lite (BLE/serial only, ~180KB) or full (all features, ~500KB)") orelse .full;

    const options = b.addOptions();
    options.addOption(bool, "enable_ble", enable_ble or deploy_profile == .lite);
    options.addOption(bool, "enable_serial", enable_serial or deploy_profile == .lite);
    options.addOption(bool, "embedded", embedded or deploy_profile == .lite);
    options.addOption(ToolProfile, "profile", tool_profile);
    options.addOption(bool, "sandbox", sandbox);
    options.addOption(DeployProfile, "deploy_profile", deploy_profile);
    // Capability flags for comptime guards
    options.addOption(bool, "has_http", deploy_profile == .full);
    options.addOption(bool, "has_tls", deploy_profile == .full);
    options.addOption(bool, "has_process", deploy_profile == .full);
    options.addOption(bool, "has_filesystem", deploy_profile == .full);

    const exe_name: []const u8 = switch (deploy_profile) {
        .lite => "krillclaw-lite",
        .full => "yoctoclaw",
    };

    const root_source: std.Build.LazyPath = switch (deploy_profile) {
        .lite => b.path("src/main_lite.zig"),
        .full => b.path("src/main.zig"),
    };

    const mod = b.createModule(.{
        .root_source_file = root_source,
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = mod,
    });

    // Size optimization: strip debug info and frame pointers
    exe.root_module.strip = true;
    exe.root_module.omit_frame_pointer = true;

    b.installArtifact(exe);

    // Run step (full profile only)
    if (deploy_profile == .full) {
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run YoctoClaw");
        run_step.dependOn(&run_cmd.step);
    }

    // Test step (full profile only — lite has no OS-dependent tests)
    if (deploy_profile == .full) {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addOptions("build_options", options);

        const tests = b.addTest(.{
            .root_module = test_mod,
        });

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }

    // Size report step
    const size_step = b.step("size", "Report binary size");
    const size_cmd = b.addSystemCommand(&.{ "ls", "-la" });
    size_cmd.addArtifactArg(exe);
    size_cmd.step.dependOn(b.getInstallStep());
    size_step.dependOn(&size_cmd.step);

    // Size budget check step
    const budget_limit: []const u8 = switch (deploy_profile) {
        .lite => "184320",
        .full => "512000",
    };
    const profile_name: []const u8 = switch (deploy_profile) {
        .lite => "lite",
        .full => "full",
    };
    const size_check_cmd = b.addSystemCommand(&.{ "sh", "scripts/size-check.sh" });
    size_check_cmd.addArtifactArg(exe);
    size_check_cmd.addArgs(&.{ budget_limit, profile_name });
    size_check_cmd.step.dependOn(b.getInstallStep());

    const check_step = b.step("size-check", "Verify binary fits size budget");
    check_step.dependOn(&size_check_cmd.step);
}
