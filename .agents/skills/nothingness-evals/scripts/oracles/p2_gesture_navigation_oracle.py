from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any


TASKS = {"t4-swipe-to-seek-linux", "t5-jump-to-now-playing-linux"}
SHA256 = re.compile(r"[0-9a-f]{64}")


def output(task: str, classification: str, checks: dict[str, bool]) -> dict[str, object]:
    return {"schema_version": 1, "oracle": "p2-gesture-navigation", "task": task, "classification": classification, "checks": checks, "passed": classification == "pass"}


def screenshot(value: object) -> bool:
    return isinstance(value, dict) and isinstance(value.get("path"), str) and bool(value["path"]) and isinstance(value.get("sha256"), str) and SHA256.fullmatch(value["sha256"]) is not None


def integer(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def t4(evidence: dict[str, object]) -> dict[str, object]:
    required = ("pre", "action", "during", "post")
    if any(key not in evidence for key in required):
        return output("t4-swipe-to-seek-linux", "missing_evidence", {key: key in evidence for key in required})
    pre, action, during, post = (evidence[key] for key in required)
    if not all(isinstance(value, dict) for value in (pre, action, during, post)):
        return output("t4-swipe-to-seek-linux", "malformed_evidence", {"objects": False})
    duration, start, target, end = pre.get("duration_ms"), pre.get("position_ms"), during.get("target_ms"), post.get("position_ms")
    pre_path, post_path = pre.get("track_path"), post.get("track_path")
    folder = during.get("folder_line")
    fraction = folder.get("progress_fraction") if isinstance(folder, dict) else None
    checks = {
        "seekable_pre_state": isinstance(pre_path, str) and bool(pre_path) and integer(duration) and integer(start) and duration > 0 and 0 <= start <= duration,
        "standardized_drag": action == {"type": "horizontal_drag", "dx": 240, "steps": 12, "succeeded": True},
        "during_folder_line": isinstance(folder, dict) and folder.get("visible") is True and isinstance(folder.get("position_text"), str) and bool(folder["position_text"]) and isinstance(folder.get("duration_text"), str) and bool(folder["duration_text"]) and isinstance(fraction, (int, float)) and 0 <= fraction <= 1,
        "preview_target_changed": integer(target) and integer(start) and integer(duration) and 0 <= target <= duration and abs(target - start) >= 1000,
        "preview_fraction_matches_target": integer(target) and integer(duration) and isinstance(fraction, (int, float)) and abs(fraction - target / duration) <= 0.01,
        "center_indicator_absent": during.get("center_seek_indicator") is False,
        "during_screenshot": screenshot(during.get("screenshot")),
        "same_track_post_seek": isinstance(post_path, str) and post_path == pre_path,
        "runtime_seek_reached_target": integer(end) and integer(target) and abs(end - target) <= 3000,
        "clamped_post_position": integer(end) and integer(duration) and 0 <= end <= duration,
        "post_transient_cleared": post.get("folder_line_preview") is False and post.get("center_seek_indicator") is False,
        "post_screenshot": screenshot(post.get("screenshot")),
    }
    return output("t4-swipe-to-seek-linux", "pass" if all(checks.values()) else "semantic_failure", checks)


def t5(evidence: dict[str, object]) -> dict[str, object]:
    required = ("pre", "action", "post", "no_playing")
    if any(key not in evidence for key in required):
        return output("t5-jump-to-now-playing-linux", "missing_evidence", {key: key in evidence for key in required})
    pre, action, post, no_playing = (evidence[key] for key in required)
    if not all(isinstance(value, dict) for value in (pre, action, post, no_playing)):
        return output("t5-jump-to-now-playing-linux", "malformed_evidence", {"objects": False})
    playing_path, parent, before_path, after_path = pre.get("playing_path"), pre.get("playing_parent"), pre.get("browser_path"), post.get("browser_path")
    row, bounds = post.get("current_row"), post.get("scroll_bounds")
    checks = {
        "same_folder_offscreen_pre_state": isinstance(playing_path, str) and bool(playing_path) and isinstance(parent, str) and bool(parent) and before_path == parent and pre.get("current_row_visible") is False and isinstance(pre.get("scroll_offset"), (int, float)),
        "affordance_discoverable": pre.get("affordance") == {"label": "jump to now playing", "enabled": True},
        "activation_succeeded": action == {"type": "semantic_activate", "label": "jump to now playing", "succeeded": True},
        "browser_location_preserved": isinstance(after_path, str) and after_path == before_path == parent and post.get("playing_parent") == parent,
        "scroll_state_changed": isinstance(pre.get("scroll_offset"), (int, float)) and isinstance(post.get("scroll_offset"), (int, float)) and pre["scroll_offset"] != post["scroll_offset"],
        "correct_row_visible": isinstance(row, dict) and row.get("path") == playing_path and row.get("visible") is True and (row.get("focused") is True or row.get("located") is True),
        "row_within_scroll_bounds": isinstance(row, dict) and isinstance(bounds, dict) and all(isinstance(row.get(key), (int, float)) for key in ("top", "bottom")) and all(isinstance(bounds.get(key), (int, float)) for key in ("top", "bottom")) and bounds["top"] <= row["top"] <= row["bottom"] <= bounds["bottom"],
        "post_screenshots": screenshot(pre.get("screenshot")) and screenshot(post.get("screenshot")),
        "no_playing_affordance_inactive": no_playing.get("playing_path") in (None, "") and no_playing.get("affordance") in ({"present": False}, {"present": True, "enabled": False}),
    }
    return output("t5-jump-to-now-playing-linux", "pass" if all(checks.values()) else "semantic_failure", checks)


def evaluate(task: str, evidence: object) -> dict[str, object]:
    if task not in TASKS:
        return output(task, "malformed_evidence", {"known_task": False})
    if not isinstance(evidence, dict) or evidence.get("schema_version") != 1:
        return output(task, "malformed_evidence", {"schema": False})
    return t4(evidence) if task.startswith("t4-") else t5(evidence)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", required=True)
    arguments = parser.parse_args()
    try:
        evidence: Any = json.load(sys.stdin)
    except json.JSONDecodeError:
        print(json.dumps(output(arguments.task, "malformed_evidence", {"json": False}), separators=(",", ":")))
        return
    print(json.dumps(evaluate(arguments.task, evidence), separators=(",", ":")))


if __name__ == "__main__":
    main()