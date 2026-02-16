//! ReAct (Reason + Act) agent loop constants and helpers.

/// Absolute safety cap — no agent loop may exceed this regardless of config.
pub const MAX_ITERATIONS_HARD_CAP: u32 = 200;
