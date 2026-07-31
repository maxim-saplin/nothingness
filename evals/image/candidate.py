from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


RUNTIME = Path("/run/nothingness")
CONTROL_SOCKET = RUNTIME / "judge-control.sock"
PROVIDER_ENV_KEYS = {
    "azure-openai-responses": {
        "AZURE_OPENAI_API_KEY",
        "AZURE_OPENAI_BASE_URL",
        "AZURE_OPENAI_RESOURCE_NAME",
        "AZURE_OPENAI_API_VERSION",
        "AZURE_OPENAI_DEPLOYMENT_NAME_MAP",
    },
}
RPC_COMMANDS = {"steer", "follow_up", "abort", "get_state", "get_messages", "get_entries", "get_session_stats"}


def timestamp() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(json.dumps(value, separators=(",", ":")) + "\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def provider_environment(provider: str, value: object) -> dict[str, str]:
    allowed = PROVIDER_ENV_KEYS.get(provider, set())
    if not isinstance(value, dict) or any(name not in allowed or not isinstance(raw, str) or not raw for name, raw in value.items()):
        raise ValueError("invalid_provider_environment")
    return dict(value)


def usage_for(event: dict[str, Any]) -> dict[str, Any] | None:
    message = event.get("message")
    if isinstance(message, dict) and isinstance(message.get("usage"), dict):
        return message["usage"]
    return event.get("usage") if isinstance(event.get("usage"), dict) else None


def add_usage(total: dict[str, float], usage: dict[str, Any]) -> None:
    for name in ("input", "output", "reasoning", "cacheRead", "cacheWrite", "totalTokens"):
        value = usage.get(name)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            total[name] += value
    cost = usage.get("cost")
    if "cost" in total and isinstance(cost, dict) and isinstance(cost.get("total"), (int, float)) and not isinstance(cost["total"], bool):
        total["cost"] += cost["total"]


def activity(event: dict[str, Any]) -> str | None:
    event_type = event.get("type")
    tool = event.get("toolName")
    if event_type == "tool_execution_start":
        return f"tool call: {tool or 'unknown'}"
    if event_type == "tool_execution_end":
        return f"tool {'failed' if event.get('isError') else 'completed'}: {tool or 'unknown'}"
    if event_type == "auto_retry_start":
        return "provider retry"
    if event_type == "auto_retry_end":
        return "provider retry ended"
    if event_type == "message_end":
        message = event.get("message")
        role = message.get("role") if isinstance(message, dict) else None
        return f"{role or 'agent'} message"
    return {
        "turn_start": "assistant turn started",
        "turn_end": "assistant turn completed",
        "agent_end": "candidate awaiting judge",
    }.get(event_type)


class RpcBridge:
    def __init__(self, arguments: argparse.Namespace, environment: dict[str, str]) -> None:
        self.arguments = arguments
        self.environment = environment
        self.started_unix = time.time()
        self.started_monotonic = time.monotonic()
        self.sequence = 0
        self.tool_calls = 0
        self.retries = 0
        self.usage = {name: 0.0 for name in ("input", "output", "reasoning", "cacheRead", "cacheWrite", "totalTokens")}
        self.cost: float | None = None
        self.phase = "starting"
        self.last_activity = "candidate starting"
        self.last_activity_at = timestamp()
        self.finish_reason: str | None = None
        self.finish_phase: str | None = None
        self.timed_out = False
        self.signal_number: int | None = None
        self.lock = threading.RLock()
        self.finish = threading.Event()
        self.server: socket.socket | None = None
        self.process: subprocess.Popen[str] | None = None
        self.canonical = (RUNTIME / "candidate.jsonl").open("w", encoding="utf-8")
        self.journal = (RUNTIME / "lifecycle.jsonl").open("w", encoding="utf-8")

    def record(self, source: str, event: dict[str, Any]) -> None:
        with self.lock:
            self.sequence += 1
            record = {"sequence": self.sequence, "timestamp": timestamp(), "elapsed_seconds": round(time.monotonic() - self.started_monotonic, 3), "source": source, "event": event}
            self.journal.write(json.dumps(record, separators=(",", ":")) + "\n")
            self.journal.flush()
            os.fsync(self.journal.fileno())

    def status(self) -> None:
        tokens = {name: int(value) if value.is_integer() else value for name, value in self.usage.items()}
        atomic_json(RUNTIME / "progress.json", {"schema_version": 1, "phase": self.phase, "model": {"provider": self.arguments.provider, "model": self.arguments.model, "thinking": self.arguments.thinking}, "started_at_unix": self.started_unix, "updated_at": timestamp(), "elapsed_seconds": round(time.monotonic() - self.started_monotonic, 1), "timeout_seconds": self.arguments.timeout_seconds, "tool_calls": self.tool_calls, "retries": self.retries, "tokens": tokens, "cost_usd": self.cost, "last_activity": self.last_activity, "last_activity_at": self.last_activity_at, "event_sequence": self.sequence})

    def update(self, event: dict[str, Any]) -> None:
        event_type = event.get("type")
        if event_type == "tool_execution_start":
            self.tool_calls += 1
        elif event_type == "auto_retry_start":
            self.retries += 1
            self.phase = "retrying"
        elif event_type == "auto_retry_end":
            self.phase = "running"
        elif event_type == "turn_end":
            usage = usage_for(event)
            if usage is not None:
                add_usage(self.usage, usage)
                cost = usage.get("cost")
                if isinstance(cost, dict) and isinstance(cost.get("total"), (int, float)) and not isinstance(cost["total"], bool):
                    self.cost = (self.cost or 0) + cost["total"]
        elif event_type == "agent_end":
            self.phase = "awaiting_judge"
        label = activity(event)
        if label:
            self.last_activity = label
            self.last_activity_at = timestamp()
            self.status()

    def send_rpc(self, command: dict[str, Any]) -> None:
        if self.process is None or self.process.stdin is None or self.process.poll() is not None:
            raise RuntimeError("candidate_not_running")
        with self.lock:
            self.process.stdin.write(json.dumps(command, separators=(",", ":")) + "\n")
            self.process.stdin.flush()
        self.record("judge_command", command)

    def read_output(self) -> None:
        assert self.process is not None and self.process.stdout is not None
        for raw in self.process.stdout:
            self.canonical.write(raw)
            self.canonical.flush()
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                self.record("pi_invalid_json", {"line": raw[:1000]})
                continue
            if isinstance(event, dict):
                self.record("pi", event)
                self.update(event)

    def handle_control(self, connection: socket.socket) -> None:
        try:
            payload = b""
            while len(payload) <= 65_536 and not payload.endswith(b"\n"):
                chunk = connection.recv(4096)
                if not chunk:
                    break
                payload += chunk
            command = json.loads(payload)
            if not isinstance(command, dict):
                raise ValueError("invalid_control")
            action = command.get("control")
            if action in {"rpc", "intervention"}:
                rpc = command.get("command")
                if not isinstance(rpc, dict) or rpc.get("type") not in RPC_COMMANDS:
                    raise ValueError("invalid_rpc_command")
                intervention = None
                if action == "intervention":
                    intervention = command.get("intervention")
                    required = {"id", "timestamp", "classification", "mode", "message", "reason"}
                    if not isinstance(intervention, dict) or set(intervention) != required or not all(isinstance(value, str) and value for value in intervention.values()):
                        raise ValueError("invalid_intervention")
                    if rpc.get("id") != intervention["id"] or rpc.get("message") != intervention["message"] or rpc.get("type") != intervention["mode"]:
                        raise ValueError("intervention_rpc_mismatch")
                    self.record("judge_intervention", {**intervention, "delivery": "pending"})
                if rpc["type"] in {"steer", "follow_up"}:
                    self.phase = "running"
                    self.last_activity = f"judge {rpc['type']} queued"
                    self.last_activity_at = timestamp()
                    self.status()
                try:
                    self.send_rpc(rpc)
                except RuntimeError:
                    if intervention is not None:
                        self.record("judge_intervention", {**intervention, "delivery": "failed"})
                    raise
                if intervention is not None:
                    self.record("judge_intervention", {**intervention, "delivery": "delivered"})
            elif action in {"finish", "abort"}:
                reason = command.get("reason")
                if not isinstance(reason, str) or not reason:
                    raise ValueError("invalid_finish_reason")
                self.finish_phase = self.phase
                self.finish_reason = f"judge_{action}:{reason}"
                self.record("judge_control", command)
                self.finish.set()
            else:
                raise ValueError("invalid_control")
            response = {"ok": True, "control": action}
        except (ValueError, json.JSONDecodeError, RuntimeError) as error:
            response = {"ok": False, "reason": str(error)}
        connection.sendall(json.dumps(response, separators=(",", ":")).encode() + b"\n")

    def serve_controls(self) -> None:
        if CONTROL_SOCKET.exists():
            CONTROL_SOCKET.unlink()
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server = server
        server.bind(str(CONTROL_SOCKET))
        CONTROL_SOCKET.chmod(0o600)
        server.listen()
        server.settimeout(0.5)
        while not self.finish.is_set():
            try:
                connection, _ = server.accept()
            except TimeoutError:
                continue
            with connection:
                self.handle_control(connection)

    def stop(self, signal_number: int, _frame: object) -> None:
        self.signal_number = signal_number
        self.finish_reason = "external_signal"
        self.finish.set()

    def run(self) -> int:
        command = ["pi", "--provider", self.arguments.provider, "--model", self.arguments.model, "--thinking", self.arguments.thinking, "--mode", "rpc", "--session", str(RUNTIME / "sessions" / "candidate.jsonl"), "--name", self.arguments.run_id]
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
        with (RUNTIME / "candidate.stderr").open("w", encoding="utf-8") as error:
            self.process = subprocess.Popen(command, cwd="/workspace", env=self.environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=error, text=True, bufsize=1, start_new_session=True)
            self.phase = "running"
            self.status()
            reader = threading.Thread(target=self.read_output, daemon=True)
            reader.start()
            threading.Thread(target=self.serve_controls, daemon=True).start()
            self.send_rpc({"id": "initial-prompt", "type": "prompt", "message": self.arguments.prompt})
            deadline = self.started_monotonic + self.arguments.timeout_seconds
            while not self.finish.wait(0.2):
                if self.process.poll() is not None:
                    self.finish_reason = "pi_process_exit"
                    break
                if time.monotonic() >= deadline:
                    self.timed_out = True
                    self.finish_reason = "timeout"
                    break
            if self.process.poll() is None:
                if self.timed_out or self.finish_reason == "external_signal" or str(self.finish_reason).startswith("judge_abort"):
                    try:
                        self.send_rpc({"id": "supervisor-abort", "type": "abort"})
                    except RuntimeError:
                        pass
                os.killpg(self.process.pid, signal.SIGTERM)
                try:
                    self.process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait()
            actual_exit = self.process.returncode
            reader.join()
        if self.finish_reason and self.finish_reason.startswith("judge_finish"):
            exit_code = 0
        elif self.timed_out:
            exit_code = 124
        elif self.signal_number is not None:
            exit_code = 128 + self.signal_number
        elif self.finish_reason and self.finish_reason.startswith("judge_abort"):
            exit_code = 130
        else:
            exit_code = actual_exit
        self.phase = "completed"
        self.last_activity = self.finish_reason or "candidate completed"
        self.last_activity_at = timestamp()
        self.status()
        completion = {"exit_code": exit_code, "pi_exit_code": actual_exit, "timed_out": self.timed_out, "reason": self.finish_reason, "judge_finish_phase": self.finish_phase, "signal": self.signal_number, "started_at_unix": self.started_unix, "finished_at_unix": time.time()}
        self.record("supervisor", {"type": "completion", **completion})
        completion["terminal_event_sequence"] = self.sequence
        atomic_json(RUNTIME / "candidate-completion.json", completion)
        return exit_code

    def close(self) -> None:
        self.finish.set()
        if self.server is not None:
            self.server.close()
        if CONTROL_SOCKET.exists():
            CONTROL_SOCKET.unlink()
        self.canonical.close()
        self.journal.close()


def send_control() -> int:
    try:
        payload = sys.stdin.buffer.read(65_537)
        if len(payload) > 65_536:
            raise ValueError("control_too_large")
        json.loads(payload)
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(5)
        client.connect(str(CONTROL_SOCKET))
        client.sendall(payload.rstrip(b"\n") + b"\n")
        response = b""
        while not response.endswith(b"\n"):
            chunk = client.recv(4096)
            if not chunk:
                break
            response += chunk
        sys.stdout.buffer.write(response)
        result = json.loads(response)
        return 0 if result.get("ok") else 4
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "reason": str(error)}, separators=(",", ":")), file=sys.stderr)
        return 4


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--thinking", required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--timeout-seconds", required=True, type=float)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--detach", action="store_true")
    parser.add_argument("--probe", action="store_true")
    return parser.parse_args()


def stage_payload(arguments: argparse.Namespace) -> tuple[Path, dict[str, str]]:
    payload = json.load(sys.stdin)
    pi_config = payload.get("pi_config") if isinstance(payload, dict) else None
    if not isinstance(pi_config, dict) or set(pi_config) != {"auth", "models", "settings"} or not all(isinstance(value, str) for value in pi_config.values()):
        raise SystemExit(2)
    try:
        provider_env = provider_environment(arguments.provider, payload.get("provider_env"))
    except ValueError:
        raise SystemExit(2) from None
    config_dir = RUNTIME / "pi-config"
    config_dir.mkdir(mode=0o700, exist_ok=True)
    config_dir.chmod(0o700)
    for name in ("npm", "git"):
        shutil.copytree(Path("/opt/pi-packages") / name, config_dir / name, symlinks=True)
    for name, content in pi_config.items():
        path = config_dir / f"{name}.json"
        path.write_text(content)
        path.chmod(0o600)
    return config_dir, provider_env


def run_probe(arguments: argparse.Namespace, config_dir: Path, provider_env: dict[str, str]) -> int:
    admission = RUNTIME / "admission"
    admission.mkdir(exist_ok=True)
    started = time.monotonic()
    environment = os.environ.copy()
    environment.update(provider_env)
    environment["PI_CODING_AGENT_DIR"] = str(config_dir)
    command = ["pi", "--provider", arguments.provider, "--model", arguments.model, "--thinking", arguments.thinking, "--mode", "json", "--print", "Reply exactly READY"]
    try:
        completed = subprocess.run(command, cwd="/workspace", env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=arguments.timeout_seconds)
        (admission / "probe.jsonl").write_text(completed.stdout)
        (admission / "probe.stderr").write_text(completed.stderr[-16_000:])
        events = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
        final = next((event.get("message", {}) for event in reversed(events) if event.get("type") == "message_end"), {})
        text = "\n".join(item.get("text", "") for item in final.get("content", []) if isinstance(item, dict) and item.get("type") == "text")
        usage = final.get("usage") if isinstance(final.get("usage"), dict) else next((event.get("usage") for event in reversed(events) if isinstance(event.get("usage"), dict)), {})
        stop_reason = final.get("stopReason", final.get("stop_reason"))
        total_tokens = usage.get("totalTokens", usage.get("total_tokens")) if isinstance(usage, dict) else None
        # pi's own assistant message carries the provider/model that actually
        # served the response (confirmed against a real captured transcript:
        # every message_end/turn_end for role=assistant includes "api",
        # "provider", "model" alongside content/usage) — this is genuine,
        # discoverable evidence of what was served, not something the caller
        # chooses. It is the only part of the requested identity pi's stream
        # confirms: "thinking" is a request-time parameter with no analogous
        # server-echoed confirmation anywhere in the event stream.
        served_provider, served_model = final.get("provider"), final.get("model")
        served = {"provider": served_provider, "model": served_model} if isinstance(served_provider, str) and isinstance(served_model, str) else None
        result = {"ok": completed.returncode == 0 and text == "READY" and stop_reason in {"stop", "end_turn", "completed"} and isinstance(total_tokens, (int, float)) and total_tokens > 0 and served is not None, "exit_code": completed.returncode, "elapsed_ms": round((time.monotonic() - started) * 1000), "text": text, "stop_reason": stop_reason, "usage": usage, "served_model": served}
    except (subprocess.TimeoutExpired, json.JSONDecodeError):
        result = {"ok": False, "elapsed_ms": round((time.monotonic() - started) * 1000)}
    atomic_json(admission / "result.json", result)
    return 0 if result["ok"] else 4


def main() -> int:
    if "--control" in sys.argv:
        return send_control()
    arguments = parse_arguments()
    if arguments.detach or arguments.probe:
        config_dir, provider_env = stage_payload(arguments)
        if arguments.probe:
            try:
                return run_probe(arguments, config_dir, provider_env)
            finally:
                shutil.rmtree(config_dir, ignore_errors=True)
        worker_arguments = [argument for argument in sys.argv[1:] if argument != "--detach"]
        environment = os.environ.copy()
        environment.update(provider_env)
        environment["PI_CODING_AGENT_DIR"] = str(config_dir)
        with (RUNTIME / "candidate-launcher.log").open("w") as launcher_log:
            subprocess.Popen([sys.executable, __file__, *worker_arguments], stdin=subprocess.DEVNULL, stdout=launcher_log, stderr=subprocess.STDOUT, env=environment, start_new_session=True)
        return 0
    bridge = RpcBridge(arguments, os.environ.copy())
    try:
        return bridge.run()
    finally:
        bridge.close()
        shutil.rmtree(os.environ.get("PI_CODING_AGENT_DIR", ""), ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())