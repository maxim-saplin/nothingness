from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any


TASKS = {
    "t2-settings-placement-linux",
    "t3-settings-placement-color-scheme-linux",
}
SHA256 = re.compile(r"[0-9a-f]{64}")


def result(task: str, classification: str, checks: dict[str, bool]) -> dict[str, object]:
    return {
        "schema_version": 1,
        "oracle": "settings-contract",
        "task": task,
        "classification": classification,
        "checks": checks,
        "passed": classification == "pass",
    }


def valid_entries(value: object) -> bool:
    return isinstance(value, list) and all(
        isinstance(entry, dict)
        and isinstance(entry.get("kind"), str)
        and isinstance(entry.get("label"), str)
        and isinstance(entry.get("value"), str)
        for entry in value
    )


def evaluate(task: str, evidence: object) -> dict[str, object]:
    if task not in TASKS:
        return result(task, "malformed_evidence", {"known_task": False})
    required = ("semantic_entries", "action", "post_semantic_entries", "screenshot")
    if not isinstance(evidence, dict) or any(name not in evidence for name in required):
        return result(task, "missing_evidence", {name: isinstance(evidence, dict) and name in evidence for name in required})
    entries = evidence["semantic_entries"]
    action = evidence["action"]
    post_entries = evidence["post_semantic_entries"]
    screenshot = evidence["screenshot"]
    if evidence.get("schema_version") != 1 or not valid_entries(entries) or not valid_entries(post_entries) or not isinstance(action, dict) or not isinstance(screenshot, dict):
        return result(task, "malformed_evidence", {"schema": False})
    screenshot_valid = isinstance(screenshot.get("path"), str) and bool(screenshot["path"]) and isinstance(screenshot.get("sha256"), str) and SHA256.fullmatch(screenshot["sha256"]) is not None
    if not screenshot_valid:
        return result(task, "malformed_evidence", {"screenshot": False})
    screen_positions = [index for index, entry in enumerate(entries) if entry["kind"] == "screen" and entry["value"] == "cassette"]
    if len(screen_positions) != 1:
        return result(task, "semantic_failure", {"cassette_screen": False, "screenshot": True})
    screen_index = screen_positions[0]
    variant_positions = [index for index, entry in enumerate(entries) if entry["kind"] == "cassette_variant"]
    contiguous = bool(variant_positions) and variant_positions == list(range(screen_index + 1, screen_index + 1 + len(variant_positions)))
    checks = {"cassette_screen": True, "cassette_variants_contiguous": contiguous, "screenshot": True}
    if not contiguous:
        return result(task, "semantic_failure", checks)
    post_screen_positions = [index for index, entry in enumerate(post_entries) if entry["kind"] == "screen" and entry["value"] == "cassette"]
    post_variant_positions = [index for index, entry in enumerate(post_entries) if entry["kind"] == "cassette_variant"]
    post_variants = [entry for entry in post_entries if entry["kind"] == "cassette_variant"]
    action_valid = action == {"type": "tap_by_key", "key": "void-settings-cassette-variant", "succeeded": True}
    checks["post_cassette_variants_contiguous"] = len(post_screen_positions) == 1 and bool(post_variant_positions) and post_variant_positions == list(range(post_screen_positions[0] + 1, post_screen_positions[0] + 1 + len(post_variant_positions)))
    checks["selector_action_succeeded"] = action_valid
    checks["selector_value_changed"] = len(post_variants) == len(variant_positions) and [entry["value"] for entry in post_variants] != [entries[index]["value"] for index in variant_positions]
    if not checks["post_cassette_variants_contiguous"] or not action_valid or not checks["selector_value_changed"]:
        return result(task, "semantic_failure", checks)
    if task == "t3-settings-placement-color-scheme-linux":
        labels = [entries[index]["label"] for index in variant_positions]
        post_labels = [entry["label"] for entry in post_variants]
        checks["single_cassette_selector"] = len(labels) == 1
        checks["color_scheme_present"] = labels == ["color scheme"] and post_labels == labels
        checks["old_variant_label_absent"] = "variant" not in labels and "variant" not in post_labels
        if not all(checks.values()):
            return result(task, "semantic_failure", checks)
    return result(task, "pass", checks)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", required=True)
    arguments = parser.parse_args()
    try:
        evidence: Any = json.load(sys.stdin)
    except json.JSONDecodeError:
        output = result(arguments.task, "malformed_evidence", {"json": False})
    else:
        output = evaluate(arguments.task, evidence)
    print(json.dumps(output, separators=(",", ":")))


if __name__ == "__main__":
    main()