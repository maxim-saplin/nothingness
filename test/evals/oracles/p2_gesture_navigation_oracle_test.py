from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ORACLE = ROOT / ".agents/skills/nothingness-evals/scripts/oracles/p2_gesture_navigation_oracle.py"
SPEC = importlib.util.spec_from_file_location("p2_oracle", ORACLE)
assert SPEC is not None and SPEC.loader is not None
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


SHOT = {"path": "evidence/shot.png", "sha256": "a" * 64}


def t4() -> dict[str, object]:
    return {"schema_version": 1, "pre": {"track_path": "/music/track.opus", "position_ms": 1000, "duration_ms": 10000}, "action": {"type": "horizontal_drag", "dx": 240, "steps": 12, "succeeded": True}, "during": {"target_ms": 7000, "folder_line": {"visible": True, "position_text": "0:07", "duration_text": "0:10", "progress_fraction": .7}, "center_seek_indicator": False, "screenshot": SHOT}, "post": {"track_path": "/music/track.opus", "position_ms": 7000, "folder_line_preview": False, "center_seek_indicator": False, "screenshot": SHOT}}


def t5() -> dict[str, object]:
    return {"schema_version": 1, "pre": {"playing_path": "/music/end.opus", "playing_parent": "/music", "browser_path": "/music", "current_row_visible": False, "scroll_offset": 0, "affordance": {"label": "jump to now playing", "enabled": True}, "screenshot": SHOT}, "action": {"type": "semantic_activate", "label": "jump to now playing", "succeeded": True}, "post": {"playing_parent": "/music", "browser_path": "/music", "scroll_offset": 480, "current_row": {"path": "/music/end.opus", "visible": True, "located": True, "top": 680, "bottom": 720}, "scroll_bounds": {"top": 100, "bottom": 720}, "screenshot": SHOT}, "no_playing": {"playing_path": None, "affordance": {"present": False}}}


class P2GestureNavigationOracleTest(unittest.TestCase):
    def test_t4_accepts_progress_and_cleared_transient(self) -> None:
        self.assertTrue(oracle.evaluate("t4-swipe-to-seek-linux", t4())["passed"])

    def test_t4_rejects_no_seek_movement(self) -> None:
        value = t4(); value["during"]["target_ms"] = 1000; value["during"]["folder_line"]["progress_fraction"] = .1; value["post"]["position_ms"] = 1000
        self.assertFalse(oracle.evaluate("t4-swipe-to-seek-linux", value)["checks"]["preview_target_changed"])

    def test_t4_rejects_playback_drift_or_track_change(self) -> None:
        value = t4(); value["post"]["position_ms"] = 3000
        self.assertFalse(oracle.evaluate("t4-swipe-to-seek-linux", value)["checks"]["runtime_seek_reached_target"])
        value = t4(); value["post"]["track_path"] = "/music/next.opus"
        self.assertFalse(oracle.evaluate("t4-swipe-to-seek-linux", value)["checks"]["same_track_post_seek"])

    def test_t4_rejects_preview_fraction_unrelated_to_target(self) -> None:
        value = t4(); value["during"]["folder_line"]["progress_fraction"] = .2
        self.assertFalse(oracle.evaluate("t4-swipe-to-seek-linux", value)["checks"]["preview_fraction_matches_target"])

    def test_t4_rejects_missing_during_or_center_indicator(self) -> None:
        value = t4(); del value["during"]["folder_line"]
        result = oracle.evaluate("t4-swipe-to-seek-linux", value)
        self.assertFalse(result["checks"]["during_folder_line"])
        value = t4(); value["during"]["center_seek_indicator"] = True
        self.assertFalse(oracle.evaluate("t4-swipe-to-seek-linux", value)["checks"]["center_indicator_absent"])

    def test_t4_rejects_stale_or_unclamped_post_state(self) -> None:
        value = t4(); value["post"].update({"position_ms": 10001, "folder_line_preview": True})
        result = oracle.evaluate("t4-swipe-to-seek-linux", value)
        self.assertFalse(result["checks"]["clamped_post_position"])
        self.assertFalse(result["checks"]["post_transient_cleared"])

    def test_t5_accepts_end_of_list_row_in_bounds(self) -> None:
        self.assertTrue(oracle.evaluate("t5-jump-to-now-playing-linux", t5())["passed"])

    def test_t5_rejects_missing_affordance_or_noop(self) -> None:
        value = t5(); value["pre"]["affordance"] = {"label": "jump to now-playing folder", "enabled": False}
        self.assertFalse(oracle.evaluate("t5-jump-to-now-playing-linux", value)["checks"]["affordance_discoverable"])
        value = t5(); value["action"]["succeeded"] = False
        self.assertFalse(oracle.evaluate("t5-jump-to-now-playing-linux", value)["checks"]["activation_succeeded"])

        value = t5(); value["post"]["scroll_offset"] = value["pre"]["scroll_offset"]
        self.assertFalse(oracle.evaluate("t5-jump-to-now-playing-linux", value)["checks"]["scroll_state_changed"])

    def test_t5_rejects_folder_change(self) -> None:
        value = t5(); value["post"]["browser_path"] = "/other"
        self.assertFalse(oracle.evaluate("t5-jump-to-now-playing-linux", value)["checks"]["browser_location_preserved"])

    def test_t5_rejects_wrong_or_outside_row(self) -> None:
        value = t5(); value["post"]["current_row"]["path"] = "/music/wrong.opus"
        self.assertFalse(oracle.evaluate("t5-jump-to-now-playing-linux", value)["checks"]["correct_row_visible"])
        value = t5(); value["post"]["current_row"]["bottom"] = 721
        self.assertFalse(oracle.evaluate("t5-jump-to-now-playing-linux", value)["checks"]["row_within_scroll_bounds"])

    def test_t5_rejects_active_affordance_without_playing_track(self) -> None:
        value = t5(); value["no_playing"]["affordance"] = {"present": True, "enabled": True}
        self.assertFalse(oracle.evaluate("t5-jump-to-now-playing-linux", value)["checks"]["no_playing_affordance_inactive"])


if __name__ == "__main__":
    unittest.main()