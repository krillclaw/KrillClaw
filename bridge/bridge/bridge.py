#!/usr/bin/env python3
"""
YoctoClaw Bridge — connects a BLE/Serial YoctoClaw device to Claude API.

The bridge receives RPC messages from YoctoClaw running on embedded hardware,
forwards API calls to Claude, executes tools locally, and sends results back.

Usage:
  # BLE mode (connect to YoctoClaw ring/device):
  python bridge.py --ble

  # Serial mode (connect to YoctoClaw dev board):
  python bridge.py --serial /dev/ttyUSB0

  # Unix socket mode (for desktop BLE simulation):
  python bridge.py --socket /tmp/yoctoclaw.sock
"""

import argparse
import asyncio
import json
import os
import struct
import subprocess
import sys

try:
    import anthropic
except ImportError:
    print("pip install anthropic")
    sys.exit(1)


class YoctoClawBridge:
    def __init__(self, api_key: str, model: str = "claude-sonnet-4-5-20250929"):
        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = model

    def handle_message(self, data: bytes) -> bytes:
        """Process an RPC message and return the response."""
        msg = json.loads(data)
        msg_type = msg.get("type", "")

        if msg_type == "api":
            return self._handle_api(msg)
        elif msg_type == "tool":
            return self._handle_tool(msg)
        else:
            return json.dumps({"error": f"Unknown type: {msg_type}"}).encode()

    def _handle_api(self, msg: dict) -> bytes:
        """Forward API call to Claude and return response."""
        body = json.loads(msg.get("body", "{}"))

        try:
            response = self.client.messages.create(
                model=body.get("model", self.model),
                max_tokens=body.get("max_tokens", 8192),
                system=body.get("system", ""),
                tools=body.get("tools", []),
                messages=body.get("messages", []),
            )
            return json.dumps({
                "type": "api_result",
                "body": response.model_dump_json(),
            }).encode()
        except Exception as e:
            return json.dumps({
                "type": "api_result",
                "error": str(e),
            }).encode()

    def _handle_tool(self, msg: dict) -> bytes:
        """Execute a tool locally and return result."""
        name = msg.get("name", "")
        input_data = msg.get("input", {})
        if isinstance(input_data, str):
            input_data = json.loads(input_data)

        try:
            if name == "bash":
                result = subprocess.run(
                    input_data["command"],
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                output = result.stdout
                if result.stderr:
                    output += f"\n--- stderr ---\n{result.stderr}"
                return json.dumps({
                    "type": "tool_result",
                    "output": output or "(no output)",
                    "is_error": result.returncode != 0,
                }).encode()

            elif name == "read_file":
                with open(input_data["path"], "r") as f:
                    content = f.read()
                return json.dumps({
                    "type": "tool_result",
                    "output": content or "(empty file)",
                    "is_error": False,
                }).encode()

            elif name == "write_file":
                path = input_data["path"]
                os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
                with open(path, "w") as f:
                    f.write(input_data["content"])
                return json.dumps({
                    "type": "tool_result",
                    "output": f"Wrote {len(input_data['content'])} bytes to {path}",
                    "is_error": False,
                }).encode()

            elif name == "search":
                # Use argument list — no shell, no injection risk
                search_path = input_data.get("path", ".")
                pattern = input_data["pattern"]
                result = subprocess.run(
                    ["grep", "-rn", "--", pattern, search_path],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                output = result.stdout
                # Truncate to ~100 lines
                lines = output.split("\n")
                if len(lines) > 100:
                    output = "\n".join(lines[:100]) + f"\n... ({len(lines)} total lines)"
                return json.dumps({
                    "type": "tool_result",
                    "output": output or "No matches found",
                    "is_error": False,
                }).encode()

            else:
                return json.dumps({
                    "type": "tool_result",
                    "output": f"Unknown tool: {name}",
                    "is_error": True,
                }).encode()

        except Exception as e:
            return json.dumps({
                "type": "tool_result",
                "output": str(e),
                "is_error": True,
            }).encode()


async def socket_server(bridge: YoctoClawBridge, path: str):
    """Unix socket server for desktop BLE simulation."""
    if os.path.exists(path):
        os.unlink(path)

    async def handle_client(reader, writer):
        print(f"[bridge] Device connected")
        try:
            while True:
                # Read length-prefixed message
                len_data = await reader.readexactly(2)
                msg_len = struct.unpack(">H", len_data)[0]
                msg_data = await reader.readexactly(msg_len)

                print(f"[bridge] <- {msg_data[:100]}...")

                # Process
                response = bridge.handle_message(msg_data)

                print(f"[bridge] -> {response[:100]}...")

                # Send length-prefixed response
                writer.write(struct.pack(">H", len(response)))
                writer.write(response)
                await writer.drain()
        except (asyncio.IncompleteReadError, ConnectionResetError):
            print(f"[bridge] Device disconnected")
        finally:
            writer.close()

    server = await asyncio.start_unix_server(handle_client, path=path)
    print(f"[bridge] Listening on {path}")
    print(f"[bridge] Waiting for YoctoClaw device...")
    async with server:
        await server.serve_forever()


async def serial_bridge(bridge: YoctoClawBridge, port: str, baud: int = 115200):
    """Serial port bridge for UART-connected devices."""
    try:
        import serial as pyserial
    except ImportError:
        print("pip install pyserial")
        sys.exit(1)

    ser = pyserial.Serial(port, baud, timeout=None)
    print(f"[bridge] Connected to {port} @ {baud}")

    while True:
        # Read length-prefixed message
        len_data = ser.read(2)
        if len(len_data) < 2:
            continue
        msg_len = struct.unpack(">H", len_data)[0]
        msg_data = ser.read(msg_len)

        print(f"[bridge] <- {msg_data[:80]}...")

        response = bridge.handle_message(msg_data)

        print(f"[bridge] -> {response[:80]}...")

        ser.write(struct.pack(">H", len(response)))
        ser.write(response)


async def ble_bridge(bridge: YoctoClawBridge):
    """BLE bridge using bleak (scans for YoctoClaw device)."""
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError:
        print("pip install bleak")
        sys.exit(1)

    SERVICE_UUID = "0000pc01-0000-1000-8000-00805f9b34fb"
    TX_UUID = "0000pc02-0000-1000-8000-00805f9b34fb"
    RX_UUID = "0000pc03-0000-1000-8000-00805f9b34fb"

    print("[bridge] Scanning for YoctoClaw BLE device...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, ad: SERVICE_UUID.lower() in [s.lower() for s in (ad.service_uuids or [])],
        timeout=30.0,
    )

    if not device:
        print("[bridge] No YoctoClaw device found")
        return

    print(f"[bridge] Found: {device.name} ({device.address})")

    async with BleakClient(device) as client:
        print(f"[bridge] Connected")

        response_data = bytearray()

        def notification_handler(sender, data):
            """Handle data from YoctoClaw device (TX characteristic)."""
            nonlocal response_data
            response = bridge.handle_message(bytes(data))
            response_data = bytearray(response)

        await client.start_notify(TX_UUID, notification_handler)

        # Main loop: check for pending responses to send back
        while client.is_connected:
            if response_data:
                # Chunk and send response via RX characteristic
                data = bytes(response_data)
                response_data = bytearray()

                # Send in MTU-sized chunks
                mtu = 244
                for i in range(0, len(data), mtu):
                    chunk = data[i : i + mtu]
                    await client.write_gatt_char(RX_UUID, chunk)

            await asyncio.sleep(0.01)


def main():
    parser = argparse.ArgumentParser(description="YoctoClaw Bridge")
    parser.add_argument("--socket", help="Unix socket path (simulation mode)")
    parser.add_argument("--serial", help="Serial port path")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate")
    parser.add_argument("--ble", action="store_true", help="BLE mode")
    parser.add_argument("--model", default="claude-sonnet-4-5-20250929")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        print("Set ANTHROPIC_API_KEY environment variable")
        sys.exit(1)

    bridge = YoctoClawBridge(api_key=api_key, model=args.model)

    if args.socket:
        asyncio.run(socket_server(bridge, args.socket))
    elif args.serial:
        asyncio.run(serial_bridge(bridge, args.serial, args.baud))
    elif args.ble:
        asyncio.run(ble_bridge(bridge))
    else:
        # Default: Unix socket simulation
        asyncio.run(socket_server(bridge, "/tmp/yoctoclaw.sock"))


if __name__ == "__main__":
    main()
