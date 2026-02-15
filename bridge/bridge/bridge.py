#!/usr/bin/env python3
"""
YoctoClaw Bridge — connects a BLE/Serial YoctoClaw device to Claude API.

The bridge receives RPC messages from YoctoClaw running on embedded hardware,
forwards API calls to Claude, executes tools locally, and sends results back.

Also supports --exec-tool mode: receives a JSON command as argv[2], dispatches
to the appropriate handler, and prints JSON response to stdout.

Usage:
  # BLE mode (connect to YoctoClaw ring/device):
  python bridge.py --ble

  # Serial mode (connect to YoctoClaw dev board):
  python bridge.py --serial /dev/ttyUSB0

  # Unix socket mode (for desktop BLE simulation):
  python bridge.py --socket /tmp/yoctoclaw.sock

  # Direct tool execution (called by Zig IoT/robotics profiles):
  python bridge.py --exec-tool '{"action":"mqtt_publish","topic":"test","payload":"hello"}'
"""

import argparse
import asyncio
import json
import os
import struct
import subprocess
import sys
import time
import platform

try:
    import anthropic
except ImportError:
    anthropic = None

# ============================================================
# Tool Handlers (used by --exec-tool mode)
# ============================================================

ROBOT_LOG_PATH = os.path.expanduser("~/.yoctoclaw/robot_commands.log")


def handle_mqtt_publish(data):
    """Publish to an MQTT topic using paho-mqtt."""
    try:
        import paho.mqtt.client as mqtt
    except ImportError:
        return {"error": "paho-mqtt not installed. Run: pip install paho-mqtt"}

    topic = data.get("topic", "")
    payload = data.get("payload", "")
    broker = data.get("broker", "localhost")
    port = data.get("port", 1883)

    try:
        client = mqtt.Client()
        client.connect(broker, port, 60)
        result = client.publish(topic, payload)
        client.disconnect()
        return {
            "status": "published",
            "topic": topic,
            "payload_size": len(payload),
            "rc": result.rc,
        }
    except Exception as e:
        return {"error": f"MQTT publish failed: {e}"}


def handle_mqtt_subscribe(data):
    """Subscribe to an MQTT topic and wait for one message."""
    try:
        import paho.mqtt.client as mqtt
    except ImportError:
        return {"error": "paho-mqtt not installed. Run: pip install paho-mqtt"}

    topic = data.get("topic", "")
    timeout_ms = data.get("timeout_ms", 5000)
    broker = data.get("broker", "localhost")
    port = data.get("port", 1883)

    received = {"message": None}

    def on_message(client, userdata, msg):
        received["message"] = {
            "topic": msg.topic,
            "payload": msg.payload.decode("utf-8", errors="replace"),
            "qos": msg.qos,
        }

    try:
        client = mqtt.Client()
        client.on_message = on_message
        client.connect(broker, port, 60)
        client.subscribe(topic)
        client.loop_start()
        deadline = time.time() + (timeout_ms / 1000.0)
        while received["message"] is None and time.time() < deadline:
            time.sleep(0.05)
        client.loop_stop()
        client.disconnect()

        if received["message"]:
            return {"status": "received", **received["message"]}
        else:
            return {"status": "timeout", "topic": topic, "timeout_ms": timeout_ms}
    except Exception as e:
        return {"error": f"MQTT subscribe failed: {e}"}


def handle_http_request(data):
    """Make an HTTP request using urllib (stdlib, no deps)."""
    import urllib.request
    import urllib.error

    method = data.get("method", "GET")
    url = data.get("url", "")
    body = data.get("body", "")
    headers = data.get("headers", {})

    if not url:
        return {"error": "Missing 'url'"}

    try:
        body_bytes = body.encode("utf-8") if body else None
        req = urllib.request.Request(url, data=body_bytes, method=method)
        for k, v in headers.items():
            req.add_header(k, v)
        if body and "Content-Type" not in headers:
            req.add_header("Content-Type", "application/json")

        with urllib.request.urlopen(req, timeout=30) as resp:
            resp_body = resp.read().decode("utf-8", errors="replace")
            return {
                "status": resp.status,
                "headers": dict(resp.headers),
                "body": resp_body[:65536],  # Cap at 64KB
            }
    except urllib.error.HTTPError as e:
        return {
            "status": e.code,
            "error": str(e.reason),
            "body": e.read().decode("utf-8", errors="replace")[:65536],
        }
    except Exception as e:
        return {"error": f"HTTP request failed: {e}"}


def handle_robot_cmd(data):
    """
    Handle a robot command (pose/velocity/gripper).
    In simulator mode, logs to file and returns success.
    # TODO: Plug in real ROS/hardware bindings here.
    # For ROS2: use rclpy to publish to /cmd_vel, /joint_states, /gripper_command
    # For direct hardware: use serial/CAN bus communication to motor controllers
    """
    cmd_type = data.get("type", "unknown")
    params = data.get("params", {})

    os.makedirs(os.path.dirname(ROBOT_LOG_PATH), exist_ok=True)
    with open(ROBOT_LOG_PATH, "a") as f:
        f.write(json.dumps({
            "timestamp": time.time(),
            "type": cmd_type,
            "params": params,
        }) + "\n")

    return {
        "status": "executed",
        "mode": "simulator",
        "type": cmd_type,
        "message": f"Robot command '{cmd_type}' logged (simulator mode)",
    }


def handle_estop(data):
    """
    Emergency stop handler.
    # TODO: In real hardware mode, this should:
    # 1. Send immediate stop to all motor controllers
    # 2. Engage physical brakes if available
    # 3. Publish to /emergency_stop topic (ROS)
    """
    os.makedirs(os.path.dirname(ROBOT_LOG_PATH), exist_ok=True)
    with open(ROBOT_LOG_PATH, "a") as f:
        f.write(json.dumps({
            "timestamp": time.time(),
            "type": "ESTOP",
            "reason": data.get("reason", "manual"),
        }) + "\n")

    return {
        "status": "estop_activated",
        "mode": "simulator",
        "message": "Emergency stop activated (simulator mode)",
    }


def handle_telemetry(data):
    """
    Return telemetry snapshot.
    In simulator mode, returns system stats as simulated robot telemetry.
    # TODO: In real hardware mode, read from:
    # - /joint_states topic (ROS)
    # - IMU sensor data
    # - Motor encoder feedback
    # - Battery management system
    """
    # psutil not required — using cross-platform alternatives below

    uptime_s = 0
    cpu_pct = 0.0
    mem_total = 0
    mem_used = 0

    try:
        # Cross-platform uptime
        if os.path.exists("/proc/uptime"):
            with open("/proc/uptime") as f:
                uptime_s = float(f.read().split()[0])
        else:
            # macOS: parse sysctl
            result = subprocess.run(
                ["sysctl", "-n", "kern.boottime"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                # Parse "{ sec = 1234567890, usec = 0 }"
                import re
                m = re.search(r"sec\s*=\s*(\d+)", result.stdout)
                if m:
                    uptime_s = time.time() - int(m.group(1))
    except Exception:
        pass

    try:
        # CPU: quick sample via os.getloadavg()
        load = os.getloadavg()
        cpu_pct = load[0] * 100.0 / os.cpu_count()
    except Exception:
        pass

    try:
        if platform.system() == "Darwin":
            result = subprocess.run(
                ["sysctl", "-n", "hw.memsize"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                mem_total = int(result.stdout.strip())
            # Approximate used memory via vm_stat
            result2 = subprocess.run(
                ["vm_stat"], capture_output=True, text=True, timeout=5
            )
            if result2.returncode == 0:
                import re
                pages_active = 0
                pages_wired = 0
                for line in result2.stdout.splitlines():
                    m = re.match(r"Pages active:\s+(\d+)", line)
                    if m: pages_active = int(m.group(1))
                    m = re.match(r"Pages wired down:\s+(\d+)", line)
                    if m: pages_wired = int(m.group(1))
                mem_used = (pages_active + pages_wired) * 4096
        elif os.path.exists("/proc/meminfo"):
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        mem_total = int(line.split()[1]) * 1024
                    elif line.startswith("MemAvailable:"):
                        mem_used = mem_total - int(line.split()[1]) * 1024
    except Exception:
        pass

    return {
        "mode": "simulator",
        "uptime_seconds": round(uptime_s, 1),
        "cpu_percent": round(cpu_pct, 1),
        "memory_total_bytes": mem_total,
        "memory_used_bytes": mem_used,
        "position": {"x": 0.0, "y": 0.0, "z": 0.0},
        "velocity": {"vx": 0.0, "vy": 0.0, "vz": 0.0},
        "gripper": 0.0,
        "estop": False,
        "status": "idle",
    }


# Dispatch table for --exec-tool mode
TOOL_HANDLERS = {
    "mqtt_publish": handle_mqtt_publish,
    "mqtt_subscribe": handle_mqtt_subscribe,
    "http_request": handle_http_request,
    "robot_cmd": handle_robot_cmd,
    "estop": handle_estop,
    "telemetry": handle_telemetry,
}


def exec_tool_mode(json_str):
    """Parse JSON command, dispatch to handler, print JSON response."""
    try:
        data = json.loads(json_str)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON: {e}"}))
        sys.exit(1)

    action = data.get("action", "")
    handler = TOOL_HANDLERS.get(action)

    if handler is None:
        print(json.dumps({"error": f"Unknown action: {action}"}))
        sys.exit(1)

    try:
        result = handler(data)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


# ============================================================
# Original Bridge (BLE/Serial/Socket)
# ============================================================

class YoctoClawBridge:
    def __init__(self, api_key: str, model: str = "claude-sonnet-4-5-20250929"):
        if anthropic is None:
            raise ImportError("pip install anthropic")
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
                search_path = input_data.get("path", ".")
                pattern = input_data["pattern"]
                result = subprocess.run(
                    ["grep", "-rn", "--", pattern, search_path],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                output = result.stdout
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
                len_data = await reader.readexactly(2)
                msg_len = struct.unpack(">H", len_data)[0]
                msg_data = await reader.readexactly(msg_len)

                print(f"[bridge] <- {msg_data[:100]}...")

                response = bridge.handle_message(msg_data)

                print(f"[bridge] -> {response[:100]}...")

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
            nonlocal response_data
            response = bridge.handle_message(bytes(data))
            response_data = bytearray(response)

        await client.start_notify(TX_UUID, notification_handler)

        while client.is_connected:
            if response_data:
                data = bytes(response_data)
                response_data = bytearray()

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
    parser.add_argument("--exec-tool", dest="exec_tool", help="Execute a tool command (JSON string)")
    args = parser.parse_args()

    # --exec-tool mode: no API key needed, just dispatch and exit
    if args.exec_tool:
        exec_tool_mode(args.exec_tool)
        return

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
        asyncio.run(socket_server(bridge, "/tmp/yoctoclaw.sock"))


if __name__ == "__main__":
    main()
