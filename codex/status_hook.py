"""Translate Codex hook input and deliver it to its Neovim terminal owner."""

import base64
import json
import os
import subprocess
import sys
import time

SCHEMA_VERSION = 1
MAX_INPUT_BYTES = 1024 * 1024

EVENT_STATES = {
    "UserPromptSubmit": "working",
    "PermissionRequest": "waiting",
    "PostToolUse": "working",
    "Stop": "finished",
    "Interrupt": "idle",
}

ENV_MARKER = "NVIM_CODEX_STATUS_BRIDGE"
ENV_SERVER = "NVIM_CODEX_SERVER"
ENV_BUFFER = "NVIM_CODEX_BUFFER"
ENV_INSTANCE = "NVIM_CODEX_INSTANCE"
ENV_CLIENT = "NVIM_CODEX_CLIENT"

REMOTE_LUA = (
    "require('features.codex_status').receive(vim.json.decode(vim.base64.decode(_A)))"
)


def parse_hook_json(raw):
    """Return a hook object, or ``None`` for malformed/oversized input."""
    if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_INPUT_BYTES:
        return None

    try:
        value = json.loads(raw)
    except (TypeError, ValueError):
        return None

    return value if isinstance(value, dict) else None


def translate_hook(payload, now_ns=None):
    """Translate one supported hook payload into a versioned status envelope."""
    if not isinstance(payload, dict):
        return None

    source_event = payload.get("hook_event_name")
    state = EVENT_STATES.get(source_event)
    if state is None:
        return None

    if now_ns is None:
        now_ns = time.monotonic_ns()
    if not isinstance(now_ns, int) or now_ns < 0:
        return None

    envelope = {
        "schema_version": SCHEMA_VERSION,
        "state": state,
        "source_event": source_event,
        "monotonic_ns": now_ns,
    }

    for field in ("session_id", "turn_id"):
        value = payload.get(field)
        if isinstance(value, str) and value:
            envelope[field] = value

    return envelope


def bridge_target(environ=None):
    """Return validated RPC metadata only for a Neovim-launched Codex."""
    environ = os.environ if environ is None else environ
    if environ.get(ENV_MARKER) != "1":
        return None

    server = environ.get(ENV_SERVER)
    buffer_text = environ.get(ENV_BUFFER, "")
    instance = environ.get(ENV_INSTANCE)
    client = environ.get(ENV_CLIENT)
    if not isinstance(server, str) or not server or len(server) > 4096:
        return None
    if not isinstance(buffer_text, str) or not buffer_text.isascii():
        return None
    if not buffer_text.isdigit() or int(buffer_text) <= 0:
        return None
    if not isinstance(instance, str) or not 0 < len(instance) <= 256:
        return None
    if "\x00" in instance:
        return None
    if not isinstance(client, str) or not os.path.isabs(client):
        return None
    if "\x00" in client or not os.path.isfile(client):
        return None
    if not os.access(client, os.X_OK):
        return None

    return {
        "server": server,
        "buffer": int(buffer_text),
        "instance": instance,
        "client": client,
    }


def prepare_dispatch(payload, environ=None, now_ns=None):
    """Return ``(target, envelope)`` when this event belongs to Neovim."""
    target = bridge_target(environ)
    envelope = translate_hook(payload, now_ns=now_ns)
    if target is None or envelope is None:
        return None

    return target, envelope


def build_client_argv(target, envelope):
    """Build an argv-only RPC client call with a base64-encoded JSON argument."""
    if not isinstance(target, dict) or not isinstance(envelope, dict):
        return None

    client = target.get("client")
    server = target.get("server")
    buffer_number = target.get("buffer")
    instance = target.get("instance")
    if not isinstance(client, str) or not client:
        return None
    if not isinstance(server, str) or not server:
        return None
    if not isinstance(buffer_number, int) or buffer_number <= 0:
        return None
    if not isinstance(instance, str) or not instance:
        return None

    message = dict(envelope)
    message["buffer"] = buffer_number
    message["instance"] = instance

    try:
        serialized = json.dumps(
            message,
            allow_nan=False,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    except (TypeError, ValueError):
        return None

    encoded = base64.b64encode(serialized).decode("ascii")
    expression = f"luaeval(\"{REMOTE_LUA}\", '{encoded}')"
    return [
        client,
        "--server",
        server,
        "--remote-expr",
        expression,
    ]


def send_to_neovim(target, envelope):
    """Deliver one event, returning false without raising on any RPC failure."""
    argv = build_client_argv(target, envelope)
    if not argv or not all(isinstance(item, str) and item for item in argv):
        return False

    try:
        completed = subprocess.run(
            argv,
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=1,
        )
    except (OSError, subprocess.SubprocessError):
        return False

    return completed.returncode == 0


def main():
    payload = None
    try:
        payload = parse_hook_json(sys.stdin.read(MAX_INPUT_BYTES + 1))
        if payload is not None:
            prepared = prepare_dispatch(payload)
            if prepared is not None:
                send_to_neovim(*prepared)
    except Exception:  # noqa: BLE001 -- status reporting must fail open.
        return

    # Stop requires JSON on stdout. An empty object has no behavioral effect.
    if isinstance(payload, dict) and payload.get("hook_event_name") == "Stop":
        try:
            sys.stdout.write("{}\n")
            sys.stdout.flush()
        except (OSError, ValueError):
            return


if __name__ == "__main__":
    main()
