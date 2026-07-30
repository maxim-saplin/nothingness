from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any


T6 = "t6-dot-song-info-hardening-linux"
T7 = "t7-opus-shuffled-playlist-linux"
TASKS = {T6, T7}
SHA256 = re.compile(r"[0-9a-f]{64}")
LONG_ARTIST = "A very long artist name that wraps across two lines"
LONG_TITLE = "A very long song title that also wraps across two lines"
OPUS = {
    "/opt/nothingness/media/01-undercover-49.opus": "1752703ac8d43aeaf6025828a5bf19e4974abe997fea07301f8a9036f8003cad",
    "/opt/nothingness/media/02-undercover-50.opus": "9e574ca04a6290746df1037834a499ea7f0d8904178fbcc8f0a572baca72f1a3",
    "/opt/nothingness/media/03-undercover-51.opus": "5a3d42563f228a1307b8458a5d24c4e47b6e8c7eb0818f48e2bc79dfc97e36d8",
    "/opt/nothingness/media/04-undercover-52.opus": "5adb06cd41c765111bbdfdb316edfe5c7c1cee8f91e288e8d0c74d7913864200",
    "/opt/nothingness/media/05-undercover-53.opus": "7f0968a9e372249b2711fedc5f2be5b7f5b7af880355d4f24562552a8b3b1132",
    "/opt/nothingness/media/06-undercover-54.opus": "ce752edc5744e1d3ed3072e97e21a4325b5ce2b30cf1157ab34d1e10a0f1150a",
    "/opt/nothingness/media/07-undercover-44.opus": "18246d6d137e96c8c04c9bd0e9ac71035a22a6f8af72287cc266189d175e773f",
    "/opt/nothingness/media/08-undercover-45.opus": "934d519a49ae2b8c58478108d9be6219a14926db546c639611ba99985c5b07c9",
    "/opt/nothingness/media/09-undercover-46.opus": "0c15459fc15a476630c937cbaddeb71fac289d070e4915f04bfa6c19e58eaf7d",
    "/opt/nothingness/media/10-undercover-47.opus": "ed75b7c682cb145b3d6bddbe70a8c5d1c9484b61205f0d41a0e6bccde459940c",
}


def output(task: str, classification: str, checks: dict[str, bool]) -> dict[str, object]:
    return {
        "schema_version": 1,
        "oracle": "p3-dot-opus",
        "task": task,
        "classification": classification,
        "checks": checks,
        "passed": classification == "pass",
    }


def rect(value: object) -> bool:
    return (
        isinstance(value, dict)
        and all(isinstance(value.get(key), (int, float)) for key in ("left", "top", "right", "bottom"))
        and value["left"] <= value["right"]
        and value["top"] <= value["bottom"]
    )


def inside(inner: object, outer: object) -> bool:
    return (
        rect(inner)
        and rect(outer)
        and outer["left"] <= inner["left"] <= inner["right"] <= outer["right"]
        and outer["top"] <= inner["top"] <= inner["bottom"] <= outer["bottom"]
    )


def overlaps(first: object, second: object) -> bool:
    return (
        rect(first)
        and rect(second)
        and first["left"] < second["right"]
        and second["left"] < first["right"]
        and first["top"] < second["bottom"]
        and second["top"] < first["bottom"]
    )


def screenshot(value: object) -> bool:
    return (
        isinstance(value, dict)
        and isinstance(value.get("path"), str)
        and bool(value["path"])
        and isinstance(value.get("sha256"), str)
        and SHA256.fullmatch(value["sha256"]) is not None
        and value.get("nonblank") is True
    )


def evaluate_t6(evidence: dict[str, object]) -> dict[str, object]:
    required = ("scenario", "fresh", "enabled", "restarted", "disabled", "scales")
    if any(key not in evidence for key in required):
        return output(T6, "missing_evidence", {key: key in evidence for key in required})
    scenario = evidence["scenario"]
    fresh = evidence["fresh"]
    enabled = evidence["enabled"]
    restarted = evidence["restarted"]
    disabled = evidence["disabled"]
    scales = evidence["scales"]
    if not all(isinstance(value, dict) for value in (scenario, fresh, enabled, restarted, disabled)) or not isinstance(scales, list):
        return output(T6, "malformed_evidence", {"objects": False})

    enabled_instance = enabled.get("app_instance")
    restarted_instance = restarted.get("app_instance")
    checks = {
        "frozen_stress_scenario": scenario == {
            "artist": LONG_ARTIST,
            "title": LONG_TITLE,
            "max_dot_size": 120,
            "spectrum_peak": 1.0,
        },
        "fresh_default_off": fresh.get("show_song_info") is False and fresh.get("has_song_info") is False,
        "enabled_conditional_info": enabled.get("show_song_info") is True and enabled.get("has_song_info") is True,
        "restart_persisted": (
            isinstance(enabled_instance, str)
            and bool(enabled_instance)
            and isinstance(restarted_instance, str)
            and bool(restarted_instance)
            and restarted_instance != enabled_instance
            and restarted.get("show_song_info") is True
            and restarted.get("has_song_info") is True
        ),
        "disabled_removes_info": disabled.get("show_song_info") is False and disabled.get("has_song_info") is False,
        "exact_scales": len(scales) == 2 and {item.get("scale") for item in scales if isinstance(item, dict)} == {1.0, 1.5},
    }
    geometry: list[bool] = []
    for item in scales:
        if not isinstance(item, dict):
            geometry.append(False)
            continue
        hero = item.get("hero_bounds")
        dot = item.get("dot_bounds")
        artist = item.get("artist_bounds")
        title = item.get("title_bounds")
        geometry.append(
            item.get("scale") in (1.0, 1.5)
            and inside(dot, hero)
            and inside(artist, hero)
            and inside(title, hero)
            and not overlaps(artist, dot)
            and not overlaps(title, dot)
            and item.get("overflow_errors") == []
            and screenshot(item.get("screenshot"))
        )
    checks["geometry_clear_at_both_scales"] = len(geometry) == 2 and all(geometry)
    classification = "pass" if all(checks.values()) else "semantic_failure"
    return output(T6, classification, checks)


def evaluate_t7(evidence: dict[str, object]) -> dict[str, object]:
    required = ("inventory", "queue", "pre", "action", "post")
    if any(key not in evidence for key in required):
        return output(T7, "missing_evidence", {key: key in evidence for key in required})
    inventory = evidence["inventory"]
    queue = evidence["queue"]
    pre = evidence["pre"]
    action = evidence["action"]
    post = evidence["post"]
    if not isinstance(inventory, list) or not isinstance(queue, list) or not all(isinstance(value, dict) for value in (pre, action, post)):
        return output(T7, "malformed_evidence", {"objects": False})

    observed_inventory = [
        (item.get("path"), item.get("sha256"))
        for item in inventory
        if isinstance(item, dict)
        and item.get("codec") == "opus"
        and item.get("full_decode") is True
    ]
    queue_paths = [item.get("path") for item in queue if isinstance(item, dict)]
    queue_found = all(
        isinstance(item, dict)
        and item.get("is_not_found") is False
        and item.get("path") in OPUS
        for item in queue
    )
    pre_path = pre.get("current_path")
    post_path = post.get("current_path")
    pre_index = pre.get("current_index")
    post_index = post.get("current_index")
    checks = {
        "inventory_exact": len(observed_inventory) == 10 and set(observed_inventory) == set(OPUS.items()),
        "inventory_multiplicity_one": len(set(observed_inventory)) == len(observed_inventory) == 10,
        "queue_exact_once": len(queue_paths) == 10 and set(queue_paths) == set(OPUS) and len(set(queue_paths)) == 10,
        "all_queue_entries_found": queue_found and len(queue) == 10,
        "shuffle_enabled": pre.get("shuffle") is True and post.get("shuffle") is True,
        "valid_media_playing": pre.get("is_playing") is True and pre_path in OPUS,
        "next_succeeded": action == {"type": "next", "succeeded": True},
        "navigation_transition": (
            isinstance(pre_index, int)
            and not isinstance(pre_index, bool)
            and isinstance(post_index, int)
            and not isinstance(post_index, bool)
            and 0 <= pre_index < 10
            and 0 <= post_index < 10
            and post_index != pre_index
        ),
        "post_media_playing": post.get("is_playing") is True and post_path in OPUS,
        "state_matches_queue": (
            isinstance(pre_index, int)
            and not isinstance(pre_index, bool)
            and isinstance(post_index, int)
            and not isinstance(post_index, bool)
            and 0 <= pre_index < len(queue_paths)
            and 0 <= post_index < len(queue_paths)
            and queue_paths[pre_index] == pre_path
            and queue_paths[post_index] == post_path
        ),
    }
    classification = "pass" if all(checks.values()) else "semantic_failure"
    return output(T7, classification, checks)


def evaluate(task: str, evidence: object) -> dict[str, object]:
    if task not in TASKS:
        return output(task, "malformed_evidence", {"known_task": False})
    if not isinstance(evidence, dict) or evidence.get("schema_version") != 1:
        return output(task, "malformed_evidence", {"schema": False})
    return evaluate_t6(evidence) if task == T6 else evaluate_t7(evidence)


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