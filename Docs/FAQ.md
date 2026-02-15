# YoctoClaw FAQ

### "Is this a toy?"

No. 39 unit tests, CI pipeline, streaming, context management, stuck-loop detection. The entire codebase is auditable in an hour.

### "You still need an LLM — so it's not really self-contained?"

Correct. YoctoClaw is the harness, not the model. Same as Claude Code needing Claude, or Aider needing an API key. The difference is the harness is 180KB instead of 50MB.

### "Why would I use this over Claude Code?"

You wouldn't, unless you need: extreme resource constraints, embedded deployment, auditable codebase, or you want to understand how a coding agent works end-to-end.

### "Does it actually run on a smart ring?"

The BLE transport architecture supports it. We've tested BLE communication with nRF5340 dev boards. Smart ring integration is designed for but not yet demonstrated on consumer hardware.

### "180KB but what about the LLM?"

Fair point. The 180KB claim is about the agent binary, not the full system. We're explicit about this because we think the harness size matters independently — it determines where the agent CAN run.

### "IoT and Robotics profiles look incomplete"

They are. Marked as [Preview]. The coding profile is production-ready. IoT and Robotics ship fully in v0.2.

### "Is Zig too niche?"

Zig compiles to any target LLVM supports. The binary runs everywhere. You don't need to know Zig to use YoctoClaw.

### "No one needs embedded agents"

Yet. The same was said about putting Linux on everything in 2005.
