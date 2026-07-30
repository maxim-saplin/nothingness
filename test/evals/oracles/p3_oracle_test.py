from __future__ import annotations

import importlib.util
import unittest
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ORACLE = ROOT / ".agents/skills/nothingness-evals/scripts/oracles/p3_oracle.py"
SPEC = importlib.util.spec_from_file_location("p3_oracle", ORACLE)
assert SPEC is not None and SPEC.loader is not None
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


def bounds(left: float, top: float, right: float, bottom: float) -> dict[str, float]:
  return {"left": left, "top": top, "right": right, "bottom": bottom}


def t6() -> dict[str, object]:
  scales = []
  for scale in (1.0, 1.5):
    scales.append({
      "scale": scale,
      "hero_bounds": bounds(0, 0, 400, 400),
      "dot_bounds": bounds(100, 130, 300, 330),
      "artist_bounds": bounds(56, 12, 344, 72),
      "title_bounds": bounds(56, 80, 344, 120),
      "overflow_errors": [],
      "screenshot": {"path": f"t6-{scale}.png", "sha256": "a" * 64, "nonblank": True},
    })
  return {
    "schema_version": 1,
    "scenario": {
      "artist": oracle.LONG_ARTIST,
      "title": oracle.LONG_TITLE,
      "max_dot_size": 120,
      "spectrum_peak": 1.0,
    },
    "fresh": {"show_song_info": False, "has_song_info": False},
    "enabled": {"app_instance": "first", "show_song_info": True, "has_song_info": True},
    "restarted": {"app_instance": "second", "show_song_info": True, "has_song_info": True},
    "disabled": {"show_song_info": False, "has_song_info": False},
    "scales": scales,
  }


def t7() -> dict[str, object]:
  paths = list(oracle.OPUS)
  return {
    "schema_version": 1,
    "inventory": [
      {"path": path, "sha256": sha256, "codec": "opus", "full_decode": True}
      for path, sha256 in oracle.OPUS.items()
    ],
    "queue": [{"path": path, "is_not_found": False} for path in paths],
    "pre": {"shuffle": True, "is_playing": True, "current_index": 0, "current_path": paths[0]},
    "action": {"type": "next", "succeeded": True},
    "post": {"shuffle": True, "is_playing": True, "current_index": 1, "current_path": paths[1]},
  }


class P3OracleTest(unittest.TestCase):
  def assert_t6_fails(self, value: dict[str, object], check: str) -> None:
    result = oracle.evaluate(oracle.T6, value)
    self.assertFalse(result["passed"])
    self.assertFalse(result["checks"][check])

  def assert_t7_fails(self, value: dict[str, object], check: str) -> None:
    result = oracle.evaluate(oracle.T7, value)
    self.assertFalse(result["passed"])
    self.assertFalse(result["checks"][check])

  def test_t6_accepts_frozen_persistent_clear_geometry(self) -> None:
    self.assertTrue(oracle.evaluate(oracle.T6, t6())["passed"])

  def test_t6_rejects_default_on_or_failed_persistence(self) -> None:
    value = t6()
    value["fresh"]["show_song_info"] = True
    self.assert_t6_fails(value, "fresh_default_off")
    value = t6()
    value["restarted"]["app_instance"] = "first"
    self.assert_t6_fails(value, "restart_persisted")

  def test_t6_rejects_conditional_rendering_failures(self) -> None:
    value = t6()
    value["enabled"]["has_song_info"] = False
    self.assert_t6_fails(value, "enabled_conditional_info")
    value = t6()
    value["disabled"]["has_song_info"] = True
    self.assert_t6_fails(value, "disabled_removes_info")

  def test_t6_rejects_overlap_out_of_bounds_overflow_and_bad_screenshot(self) -> None:
    for mutation in ("overlap", "outside", "overflow", "screenshot"):
      with self.subTest(mutation=mutation):
        value = t6()
        maximum = value["scales"][1]
        if mutation == "overlap":
          maximum["artist_bounds"] = bounds(56, 120, 344, 160)
        elif mutation == "outside":
          maximum["title_bounds"] = bounds(56, 380, 344, 420)
        elif mutation == "overflow":
          maximum["overflow_errors"] = ["RenderFlex overflowed"]
        else:
          maximum["screenshot"]["sha256"] = "not-a-sha"
        self.assert_t6_fails(value, "geometry_clear_at_both_scales")

  def test_t6_rejects_wrong_scenario_or_scale_boundary(self) -> None:
    value = t6()
    value["scenario"]["max_dot_size"] = 119
    self.assert_t6_fails(value, "frozen_stress_scenario")
    value = t6()
    value["scales"][1]["scale"] = 1.49
    self.assert_t6_fails(value, "exact_scales")

  def test_t7_accepts_exact_inventory_and_manifest_order_shuffle(self) -> None:
    self.assertTrue(oracle.evaluate(oracle.T7, t7())["passed"])

  def test_t7_rejects_missing_duplicate_extra_or_wrong_hash_inventory(self) -> None:
    for mutation in ("missing", "duplicate", "extra", "hash"):
      with self.subTest(mutation=mutation):
        value = t7()
        if mutation == "missing":
          value["inventory"].pop()
        elif mutation == "duplicate":
          value["inventory"][-1] = deepcopy(value["inventory"][0])
        elif mutation == "extra":
          value["inventory"].append({"path": "/opt/nothingness/media/extra.opus", "sha256": "f" * 64, "codec": "opus", "full_decode": True})
        else:
          value["inventory"][0]["sha256"] = "f" * 64
        self.assert_t7_fails(value, "inventory_exact")

  def test_t7_rejects_bad_codec_decode_or_queue_membership(self) -> None:
    value = t7()
    value["inventory"][0]["codec"] = "vorbis"
    self.assert_t7_fails(value, "inventory_exact")
    value = t7()
    value["inventory"][0]["full_decode"] = False
    self.assert_t7_fails(value, "inventory_exact")
    value = t7()
    value["queue"][0]["is_not_found"] = True
    self.assert_t7_fails(value, "all_queue_entries_found")
    value = t7()
    value["queue"].pop()
    self.assert_t7_fails(value, "queue_exact_once")

  def test_t7_rejects_shuffle_playback_membership_or_action_failures(self) -> None:
    mutations = (
      ("pre", "shuffle", False, "shuffle_enabled"),
      ("pre", "is_playing", False, "valid_media_playing"),
      ("pre", "current_path", "/outside.opus", "valid_media_playing"),
      ("action", "succeeded", False, "next_succeeded"),
      ("post", "current_path", "/outside.opus", "post_media_playing"),
      ("post", "is_playing", False, "post_media_playing"),
    )
    for section, key, replacement, check in mutations:
      with self.subTest(section=section, key=key):
        value = t7()
        value[section][key] = replacement
        self.assert_t7_fails(value, check)

  def test_t7_rejects_zero_queue_noop_and_state_queue_mismatch(self) -> None:
    value = t7()
    value["queue"] = []
    self.assert_t7_fails(value, "queue_exact_once")
    value = t7()
    value["post"]["current_index"] = value["pre"]["current_index"]
    value["post"]["current_path"] = value["pre"]["current_path"]
    self.assert_t7_fails(value, "navigation_transition")
    value = t7()
    value["post"]["current_path"] = value["queue"][2]["path"]
    self.assert_t7_fails(value, "state_matches_queue")


if __name__ == "__main__":
  unittest.main()