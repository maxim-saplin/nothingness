from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / ".agents" / "skills" / "nothingness-evals" / "scripts"
sys.path.insert(0, str(SCRIPTS))


def load_script(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


campaign_common = load_script("campaign_common.py")
campaign_run = load_script("campaign-run.py")
campaign_report = load_script("campaign_report.py")
watch_campaign = load_script("watch-campaign.py")
common = load_script("common.py")

SUITE = ROOT / "evals" / "suites" / "t1-t7-gpt-5.4-nano-medium.json"


def campaign_id(suffix: str) -> str:
    return f"gpt-5.4-nano--t1-t7-gpt-5.4-nano-medium--20260717T{suffix}Z"


class CampaignTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.campaigns_root = Path(self._tmp.name) / "campaigns"
        self.runs_root = Path(self._tmp.name) / "runs"
        self.publication_root = Path(self._tmp.name) / "evals"
        self.campaigns_root.mkdir()
        self.runs_root.mkdir()
        self._env_patch = patch.dict(
            os.environ,
            {
                "NOTHINGNESS_EVAL_PUBLICATION_ROOT": str(self.publication_root),
                "NOTHINGNESS_EVAL_CAMPAIGNS_ROOT": str(self.campaigns_root),
            },
        )
        self._env_patch.start()
        self.addCleanup(self._env_patch.stop)
        campaign_common.set_publication_root(self.publication_root)
        self.addCleanup(campaign_common.set_publication_root, None)
        self.patchers = [
            patch.object(campaign_common, "CAMPAIGNS_ROOT", self.campaigns_root),
            patch.object(campaign_common, "ROOT", ROOT),
            patch.object(campaign_common, "RUNS_ROOT", self.runs_root),
            patch.object(campaign_run, "CAMPAIGNS_ROOT", self.campaigns_root),
            patch.object(campaign_run, "ROOT", ROOT),
            patch.object(common, "RUNS_ROOT", self.runs_root),
            patch.object(campaign_run, "run_dir", lambda run_id: self.runs_root / run_id),
            patch.object(campaign_common, "run_dir", lambda run_id: self.runs_root / run_id),
        ]
        for patcher in self.patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_campaign(self, *args: str) -> dict:
        completed = subprocess.run(
            [sys.executable, str(SCRIPTS / "campaign-run.py"), *args],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if completed.returncode:
            self.fail(f"campaign-run failed: {completed.stderr.strip()}")
        return json.loads(completed.stdout)

    def test_validate_suite(self) -> None:
        suite = campaign_common.validate_suite_for_campaign(SUITE)
        self.assertEqual(suite["id"], "t1-t7-gpt-5.4-nano-medium")
        self.assertEqual(len(suite["tasks"]), 7)

    def test_synthetic_campaign_completes_seven_valid_tasks(self) -> None:
        state = campaign_common.build_initial_state(
            campaign_id=campaign_id("000100"),
            suite_path=SUITE,
            cost_ceiling_usd=1.0,
            token_ceiling=5_000_000,
        )
        campaign_common.save_campaign_state(state)
        for _ in range(7):
            campaign_run.apply_synthetic_attempt(
                state,
                validity="valid",
                outcome="candidate_fail",
                score=0,
                combined_cost=0.01,
                tokens=1000,
            )
        campaign_common.save_campaign_state(state)
        self.assertEqual(state["status"], "completed")
        self.assertEqual(len([task for task in state["tasks"] if task["status"] == "published"]), 7)
        snapshot, terminal = watch_campaign.render(campaign_id("000100"))
        self.assertIn("completed", snapshot)
        self.assertTrue(terminal)

    def test_invalid_cap_blocks_campaign(self) -> None:
        state = campaign_common.build_initial_state(
            campaign_id=campaign_id("000200"),
            suite_path=SUITE,
            cost_ceiling_usd=1.0,
            token_ceiling=5_000_000,
        )
        campaign_common.save_campaign_state(state)
        for _ in range(3):
            campaign_run.apply_synthetic_attempt(
                state,
                validity="invalid_infrastructure",
                outcome="unassigned",
                score=None,
            )
        campaign_common.save_campaign_state(state)
        self.assertEqual(state["status"], "blocked_infrastructure")
        self.assertEqual(state["current"]["task_index"], 0)

    def test_budget_pause_after_cost(self) -> None:
        state = campaign_common.build_initial_state(
            campaign_id=campaign_id("000300"),
            suite_path=SUITE,
            cost_ceiling_usd=0.03,
            token_ceiling=5_000_000,
        )
        campaign_common.save_campaign_state(state)
        campaign_run.apply_synthetic_attempt(
            state,
            validity="valid",
            outcome="candidate_fail",
            score=0,
            combined_cost=0.03,
            tokens=1000,
        )
        campaign_common.save_campaign_state(state)
        self.assertEqual(state["status"], "paused_budget")
        self.assertEqual(state["tasks"][0]["status"], "published")
        state["budget"]["candidate_admission_cost_ceiling_usd"] = 1.0
        state["status"] = "prepared"
        campaign_run.prepare_next_task_if_needed(state)
        campaign_run.apply_synthetic_attempt(
            state,
            validity="valid",
            outcome="candidate_fail",
            score=0,
            combined_cost=0.01,
            tokens=1000,
        )
        self.assertEqual(state["tasks"][1]["status"], "published")

    def test_unknown_cost_pauses_until_allowed(self) -> None:
        state = campaign_common.build_initial_state(
            campaign_id=campaign_id("000400"),
            suite_path=SUITE,
            cost_ceiling_usd=1.0,
            token_ceiling=5_000_000,
        )
        campaign_common.save_campaign_state(state)
        campaign_run.apply_synthetic_attempt(
            state,
            validity="valid",
            outcome="candidate_fail",
            score=0,
            unknown_cost=True,
        )
        self.assertEqual(state["status"], "paused_budget")
        state["budget"]["allow_unknown_cost"] = True
        state["status"] = "prepared"
        campaign_run.prepare_next_task_if_needed(state)
        campaign_run.apply_synthetic_attempt(
            state,
            validity="valid",
            outcome="candidate_fail",
            score=0,
            combined_cost=0.01,
            tokens=500,
        )
        self.assertEqual(state["tasks"][1]["status"], "published")

    def test_readme_index_helpers(self) -> None:
        state = campaign_common.build_initial_state(
            campaign_id=campaign_id("000500"),
            suite_path=SUITE,
            cost_ceiling_usd=1.0,
            token_ceiling=5_000_000,
        )
        state["status"] = "paused_budget"
        state["tasks"][0]["status"] = "published"
        state["tasks"][0]["attempts"] = [{"outcome": "candidate_fail", "score": 0}]
        section = campaign_report.model_readme_campaign_section(state)
        self.assertIn("paused_budget", section)
        self.assertIn("t1-playback-smoke-linux", section)
        summary = campaign_report.evals_readme_model_summary(state)
        self.assertIn("1/7", summary)
        merged = campaign_report.replace_marked_section("header\n", "campaign-index", section)
        self.assertIn("<!-- campaign-index:start -->", merged)


if __name__ == "__main__":
    unittest.main()
