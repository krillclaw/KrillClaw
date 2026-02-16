//! Compile-time profile detection for Lite/Full deployment profiles.
const build_options = @import("build_options");

pub const DeployProfile = enum { lite, full };

pub const deploy = build_options.deploy_profile;
pub const is_lite = deploy == .lite;
pub const is_full = deploy == .full;
