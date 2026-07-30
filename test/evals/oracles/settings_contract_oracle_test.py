from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ORACLE = ROOT / ".agents" / "skills" / "nothingness-evals" / "scripts" / "oracles" / "settings_contract_oracle.py"
SPEC = importlib.util.spec_from_file_location("settings_contract_oracle", ORACLE)
assert SPEC is not None and SPEC.loader is not None
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


def evidence(entries: list[dict[str, str]], post_entries: list[dict[str, str]] | None = None) -> dict[str, object]:
    changed = [dict(entry, value=f"{entry['value']} next") if entry["kind"] == "cassette_variant" else entry for entry in entries]
    return {
        "schema_version": 1,
        "semantic_entries": entries,
        "action": {"type": "tap_by_key", "key": "void-settings-cassette-variant", "succeeded": True},
        "post_semantic_entries": post_entries or changed,
        "screenshot": {"path": "evidence/settings.png", "sha256": "a" * 64},
    }


class SettingsContractOracleTest(unittest.TestCase):
    def test_t2_accepts_contiguous_cassette_variant(self) -> None:
        value = oracle.evaluate("t2-settings-placement-linux", evidence([
            {"kind": "theme", "label": "theme", "value": "void"},
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "variant", "value": "Tape Mono"},
            {"kind": "immersive", "label": "immersive", "value": "off"},
        ]))
        self.assertEqual(value["classification"], "pass")

    def test_t3_accepts_exact_color_scheme_label(self) -> None:
        value = oracle.evaluate("t3-settings-placement-color-scheme-linux", evidence([
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "color scheme", "value": "Tape Mono"},
        ]))
        self.assertTrue(value["passed"])

    def test_rejects_intervening_item(self) -> None:
        value = oracle.evaluate("t2-settings-placement-linux", evidence([
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "immersive", "label": "immersive", "value": "off"},
            {"kind": "cassette_variant", "label": "variant", "value": "Tape Mono"},
        ]))
        self.assertEqual(value["classification"], "semantic_failure")
        self.assertFalse(value["checks"]["cassette_variants_contiguous"])

    def test_rejects_missing_variants(self) -> None:
        value = oracle.evaluate("t2-settings-placement-linux", evidence([
            {"kind": "screen", "label": "screen", "value": "cassette"},
        ]))
        self.assertEqual(value["classification"], "semantic_failure")

    def test_t3_rejects_old_label(self) -> None:
        value = oracle.evaluate("t3-settings-placement-color-scheme-linux", evidence([
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "variant", "value": "Tape Mono"},
        ]))
        self.assertEqual(value["classification"], "semantic_failure")
        self.assertFalse(value["checks"]["old_variant_label_absent"])

    def test_t3_rejects_extra_cassette_selector(self) -> None:
        value = oracle.evaluate("t3-settings-placement-color-scheme-linux", evidence([
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "color scheme", "value": "Tape Mono"},
            {"kind": "cassette_variant", "label": "animation", "value": "on"},
        ]))
        self.assertEqual(value["classification"], "semantic_failure")
        self.assertFalse(value["checks"]["single_cassette_selector"])
        self.assertFalse(value["checks"]["color_scheme_present"])

    def test_rejects_missing_action_evidence(self) -> None:
        value = evidence([
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "variant", "value": "Tape Mono"},
        ])
        del value["action"]
        self.assertEqual(oracle.evaluate("t2-settings-placement-linux", value)["classification"], "missing_evidence")

    def test_rejects_noop_selector(self) -> None:
        entries = [
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "variant", "value": "Tape Mono"},
        ]
        value = oracle.evaluate("t2-settings-placement-linux", evidence(entries, entries))
        self.assertEqual(value["classification"], "semantic_failure")
        self.assertFalse(value["checks"]["selector_value_changed"])

    def test_rejects_selector_moved_after_action(self) -> None:
        entries = [
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "color scheme", "value": "Tape Mono"},
            {"kind": "immersive", "label": "immersive", "value": "off"},
        ]
        post_entries = [
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "immersive", "label": "immersive", "value": "off"},
            {"kind": "cassette_variant", "label": "color scheme", "value": "Tape Amber"},
        ]
        value = oracle.evaluate("t3-settings-placement-color-scheme-linux", evidence(entries, post_entries))
        self.assertEqual(value["classification"], "semantic_failure")
        self.assertFalse(value["checks"]["post_cassette_variants_contiguous"])

    def test_rejects_malformed_and_missing_evidence(self) -> None:
        self.assertEqual(oracle.evaluate("t2-settings-placement-linux", {})["classification"], "missing_evidence")
        malformed = evidence([{"kind": "screen", "label": "screen", "value": "cassette"}])
        malformed["screenshot"] = {"path": "evidence/settings.png", "sha256": "bad"}
        self.assertEqual(oracle.evaluate("t2-settings-placement-linux", malformed)["classification"], "malformed_evidence")

    def test_accepts_exact_contiguous_order_with_multiple_variants(self) -> None:
        value = oracle.evaluate("t2-settings-placement-linux", evidence([
            {"kind": "screen", "label": "screen", "value": "cassette"},
            {"kind": "cassette_variant", "label": "variant", "value": "mono"},
            {"kind": "cassette_variant", "label": "variant", "value": "amber"},
            {"kind": "immersive", "label": "immersive", "value": "off"},
        ]))
        self.assertTrue(value["passed"])


if __name__ == "__main__":
    unittest.main()