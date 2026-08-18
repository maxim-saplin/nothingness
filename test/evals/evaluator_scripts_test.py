from __future__ import annotations

import argparse
import contextlib
import importlib.util
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / ".agents" / "skills" / "nothingness-evals" / "scripts"
sys.path.insert(0, str(SCRIPTS))


def write_fixture_run(runs_root: Path, run_id: str, suite_id: str, task_id: str, *, progress: dict | None = None, result: dict | None = None, summary: dict | None = None, admission: dict | None = None) -> Path:
    run = runs_root / run_id
    run.mkdir(parents=True, exist_ok=True)
    (run / "run.json").write_text(json.dumps({"run_id": run_id, "suite_id": suite_id, "task_id": task_id, "trial": 1, "calibration": False, "requested_model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}, "container": "fixture-container-not-running", "prepared_at": "2026-01-01T00:00:00Z"}))
    if progress is not None:
        (run / "artifacts").mkdir(parents=True, exist_ok=True)
        (run / "artifacts" / "progress.json").write_text(json.dumps(progress))
    if result is not None:
        (run / "result.json").write_text(json.dumps(result))
    if summary is not None:
        (run / "summary.json").write_text(json.dumps(summary))
    if admission is not None:
        (run / "admission.json").write_text(json.dumps(admission))
    return run


def load_script(name: str | Path):
    path = name if isinstance(name, Path) else SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


collect = load_script("collect.py")
summarize = load_script("summarize-run.py")
usage = load_script("usage.py")
classify = load_script("classify-run.py")
common = load_script("common.py")
build_image = load_script("build-image.py")
cleanup = load_script("cleanup.py")
preflight = load_script("preflight.py")
offline_baseline = load_script("verify-offline-baseline.py")
runtime_baseline = load_script("verify-runtime-baseline.py")
watch = load_script("watch-eval.py")
campaign = load_script("campaign.py")
judge_control = load_script("judge-control.py")
judge_verify = load_script("judge-verify.py")
judge_inspect = load_script("judge-inspect.py")
judge_run = load_script("judge-run.py")
candidate = load_script(ROOT / "evals" / "image" / "candidate.py")
proxy_spec = importlib.util.spec_from_file_location("egress_proxy", ROOT / "evals" / "image" / "egress_proxy.py")
proxy = importlib.util.module_from_spec(proxy_spec)
assert proxy_spec.loader is not None
proxy_spec.loader.exec_module(proxy)


class EvaluatorScriptsTest(unittest.TestCase):
    def test_offline_baseline_has_no_network_credentials_or_candidate(self) -> None:
        run_command = offline_baseline.container_run_command("baseline")
        checks = offline_baseline.baseline_checks("baseline")
        flattened = "\n".join(" ".join(command) for _, command in checks)
        self.assertIn("--network", run_command)
        self.assertEqual(run_command[run_command.index("--network") + 1], "none")
        self.assertEqual(run_command[run_command.index("--entrypoint") + 1], "sleep")
        self.assertNotIn("nothingness-eval-candidate", flattened)
        self.assertNotIn("auth.json", flattened)
        self.assertNotIn("AZURE_", flattened)
        self.assertIn("pi --version", flattened)

    def test_runtime_baseline_has_no_network_credentials_or_candidate(self) -> None:
        run_command = runtime_baseline.container_run_command("baseline")
        actions = "\n".join(
            " ".join(runtime_baseline.drive_command("baseline", *arguments))
            for arguments in (("resume",), ("pause",), ("next",), ("seek", "0:30"))
        )
        self.assertEqual(run_command[run_command.index("--network") + 1], "none")
        self.assertNotIn("nothingness-eval-candidate", actions)
        self.assertNotIn("auth.json", actions)
        self.assertNotIn("AZURE_", actions)
        self.assertIn("drive.py resume", actions)
        self.assertIn("drive.py pause", actions)
        self.assertIn("drive.py next", actions)
        self.assertIn("drive.py seek 0:30", actions)

    def test_collection_redacts_secrets_from_every_persisted_candidate_surface(self) -> None:
        dummy_key = "dummy-secret-key-123456"
        fingerprints = {"auth.json": "auth", "models.json": "models", "settings.json": "settings"}
        pi_config = {
            "pi_config": {
                "auth": json.dumps({"azure": {"apiKey": dummy_key}}),
                "models": json.dumps({"providers": {"azure": {"headers": {"Authorization": dummy_key}}}}),
                "settings": "{}",
            },
            "provider_env": {"AZURE_OPENAI_API_KEY": dummy_key},
            "config_fingerprints": fingerprints,
        }
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            artifacts = run / "artifacts"
            artifacts.mkdir(parents=True)
            common.write_json(run / "run.json", {"run_id": "run", "container": "candidate", "proxy": "proxy", "task_id": "other", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}, "scoring": {"mode": "scored"}})

            def completed(args, value: str | bytes = "", returncode: int = 0):
                return subprocess.CompletedProcess(args, returncode, value, "")

            def fake_command(args, **kwargs):
                if args[:3] == ["docker", "exec", "candidate"] and "find" in args:
                    source = args[args.index("find") + 1]
                    path = f"{source}/{dummy_key}.json\0".encode()
                    return completed(args, path)
                if args[:3] == ["docker", "exec", "candidate"] and "cat" in args:
                    source = args[-1]
                    if source.endswith("health.json") and kwargs.get("text", True):
                        return completed(args, json.dumps({dummy_key: {"detail": dummy_key}}))
                    return completed(args, f'{{"secret":"{dummy_key}"}}\n'.encode())
                if args[:2] == ["docker", "top"]:
                    return completed(args, f"PID COMMAND\n1 {dummy_key}\n")
                if args[:2] == ["docker", "logs"]:
                    return completed(args, f"proxy {dummy_key}\n")
                if args[:3] == ["docker", "exec", "candidate"]:
                    return completed(args, "file\n")
                raise AssertionError(args)

            def fake_command_or_fail(args, code, reason, **kwargs):
                if "ls-files" in args:
                    return completed(args, f"{dummy_key}.txt\0".encode())
                if args[:2] == ["docker", "inspect"]:
                    kwargs["stdout"].write("container image running\n")
                    return completed(args)
                return completed(args, f"candidate output {dummy_key}\n")

            with patch.object(collect, "run_dir", return_value=run), patch.object(collect, "require_command"), patch.object(collect, "read_host_pi_config", return_value=pi_config), patch.object(collect, "command", side_effect=fake_command), patch.object(collect, "command_or_fail", side_effect=fake_command_or_fail), patch.object(sys, "argv", ["collect.py", "run"]):
                collect.main()

            common.validate_no_secret_leaks(run, (dummy_key,))
            self.assertNotIn(dummy_key, "\n".join(path.relative_to(run).as_posix() for path in run.rglob("*")))
            self.assertIn("[REDACTED].txt", (artifacts / "untracked.txt").read_text())
            self.assertIn("[REDACTED]", common.read_json(artifacts / "health.json"))

    def test_failed_leak_scan_does_not_publish_or_leave_staging_artifacts(self) -> None:
        dummy_key = "dummy-secret-key-123456"
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            staging = run / ".artifacts-staging"
            destination = run / "artifacts"
            staging.mkdir()
            destination.mkdir()
            (staging / "candidate.jsonl").write_text(dummy_key)
            with self.assertRaises(SystemExit):
                collect.publish_artifacts(staging, destination, run, (dummy_key,))
            self.assertFalse(destination.exists())
            self.assertFalse(staging.exists())

    def test_structured_secret_keys_are_redacted_before_judge_persistence(self) -> None:
        dummy_key = "dummy-secret-key-123456"
        redacted = common.redact_value({"event": {dummy_key: {"nested": dummy_key}}}, (dummy_key,))
        self.assertEqual(redacted, {"event": {"[REDACTED]": {"nested": "[REDACTED]"}}})
        self.assertNotIn(dummy_key, json.dumps(redacted))

    def test_interrupted_intervention_cannot_be_classified_as_delivered(self) -> None:
        pending = [{"id": "judge-1", "delivery": "pending"}]
        with self.assertRaises(SystemExit):
            classify.delivered_interventions(pending, {})
        with self.assertRaises(SystemExit):
            classify.delivered_interventions([{"id": "judge-1", "delivery": "delivered"}], {"judge-1": "pending"})
        self.assertEqual(classify.delivered_interventions([{"id": "judge-1", "delivery": "delivered"}], {"judge-1": "delivered"}), {"judge-1"})

    def test_lost_intervention_response_remains_unresolved(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": {}}})
            common.write_json(run / "interventions.json", [])
            pi_config = {"pi_config": {}, "provider_env": {}, "config_fingerprints": {}}
            arguments = ["judge-control.py", "run", "steer", "--class", "recovery", "--message", "continue", "--reason", "recover"]
            with patch.object(judge_control, "run_dir", return_value=run), patch.object(judge_control, "read_host_pi_config", return_value=pi_config), patch.object(judge_control, "send", side_effect=RuntimeError("response_lost")), patch.object(sys, "argv", arguments), self.assertRaises(RuntimeError):
                judge_control.main()
            interventions = common.read_json(run / "interventions.json")
            self.assertEqual(interventions[0]["delivery"], "unknown")
            with self.assertRaises(SystemExit):
                classify.delivered_interventions(interventions, {interventions[0]["id"]: "pending"})

    def test_forced_cleanup_journals_abort_collection_and_intent_before_removal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            removal_saw_intent = False
            removed = False

            def fake_command(args, **kwargs):
                nonlocal removal_saw_intent, removed
                if args[:3] == ["docker", "container", "inspect"]:
                    return subprocess.CompletedProcess(args, 1 if removed else 0)
                if args[:3] == ["docker", "exec", "candidate"] and args[3:5] == ["test", "-f"]:
                    return subprocess.CompletedProcess(args, 1)
                if args[:3] == ["docker", "rm", "-f"]:
                    events = [json.loads(line)["event"] for line in (run / "termination.jsonl").read_text().splitlines()]
                    removal_saw_intent = events[-1] == "force_removal_requested"
                    removed = True
                    return subprocess.CompletedProcess(args, 0)
                return subprocess.CompletedProcess(args, 1)

            with patch.object(cleanup, "command", side_effect=fake_command), patch.object(cleanup.time, "sleep"):
                removed, completion = cleanup.terminate_candidate(run, "candidate")
            events = [json.loads(line)["event"] for line in (run / "termination.jsonl").read_text().splitlines()]
            self.assertTrue(removed)
            self.assertFalse(completion)
            self.assertTrue(removal_saw_intent)
            self.assertLess(events.index("supervisor_abort_requested"), events.index("artifact_collection_requested"))
            self.assertLess(events.index("artifact_collection_result"), events.index("force_removal_requested"))
            self.assertEqual(events[-1], "termination_verified")

    def test_forced_cleanup_rejects_successful_remove_without_confirmed_absence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()

            def fake_command(args, **kwargs):
                if args[:3] == ["docker", "container", "inspect"]:
                    return subprocess.CompletedProcess(args, 0)
                if args[:3] == ["docker", "exec", "candidate"] and args[3:5] == ["test", "-f"]:
                    return subprocess.CompletedProcess(args, 1)
                if args[:3] == ["docker", "rm", "-f"]:
                    return subprocess.CompletedProcess(args, 0)
                return subprocess.CompletedProcess(args, 1)

            with patch.object(cleanup, "command", side_effect=fake_command), patch.object(cleanup.time, "sleep"), self.assertRaises(SystemExit):
                cleanup.terminate_candidate(run, "candidate")
            verification = json.loads((run / "termination.jsonl").read_text().splitlines()[-1])
            self.assertEqual(verification["event"], "termination_verified")
            self.assertFalse(verification["absent"])

    def test_judge_review_requires_verified_terminal_coverage_and_all_inspections(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)

            def observation(observation_id: str, evidence: dict[str, object], **values):
                path = run / f"{observation_id}.json"
                common.write_json(path, {"observation_id": observation_id, **evidence})
                return {"observation_id": observation_id, "evidence": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), **values}

            event_evidence = {"after": 0, "next_sequence": 8, "events": [{"sequence": sequence} for sequence in range(1, 9)]}
            events = observation("events-1", event_evidence, kind="events", after=0, next_sequence=8, event_count=8)
            inspection_evidence = {"runtime": {"playback": {}}, "git": {"available": True}, "processes": {"available": True}}
            inspection = observation("inspection-1", inspection_evidence, kind="inspection", runtime=True, git=True, processes=True, availability={"runtime": None, "git": True, "processes": True})
            verification = observation("verification-1", {"label": "check"}, kind="verification", label="check", availability={"runtime": True, "tree": True, "semantics": False, "settings": True, "screenshot": True})
            classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, inspection, verification], ["events-1", "inspection-1", "verification-1"])
            unavailable_runtime_evidence = {"runtime": {"available": False}, "git": {"available": True}, "processes": {"available": True}}
            unavailable_runtime = observation("inspection-unavailable", unavailable_runtime_evidence, kind="inspection", runtime=True, git=True, processes=True, availability={"runtime": False, "git": True, "processes": True})
            classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, unavailable_runtime, verification], ["events-1", "inspection-unavailable", "verification-1"])
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 9}, [events, inspection, verification], ["events-1", "inspection-1", "verification-1"])
            without_processes = observation("inspection-2", {"runtime": {}, "git": {"available": True}}, kind="inspection", runtime=True, git=True, processes=False, availability={"runtime": None, "git": True})
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, without_processes, verification], ["events-1", "inspection-2", "verification-1"])
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, inspection], ["events-1", "inspection-1"])
            (run / "events-1.json").write_text("tampered")
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, inspection, verification], ["events-1", "inspection-1", "verification-1"])

    def test_judge_review_rejects_a_verification_observation_that_captured_nothing(self) -> None:
        # D2 regression: a `kind: verification` ledger entry whose manifest is
        # structurally valid but recorded zero successful captures (every
        # drive.py call failed or hit a content sentinel) must not satisfy
        # "the judge looked" — the whole point of requiring a cited
        # verification observation in the first place.
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)

            def observation(observation_id: str, evidence: dict[str, object], **values):
                path = run / f"{observation_id}.json"
                common.write_json(path, {"observation_id": observation_id, **evidence})
                return {"observation_id": observation_id, "evidence": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), **values}

            events = observation("events-1", {"after": 0, "next_sequence": 8, "events": [{"sequence": sequence} for sequence in range(1, 9)]}, kind="events", after=0, next_sequence=8, event_count=8)
            inspection = observation("inspection-1", {"runtime": {"playback": {}}, "git": {"available": True}, "processes": {"available": True}}, kind="inspection", runtime=True, git=True, processes=True)
            empty_verification = observation("verification-empty", {"label": "check"}, kind="verification", label="check", availability={"runtime": False, "tree": False, "semantics": False, "settings": False, "screenshot": False})
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, inspection, empty_verification], ["events-1", "inspection-1", "verification-empty"])
            missing_availability = observation("verification-no-map", {"label": "check"}, kind="verification", label="check")
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, inspection, missing_availability], ["events-1", "inspection-1", "verification-no-map"])

    def test_judge_review_rejects_gapped_truncated_and_overlapping_event_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)

            def observation(observation_id: str, after: int, sequences: list[int]):
                path = run / f"{observation_id}.json"
                evidence = {"observation_id": observation_id, "after": after, "next_sequence": sequences[-1], "events": [{"sequence": sequence} for sequence in sequences]}
                common.write_json(path, evidence)
                return {"observation_id": observation_id, "kind": "events", "after": after, "next_sequence": sequences[-1], "event_count": len(sequences), "evidence": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

            inspection_path = run / "inspection.json"
            common.write_json(inspection_path, {"observation_id": "inspection", "runtime": {}, "git": {"available": True}, "processes": {"available": True}})
            inspection = {"observation_id": "inspection", "kind": "inspection", "runtime": True, "git": True, "processes": True, "evidence": inspection_path.name, "sha256": hashlib.sha256(inspection_path.read_bytes()).hexdigest()}
            verification_path = run / "verification.json"
            common.write_json(verification_path, {"observation_id": "verification", "label": "check"})
            verification = {"observation_id": "verification", "kind": "verification", "label": "check", "evidence": verification_path.name, "sha256": hashlib.sha256(verification_path.read_bytes()).hexdigest()}
            for event_observations in (
                [observation("terminal-only", 0, [8])],
                [observation("truncated", 0, [1, 2, 3, 4])],
                [observation("first", 0, [1, 2, 3, 4, 5]), observation("overlap", 4, [5, 6, 7, 8])],
            ):
                observations = [*event_observations, inspection, verification]
                cited = [item["observation_id"] for item in observations]
                with self.assertRaises(SystemExit):
                    classify.validate_judge_review(run, {"terminal_event_sequence": 8}, observations, cited)

    def test_missing_price_stays_unknown_in_candidate_and_dashboard(self) -> None:
        totals = {name: 0.0 for name in ("input", "output", "reasoning", "cacheRead", "cacheWrite", "totalTokens")}
        candidate.add_usage(totals, {"input": 2, "totalTokens": 2})
        self.assertNotIn("cost", totals)
        self.assertEqual(watch.money(None), "unknown")
        with tempfile.TemporaryDirectory() as temporary, patch.object(watch, "command", return_value=subprocess.CompletedProcess([], 1, "", "")):
            self.assertIsNone(watch.progress_for(Path(temporary), {"container": "missing", "prepared_at": "now"})["cost_usd"])

    def test_mutated_frozen_contract_is_rejected_before_admission_command(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            suite_path = root / "evals" / "suites" / "suite.json"
            task_path = root / "evals" / "tasks" / "task.json"
            suite_path.parent.mkdir(parents=True)
            task_path.parent.mkdir(parents=True)
            suite_path.write_text('{"id":"suite"}')
            task = {"id": "task", "prompt": "before", "limits": {}, "platform_variant": "linux"}
            task_path.write_text(json.dumps(task))
            metadata = {"suite_id": "suite", "suite_manifest_sha256": common.sha256(suite_path), "task_id": "task", "task_contract": {**task, "manifest_sha256": common.sha256(task_path)}}
            task_path.write_text(json.dumps(task | {"prompt": "mutated"}))
            with patch.object(preflight, "command") as admission_command, self.assertRaises(SystemExit):
                preflight.validate_pre_admission_contract(metadata, root)
            admission_command.assert_not_called()

    def test_served_model_match_is_the_real_identity_check_preflight_now_performs(self) -> None:
        # This replaces the old `validate_model_identity(requested,
        # requested.copy())` tautology at prepare-run.py time: the comparison
        # now runs against `served`, pi's own account of what it served
        # (candidate.py's run_probe -> admission/result.json's
        # "served_model"), and a mismatch on provider or model must be
        # rejected. `thinking` is deliberately not part of this comparison --
        # pi's event stream never echoes back what thinking level it actually
        # used, so there is nothing genuine to compare there (see
        # references/scoring.md's Known limitations).
        requested = {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}
        self.assertTrue(preflight.served_model_matches(requested, {"provider": "azure-openai-responses", "model": "gpt-5.4-mini"}))
        self.assertFalse(preflight.served_model_matches(requested, {"provider": "azure-openai-responses", "model": "gpt-5.4-nano"}))
        self.assertFalse(preflight.served_model_matches(requested, {"provider": "azure-chat", "model": "gpt-5.4-mini"}))
        self.assertFalse(preflight.served_model_matches(requested, None))
        self.assertFalse(preflight.served_model_matches(requested, "gpt-5.4-mini"))

    def test_pi_model_listing_requires_exact_provider_and_model(self) -> None:
        output = "provider model context max-out thinking images\nazure-openai-responses gpt-5.4-nano 400K 128K yes yes\nazure-chat gpt-5.4-nano 128K 32K no yes\n"
        models = common.parse_pi_model_listing(output)
        self.assertEqual(models[0], {"provider": "azure-openai-responses", "model": "gpt-5.4-nano", "thinking": "yes"})
        self.assertNotEqual(models[0]["provider"], models[1]["provider"])

    def test_azure_egress_uses_exact_https_configuration(self) -> None:
        self.assertEqual(common.derive_provider_egress_host("{}", "azure-openai-responses", {"AZURE_OPENAI_BASE_URL": "https://resource.openai.azure.com/openai/v1"}), "resource.openai.azure.com")
        self.assertEqual(common.derive_provider_egress_host("{}", "azure-openai-responses", {"AZURE_OPENAI_RESOURCE_NAME": "resource-name"}), "resource-name.openai.azure.com")
        with self.assertRaises(SystemExit):
            common.derive_provider_egress_host("{}", "azure-openai-responses", {"AZURE_OPENAI_BASE_URL": "http://resource.openai.azure.com"})

    def test_frozen_task_rejects_manifest_mutation(self) -> None:
        task = {"id": "task", "prompt": "before", "limits": {"timeout_seconds": 1}, "platform_variant": "linux"}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "task.json"
            path.write_text(json.dumps(task))
            metadata = {"task_contract": {**task, "manifest_sha256": common.sha256(path)}}
            common.validate_frozen_task(metadata, path)
            path.write_text(json.dumps(task | {"prompt": "after"}))
            with self.assertRaises(SystemExit):
                common.validate_frozen_task(metadata, path)

    def test_rpc_bridge_accounts_completed_turns_and_activity(self) -> None:
        totals = {name: 0.0 for name in ("input", "output", "reasoning", "cacheRead", "cacheWrite", "totalTokens", "cost")}
        candidate.add_usage(totals, {"input": 2, "output": 3, "reasoning": 4, "cacheRead": 5, "cacheWrite": 6, "totalTokens": 20, "cost": {"total": 0.07}})
        self.assertEqual(totals, {"input": 2.0, "output": 3.0, "reasoning": 4.0, "cacheRead": 5.0, "cacheWrite": 6.0, "totalTokens": 20.0, "cost": 0.07})
        self.assertEqual(candidate.activity({"type": "tool_execution_start", "toolName": "bash"}), "tool call: bash")
        self.assertEqual(candidate.activity({"type": "agent_end"}), "candidate awaiting judge")

    def test_candidate_provider_environment_is_allowlisted(self) -> None:
        expected = {"AZURE_OPENAI_BASE_URL": "https://example.openai.azure.com"}
        self.assertEqual(candidate.provider_environment("azure-openai-responses", expected), expected)
        with self.assertRaises(ValueError):
            candidate.provider_environment("azure-openai-responses", {"UNRELATED_SECRET": "value"})

    def _probe_arguments(self, provider: str = "azure-openai-responses", model: str = "gpt-5.4-mini", thinking: str = "medium") -> argparse.Namespace:
        return argparse.Namespace(provider=provider, model=model, thinking=thinking, timeout_seconds=30)

    def test_admission_probe_captures_pis_own_served_model_and_requires_it_for_ok(self) -> None:
        # This is the actual fix under test: run_probe used to parse only
        # text/stop_reason/usage from pi's final message and never looked at
        # the "provider"/"model" fields the real captured transcript
        # (events-91723fff02ce4ca5bd54aaad75765efc.json.gz, T1 nano trial 1)
        # shows on every assistant message_end/turn_end. Those fields are
        # genuine, independent evidence of what pi actually served.
        message_end = {"type": "message_end", "message": {"role": "assistant", "content": [{"type": "text", "text": "READY"}], "api": "azure-openai-responses", "provider": "azure-openai-responses", "model": "gpt-5.4-mini", "usage": {"totalTokens": 42}, "stopReason": "stop"}}
        stdout = json.dumps(message_end) + "\n"
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary)
            (runtime / "admission").mkdir()
            completed = subprocess.CompletedProcess(["pi"], 0, stdout, "")
            with patch.object(candidate, "RUNTIME", runtime), patch.object(candidate.subprocess, "run", return_value=completed):
                exit_code = candidate.run_probe(self._probe_arguments(), Path(temporary) / "config", {})
            result = common.read_json(runtime / "admission" / "result.json")
        self.assertEqual(exit_code, 0)
        self.assertTrue(result["ok"])
        self.assertEqual(result["served_model"], {"provider": "azure-openai-responses", "model": "gpt-5.4-mini"})

    def test_admission_probe_is_not_ok_when_pi_never_reports_a_served_model(self) -> None:
        # A response that otherwise looks perfectly admissible (right text,
        # a real stop reason, positive token usage) but whose message carries
        # no provider/model fields at all must not be treated as identity
        # evidence -- absence of the field is not the same as a match.
        message_end = {"type": "message_end", "message": {"role": "assistant", "content": [{"type": "text", "text": "READY"}], "usage": {"totalTokens": 42}, "stopReason": "stop"}}
        stdout = json.dumps(message_end) + "\n"
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary)
            (runtime / "admission").mkdir()
            completed = subprocess.CompletedProcess(["pi"], 0, stdout, "")
            with patch.object(candidate, "RUNTIME", runtime), patch.object(candidate.subprocess, "run", return_value=completed):
                exit_code = candidate.run_probe(self._probe_arguments(), Path(temporary) / "config", {})
            result = common.read_json(runtime / "admission" / "result.json")
        self.assertEqual(exit_code, 4)
        self.assertFalse(result["ok"])
        self.assertIsNone(result["served_model"])

    def test_task_scoring_preserves_manifest_object(self) -> None:
        scoring = {"mode": "scored", "cohort": "linux-isolated-baseline"}
        self.assertEqual(common.task_scoring({"scoring": scoring}), scoring)
        with self.assertRaises(SystemExit):
            common.task_scoring({"scoring": "scored"})

    def test_host_config_is_validated_and_fingerprinted_without_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "auth.json").write_text('{"token":"secret"}')
            (directory / "models.json").write_text('{"providers":{"azure":{"baseUrl":"https://example.openai.azure.com"}}}')
            (directory / "settings.json").write_text("{}")
            for path in directory.iterdir():
                path.chmod(0o600)
            payload = common.read_host_pi_config(directory)
        self.assertEqual(payload["config_fingerprints"].keys(), {"auth.json", "models.json", "settings.json"})
        self.assertNotIn("secret", json.dumps(payload["config_fingerprints"]))
        self.assertEqual(common.derive_egress_host(payload["pi_config"]["models"], "azure"), "example.openai.azure.com")

    def test_model_selection_must_exist_for_provider(self) -> None:
        models = '{"providers":{"azure":{"models":[{"id":"model-a"}]}}}'
        common.validate_model_selection(models, "azure", "model-a")
        with self.assertRaises(SystemExit):
            common.validate_model_selection(models, "azure", "model-b")

    def test_requested_model_must_exactly_match_selected_model(self) -> None:
        requested = {"provider": "azure-openai-responses", "model": "gpt-5.4-nano", "thinking": "medium"}
        common.validate_model_identity(requested, requested.copy())
        for key, replacement in (("provider", "azure-chat"), ("model", "other"), ("thinking", "low")):
            selected = requested | {key: replacement}
            with self.assertRaises(SystemExit):
                common.validate_model_identity(requested, selected)

    def test_docker_resource_names_are_stable_dns_labels(self) -> None:
        run_id = "t1-gpt-5-4-nano-medium-t1-playback-smoke-linux-calibration-attempt-01"
        names = (common.container_name(run_id), common.proxy_name(run_id), common.network_name(run_id))
        self.assertTrue(all(len(name) <= 63 for name in names))
        self.assertEqual(common.container_name(run_id), common.container_name(run_id))
        self.assertNotEqual(common.container_name(run_id), common.container_name(f"{run_id}-other"))

    def test_host_config_rejects_unsafe_auth_and_ambiguous_egress(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name, value in (("auth.json", "{}"), ("models.json", "{}"), ("settings.json", "{}")):
                (directory / name).write_text(value)
            with self.assertRaises(SystemExit):
                common.read_host_pi_config(directory)
        with self.assertRaises(SystemExit):
            common.derive_egress_host('{"providers":{"x":{"baseUrl":"http://example.com"}}}', "x")

    def test_pi_package_roots_reject_escaping_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "npm").mkdir()
            (directory / "git").mkdir()
            (directory / "npm" / "escape").symlink_to("/tmp")
            with self.assertRaises(SystemExit):
                common.pi_package_roots(directory)

    def test_reproducible_archive_has_stable_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "source"
            source.mkdir()
            (source / "file.txt").write_text("same")
            first = directory / "first.tar.gz"
            second = directory / "second.tar.gz"
            build_image.reproducible_archive(first, ((source, "payload"),))
            build_image.reproducible_archive(second, ((source, "payload"),))
            self.assertEqual(common.sha256(first), common.sha256(second))

    def test_proxy_allows_only_exact_https_destinations(self) -> None:
        allowed = {"api.openai.com"}
        self.assertTrue(proxy.allowed_destination("api.openai.com", 443, allowed))
        self.assertFalse(proxy.allowed_destination("sub.api.openai.com", 443, allowed))
        self.assertFalse(proxy.allowed_destination("api.openai.com", 80, allowed))
        self.assertFalse(proxy.allowed_destination("127.0.0.1", 443, allowed))

    def test_safe_untracked_path_rejects_traversal_and_absolute_paths(self) -> None:
        self.assertEqual(collect.safe_untracked_path("tool/smoke.py"), Path("tool/smoke.py"))
        self.assertIsNone(collect.safe_untracked_path("../secret"))
        self.assertIsNone(collect.safe_untracked_path("/workspace/secret"))

    def test_summarize_jsonl_uses_execution_start_not_updates(self) -> None:
        events = [
            {"type": "tool_execution_start"},
            {"type": "tool_execution_update"},
            {"type": "message_update", "message": {"text": "ignore"}},
            {"type": "message_end", "message": {"role": "assistant", "content": [{"type": "text", "text": "final"}], "usage": {"totalTokens": 7, "cost": {"total": 0.1}}, "stopReason": "stop"}},
            {"type": "turn_end", "message": {"role": "assistant", "usage": {"inputTokens": 4, "outputTokens": 3, "totalTokens": 7, "cost": {"total": 0.1, "input": 0.02}}}},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            transcript = Path(temporary) / "candidate.jsonl"
            transcript.write_text("".join(json.dumps(event) + "\n" for event in events))
            result = summarize.summarize_jsonl(transcript)
        self.assertEqual(result["tool_executions"], 1)
        self.assertEqual(result["final_assistant_text"], "final")
        self.assertEqual(result["usage"]["final"]["tokens"]["total"], 7)
        self.assertEqual(result["usage"]["aggregate"]["tokens"]["total"], 7)
        self.assertEqual(result["usage"]["aggregate"]["cost_usd"]["total"], 0.1)

    def test_summarize_jsonl_collects_deduplicated_served_models_from_turn_end(self) -> None:
        # Real evidence for this shape: the committed T1 nano trial transcript
        # (evals/results/gpt-5.4-nano/t1-playback-smoke-linux/trial-1/evidence)
        # has 19 turn_end events, every one carrying identical
        # api/provider/model fields on its assistant message -- this asserts
        # that repeated identical turns collapse to one served_models entry,
        # and that a turn_end with no provider/model contributes nothing.
        events = [
            {"type": "turn_end", "message": {"role": "assistant", "api": "azure-openai-responses", "provider": "azure-openai-responses", "model": "gpt-5.4-mini", "usage": {"totalTokens": 1}}},
            {"type": "turn_end", "message": {"role": "assistant", "api": "azure-openai-responses", "provider": "azure-openai-responses", "model": "gpt-5.4-mini", "usage": {"totalTokens": 1}}},
            {"type": "turn_end", "message": {"role": "assistant", "usage": {"totalTokens": 1}}},
            {"type": "message_end", "message": {"role": "assistant", "provider": "should-not-be-seen", "model": "should-not-be-seen"}},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            transcript = Path(temporary) / "candidate.jsonl"
            transcript.write_text("".join(json.dumps(event) + "\n" for event in events))
            result = summarize.summarize_jsonl(transcript)
        self.assertEqual(result["served_models"], [{"provider": "azure-openai-responses", "model": "gpt-5.4-mini"}])

    def _write_summarize_run_fixture(self, run: Path, requested_model: dict[str, str], turn_events: list[dict[str, object]], *, selected_model: dict[str, str] | None = None) -> None:
        common.write_json(run / "run.json", {"requested_model": requested_model, "selected_model": selected_model, "prepared_at": "2026-01-01T00:00:00Z"})
        artifacts = run / "artifacts"
        artifacts.mkdir(parents=True)
        (artifacts / "candidate.jsonl").write_text("".join(json.dumps(event) + "\n" for event in turn_events))
        common.write_json(artifacts / "candidate-completion.json", {"reason": "judge_finish:done", "started_at_unix": 0, "finished_at_unix": 1})

    def test_summarize_run_verifies_identity_against_the_real_transcript_not_a_copy(self) -> None:
        # This is the core of the (a) fix: `model_identity_verified` in
        # summary.json must come from the candidate session's own transcript,
        # not from comparing run.json's requested_model to a value that was a
        # copy of it. Same requested/selected pair, three different real
        # transcripts: a matching one verifies; a transcript that never
        # completed a turn does not (no evidence, no claim); a transcript
        # that served a materially different model does not either (the
        # exact defect this task exists to fix -- a run reporting model X's
        # cost/behavior while pi actually served model Y).
        requested = {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}
        matching_turn = {"type": "turn_end", "message": {"role": "assistant", "provider": "azure-openai-responses", "model": "gpt-5.4-mini", "usage": {"totalTokens": 1}}}
        mismatched_turn = {"type": "turn_end", "message": {"role": "assistant", "provider": "azure-openai-responses", "model": "gpt-5.4-nano", "usage": {"totalTokens": 1}}}

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            self._write_summarize_run_fixture(run, requested, [matching_turn], selected_model=requested)
            with patch.object(summarize, "run_dir", return_value=run), patch.object(sys, "argv", ["summarize-run.py", "run"]):
                summarize.main()
            summary = common.read_json(run / "summary.json")
        self.assertTrue(summary["model_identity_verified"])
        self.assertEqual(summary["served_models"], [{"provider": "azure-openai-responses", "model": "gpt-5.4-mini"}])

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            self._write_summarize_run_fixture(run, requested, [], selected_model=requested)
            with patch.object(summarize, "run_dir", return_value=run), patch.object(sys, "argv", ["summarize-run.py", "run"]):
                summarize.main()
            summary = common.read_json(run / "summary.json")
        self.assertFalse(summary["model_identity_verified"])
        self.assertEqual(summary["served_models"], [])

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            # requested_model and selected_model still agree (both were
            # frozen/derived from the same identity) -- only the transcript
            # itself shows a different served model, proving this check is
            # no longer the requested-vs-selected tautology it replaced.
            self._write_summarize_run_fixture(run, requested, [mismatched_turn], selected_model=requested)
            with patch.object(summarize, "run_dir", return_value=run), patch.object(sys, "argv", ["summarize-run.py", "run"]):
                summarize.main()
            summary = common.read_json(run / "summary.json")
        self.assertFalse(summary["model_identity_verified"])
        self.assertEqual(summary["served_models"], [{"provider": "azure-openai-responses", "model": "gpt-5.4-nano"}])

    def test_usage_normalization_keeps_azure_cost_and_flags_missing_cost(self) -> None:
        normalized = usage.normalized_usage({"inputTokens": 2, "outputTokens": 3, "totalTokens": 5, "cost": {"total": 0.04, "input": 0.01}})
        self.assertEqual(normalized["tokens"], {"input": 2, "output": 3, "reasoning": 0, "cacheRead": 0, "cacheWrite": 0, "total": 5})
        self.assertEqual(normalized["cost_usd"]["total"], 0.04)
        self.assertFalse(normalized["cost_missing"])
        self.assertTrue(usage.normalized_usage({"totalTokens": 2})["cost_missing"])

    def test_usage_normalization_supports_pi_native_keys(self) -> None:
        normalized = usage.normalized_usage({"input": 2, "output": 3, "reasoning": 1, "cacheRead": 4, "cacheWrite": 5, "totalTokens": 14, "cost": {"total": 0.06}})
        self.assertEqual(normalized["tokens"], {"input": 2, "output": 3, "reasoning": 1, "cacheRead": 4, "cacheWrite": 5, "total": 14})
        self.assertEqual(normalized["cost_usd"]["total"], 0.06)

    def test_result_schema_rejects_invalid_score_combinations(self) -> None:
        classify.validate_classification("valid", "pass", 3)
        classify.validate_classification("valid", "partial", 2)
        classify.validate_classification("valid", "partial", 1)
        classify.validate_classification("valid", "fail", 0)
        with self.assertRaises(SystemExit):
            classify.validate_classification("invalid_infrastructure", "unassigned", 1)
        with self.assertRaises(SystemExit):
            classify.validate_classification("valid", "pass", 4)
        with self.assertRaises(SystemExit):
            classify.validate_classification("valid", "pass", 2)
        with self.assertRaises(SystemExit):
            classify.validate_classification("valid", "fail", 3)
        with self.assertRaises(SystemExit):
            classify.validate_classification("invalid_infrastructure", "fail", None)

    def test_score_band_boundaries_are_left_closed(self) -> None:
        self.assertEqual(classify.score_band(0.85), 3)
        self.assertEqual(classify.score_band(0.849999), 2)
        self.assertEqual(classify.score_band(1.0), 3)
        self.assertEqual(classify.score_band(0.60), 2)
        self.assertEqual(classify.score_band(0.599999), 1)
        self.assertEqual(classify.score_band(0.30), 1)
        self.assertEqual(classify.score_band(0.299999), 0)
        self.assertEqual(classify.score_band(0.0), 0)

    def test_intervention_penalty_scales_linearly_and_caps_at_three(self) -> None:
        scorecard = [{"id": "E1", "tier": "required", "verdict": "met", "note": "ok", "evidence_ref": "verification-1"}]
        for delivered_count, expected_penalty in ((0, 0.0), (1, 0.05), (2, 0.10), (3, 0.15), (4, 0.15)):
            computed = classify.compute_scorecard(scorecard, delivered_count)
            self.assertEqual(computed["penalty"], expected_penalty)
            self.assertEqual(computed["adjusted"], round(1.0 - expected_penalty, 6))

    def test_required_unmet_expectation_caps_score_at_two_despite_high_adjusted(self) -> None:
        scorecard = [
            {"id": "E1", "tier": "required", "verdict": "unmet", "note": "missing the core ask", "evidence_ref": "verification-1"},
            *({"id": f"E{n}", "tier": "required", "verdict": "met", "note": "ok", "evidence_ref": "verification-1"} for n in range(2, 8)),
        ]
        computed = classify.compute_scorecard(scorecard, 0)
        self.assertGreaterEqual(computed["adjusted"], 0.85)
        self.assertTrue(computed["required_unmet"])
        self.assertEqual(computed["score"], 2)
        self.assertEqual(computed["outcome"], "partial")

    def test_scorecard_rejects_expectation_ids_that_do_not_match_rubric(self) -> None:
        expectations = {"E1": {"tier": "required", "evidence": "verification"}, "E2": {"tier": "secondary", "evidence": "verification"}}
        matching = [
            {"id": "E1", "tier": "required", "verdict": "met", "note": "ok", "evidence_ref": "verification-1"},
            {"id": "E2", "tier": "secondary", "verdict": "met", "note": "ok", "evidence_ref": "verification-1"},
        ]
        self.assertEqual(classify.validate_scorecard(matching, expectations), matching)
        missing_one = [matching[0]]
        with self.assertRaises(SystemExit):
            classify.validate_scorecard(missing_one, expectations)
        wrong_id = [matching[0], {**matching[1], "id": "E9"}]
        with self.assertRaises(SystemExit):
            classify.validate_scorecard(wrong_id, expectations)
        wrong_tier = [matching[0], {**matching[1], "tier": "required"}]
        with self.assertRaises(SystemExit):
            classify.validate_scorecard(wrong_tier, expectations)

    def test_rubric_expectations_parses_real_t2_rubric_sections(self) -> None:
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / "t2-settings-placement-linux.md"
        expectations = classify.rubric_expectations(rubric_path)
        self.assertEqual({identifier for identifier, value in expectations.items() if value["tier"] == "required"}, {"E1", "E2", "E3", "E4", "E5"})
        self.assertEqual({identifier for identifier, value in expectations.items() if value["tier"] == "secondary"}, {"E6", "E7", "E8"})
        # Every T2 expectation is legitimately settled by looking at the live
        # app (screenshot/tree/semantics/settings) — there is no git/workspace-
        # only or candidate-self-report expectation in this rubric.
        self.assertTrue(all(value["evidence"] == "verification" for value in expectations.values()))

    def test_rubric_expectations_parses_real_t1_rubric_evidence_kinds(self) -> None:
        # D1: per-expectation evidence-kind binding. T1/E6 ("no unrequested
        # source changes") is legitimately a git/workspace check (inspection);
        # T1/E5 ("claims traceable to an actual observation") audits the
        # candidate's own session event trail, not the judge's live look
        # (events). Every behavior-verification expectation stays verification.
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / "t1-playback-smoke-linux.md"
        expectations = classify.rubric_expectations(rubric_path)
        self.assertEqual({identifier: value["evidence"] for identifier, value in expectations.items()}, {
            "E1": "verification",
            "E2": "verification",
            "E3": "verification",
            "E4": "verification",
            "E5": "events",
            "E6": "inspection",
            "E7": "verification",
        })

    def test_fourth_delivered_intervention_is_refused_with_a_distinct_exit_code(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": {}}})
            common.write_json(run / "interventions.json", [{"id": f"judge-{index}", "delivery": "delivered"} for index in range(3)])
            pi_config = {"pi_config": {}, "provider_env": {}, "config_fingerprints": {}}
            arguments = ["judge-control.py", "run", "steer", "--class", "recovery", "--message", "keep going", "--reason", "recover"]
            with patch.object(judge_control, "run_dir", return_value=run), patch.object(judge_control, "read_host_pi_config", return_value=pi_config), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit) as context:
                    judge_control.main()
            self.assertEqual(context.exception.code, 6)
            self.assertEqual(len(common.read_json(run / "interventions.json")), 3)

    def test_concurrent_steer_calls_cannot_exceed_the_intervention_cap_or_lose_a_delivery(self) -> None:
        # D5 regression: judge-control.py's read-check-append-write for the
        # intervention cap was unlocked, so two concurrent `steer` processes
        # both starting from a delivered count of 2 could both read 2, both
        # pass the `>= 3` check, and both actually reach the candidate — with
        # the journal only ever showing 3 entries (a lost update). Two real
        # threads (flock is enforced at the OS/file-description level, not
        # per-thread, so this genuinely exercises the lock) hit the same
        # locked section concurrently; exactly one must be admitted past the
        # cap and one must be refused, and nothing may be lost from the log.
        import concurrent.futures
        import time

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": {}}})
            common.write_json(run / "interventions.json", [{"id": f"judge-{index}", "delivery": "delivered"} for index in range(2)])
            pi_config = {"pi_config": {}, "provider_env": {}, "config_fingerprints": {}}

            def slow_send(container, payload):
                time.sleep(0.05)
                return {"ok": True}

            def invoke(label: str) -> None:
                judge_control.main(["run", "steer", "--class", "recovery", "--message", f"go-{label}", "--reason", "recover"])

            with patch.object(judge_control, "run_dir", return_value=run), patch.object(judge_control, "read_host_pi_config", return_value=pi_config), patch.object(judge_control, "send", side_effect=slow_send):
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    futures = [pool.submit(invoke, label) for label in ("a", "b")]
                    outcomes = []
                    for future in concurrent.futures.as_completed(futures):
                        try:
                            future.result()
                            outcomes.append("ok")
                        except SystemExit as exit_error:
                            outcomes.append(exit_error.code)

            self.assertCountEqual(outcomes, ["ok", 6])
            interventions = common.read_json(run / "interventions.json")
            self.assertEqual(len(interventions), 3)
            self.assertEqual(sum(1 for item in interventions if item["delivery"] == "delivered"), 3)

    def test_judge_verify_captures_five_artifacts_and_appends_verification_observation(self) -> None:
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}
        png_bytes = b"\x89PNG\r\n\x1a\nfakepixels"
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}})

            def fake_command(args, **kwargs):
                if args[:5] == ["docker", "exec", "candidate", "python3", judge_verify.DRIVER]:
                    action = args[5]
                    if action == "contract":
                        return subprocess.CompletedProcess(args, 0, json.dumps({"count": 1, "extensions": ["ext.nothingness.getPlaybackState"]}), "")
                    if action == "inspect":
                        return subprocess.CompletedProcess(args, 0, json.dumps({"playback": {"isPlaying": True}}), "")
                    if action == "tree":
                        return subprocess.CompletedProcess(args, 0, "Root\n  Child\n", "")
                    if action == "call" and args[6] == "ext.nothingness.getSemantics":
                        return subprocess.CompletedProcess(args, 0, json.dumps({"semantics": "SemanticsNode#1(label: cassette)"}), "")
                    if action == "call" and args[6] == "ext.nothingness.getSettings":
                        return subprocess.CompletedProcess(args, 0, json.dumps({"screenType": "cassette"}), "")
                    if action == "shoot":
                        return subprocess.CompletedProcess(args, 0, json.dumps({"path": "shot"}), "")
                if args[:3] == ["docker", "exec", "candidate"] and args[3] == "cat" and args[4].endswith(".png"):
                    return subprocess.CompletedProcess(args, 0, png_bytes, "")
                if args[:5] == ["docker", "exec", "candidate", "test", "-f"]:
                    return subprocess.CompletedProcess(args, 0, "", "")  # default flutter_run.log present
                raise AssertionError(args)

            with patch.object(judge_verify, "run_dir", return_value=run), patch.object(judge_verify, "read_host_pi_config", return_value=pi_config), patch.object(judge_verify, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-verify.py", "run", "--label", "t2-cassette-check"]):
                judge_verify.main()

            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            self.assertEqual(len(observations), 1)
            self.assertEqual(observations[0]["kind"], "verification")
            self.assertTrue(all(observations[0]["availability"].values()))
            manifest = common.read_json(run / observations[0]["evidence"])
            self.assertEqual(manifest["observation_id"], observations[0]["observation_id"])
            self.assertEqual(set(manifest["artifacts"]), {"runtime", "tree", "semantics", "settings", "screenshot"})
            self.assertEqual(manifest["unavailable_reasons"], {})
            self.assertEqual(manifest["discovery"], {"method": "default", "log_path": judge_verify.DEFAULT_RUN_LOG, "env": {}})
            screenshot_path = run / manifest["artifacts"]["screenshot"]["path"]
            self.assertEqual(screenshot_path.read_bytes(), png_bytes)
            verified = classify.verified_observations(run, observations)
            self.assertIn(observations[0]["observation_id"], verified)

    def test_judge_verify_flags_content_sentinels_as_unavailable_with_reasons(self) -> None:
        # D3 regression: drive.py's own extension handlers return exit 0 with
        # valid JSON for several "nothing to show" cases — e.g.
        # getSemantics' `{"semantics": "semantics not available"}` when no
        # live accessibility tree exists, which is the common case on this
        # desktop build. A manifest claiming `availability.semantics: true`
        # over that sentinel must not happen.
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}

        def fake_command(args, **kwargs):
            if args[:5] == ["docker", "exec", "candidate", "python3", judge_verify.DRIVER]:
                action = args[5]
                if action == "contract":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"count": 1, "extensions": ["ext.nothingness.getPlaybackState"]}), "")
                if action == "inspect":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"router": {}}), "")  # missing "playback"
                if action == "tree":
                    return subprocess.CompletedProcess(args, 0, "no root element", "")
                if action == "call" and args[6] == "ext.nothingness.getSemantics":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"semantics": "semantics not available"}), "")
                if action == "call" and args[6] == "ext.nothingness.getSettings":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"screenType": "cassette"}), "")
                if action == "shoot":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"path": "shot"}), "")
            if args[:3] == ["docker", "exec", "candidate"] and args[3] == "cat" and args[4].endswith(".png"):
                return subprocess.CompletedProcess(args, 0, b"not a png", "")  # missing PNG magic
            if args[:5] == ["docker", "exec", "candidate", "test", "-f"]:
                return subprocess.CompletedProcess(args, 0, "", "")  # default flutter_run.log present
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}})
            with patch.object(judge_verify, "run_dir", return_value=run), patch.object(judge_verify, "read_host_pi_config", return_value=pi_config), patch.object(judge_verify, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-verify.py", "run", "--label", "sentinel-check"]):
                judge_verify.main()
            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            availability = observations[0]["availability"]
            self.assertEqual(availability, {"runtime": False, "tree": False, "semantics": False, "settings": True, "screenshot": False})
            manifest = common.read_json(run / observations[0]["evidence"])
            self.assertEqual(set(manifest["unavailable_reasons"]), {"runtime", "tree", "semantics", "screenshot"})
            self.assertEqual(manifest["discovery"]["method"], "default")
            # This observation recorded a genuine capture (settings), so it
            # still satisfies D2's "at least one real capture" gate — the
            # settings-only case is exercised separately from the "recorded
            # nothing at all" case in test_judge_review_rejects_a_verification_observation_that_captured_nothing.
            self.assertTrue(classify.has_genuine_capture({"kind": "verification", "availability": availability}))

    def test_judge_verify_discovers_via_scanned_non_default_log_when_default_is_unreachable(self) -> None:
        # The live bug this closes: the candidate launched `flutter run`
        # logging to its own path instead of the documented default, so
        # default discovery (and any cache scoped to the default log) finds
        # nothing live, but a candidate log IS live. Discovery must scan
        # `/tmp/flutter_run*.log`, newest first, and use the first one that
        # actually answers — consistently for all five captures.
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}
        png_bytes = b"\x89PNG\r\n\x1a\nfakepixels"
        winning_log = "/tmp/flutter_run_nothingness_linux_smoke4.log"
        dead_log = "/tmp/flutter_run_nothingness_linux_smoke3.log"
        seen_envs: set[str] = set()

        def parse_drive_call(args: list[str]):
            """`drive()` shapes its docker exec as `docker exec [-e K=V]... <container> python3 DRIVER <action> ...`
            with a variable number of `-e` pairs — parse that instead of
            assuming a fixed index, since this test (unlike the others in
            this file) exercises a non-empty env."""
            if args[:2] != ["docker", "exec"]:
                return None
            i, env = 2, {}
            while i + 1 < len(args) and args[i] == "-e":
                key, _, value = args[i + 1].partition("=")
                env[key] = value
                i += 2
            if args[i : i + 2] != ["candidate", "python3"] or args[i + 2] != judge_verify.DRIVER:
                return None
            return env, args[i + 3], args[i + 4 :]

        def fake_command(args, **kwargs):
            if args[:2] == ["docker", "exec"] and "sh" in args and "-c" in args:
                # `ls -t /tmp/flutter_run*.log` — newest first, dead log ahead
                # of the winner to prove discovery keeps trying past a miss.
                return subprocess.CompletedProcess(args, 0, f"{dead_log}\n{winning_log}\n", "")
            parsed = parse_drive_call(args)
            if parsed is not None:
                env, action, rest = parsed
                env_key = env.get("DRIVE_RUN_LOG", "")
                seen_envs.add(env_key)
                if action == "contract":
                    if env_key == winning_log:
                        return subprocess.CompletedProcess(args, 0, json.dumps({"count": 1, "extensions": []}), "")
                    return subprocess.CompletedProcess(args, 1, "", "error: could not find Dart VM service URI")
                if env_key != winning_log:
                    raise AssertionError(f"capture called with unexpected env: {args}")
                if action == "inspect":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"playback": {"isPlaying": True}}), "")
                if action == "tree":
                    return subprocess.CompletedProcess(args, 0, "Root\n  Child\n", "")
                if action == "call" and rest[0] == "ext.nothingness.getSemantics":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"semantics": "SemanticsNode#1(label: cassette)"}), "")
                if action == "call" and rest[0] == "ext.nothingness.getSettings":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"screenType": "cassette"}), "")
                if action == "shoot":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"path": "shot"}), "")
            if args[:3] == ["docker", "exec", "candidate"] and args[3] == "cat" and args[4].endswith(".png"):
                return subprocess.CompletedProcess(args, 0, png_bytes, "")
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}})
            with patch.object(judge_verify, "run_dir", return_value=run), patch.object(judge_verify, "read_host_pi_config", return_value=pi_config), patch.object(judge_verify, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-verify.py", "run", "--label", "scanned-log-check"]):
                judge_verify.main()

            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            self.assertTrue(all(observations[0]["availability"].values()))
            manifest = common.read_json(run / observations[0]["evidence"])
            self.assertEqual(manifest["discovery"], {"method": "scanned_log", "log_path": winning_log, "env": {"DRIVE_RUN_LOG": winning_log}})
            # Confirms all 5 captures (plus the discovery probes) consistently
            # used the winning env, never the dead candidate or bare default.
            self.assertEqual(seen_envs, {"", dead_log, winning_log})

    def test_judge_verify_reports_cache_discovery_when_default_log_absent_but_endpoint_answers(self) -> None:
        # drive.py's own `_resolve_ws` falls back to its cached websocket URI
        # when the default log has no fresh URI to scan. When that cache
        # still answers, discovery must say so as `method: "cache"` — not
        # falsely claim `"default"`, which would wrongly imply the default
        # log itself was live.
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}
        png_bytes = b"\x89PNG\r\n\x1a\nfakepixels"

        def fake_command(args, **kwargs):
            if args[:5] == ["docker", "exec", "candidate", "test", "-f"]:
                return subprocess.CompletedProcess(args, 1, "", "")  # default log absent
            if args[:5] == ["docker", "exec", "candidate", "python3", judge_verify.DRIVER]:
                action = args[5]
                if action == "contract":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"count": 1, "extensions": []}), "")
                if action == "inspect":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"playback": {"isPlaying": True}}), "")
                if action == "tree":
                    return subprocess.CompletedProcess(args, 0, "Root\n  Child\n", "")
                if action == "call" and args[6] == "ext.nothingness.getSemantics":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"semantics": "SemanticsNode#1(label: cassette)"}), "")
                if action == "call" and args[6] == "ext.nothingness.getSettings":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"screenType": "cassette"}), "")
                if action == "shoot":
                    return subprocess.CompletedProcess(args, 0, json.dumps({"path": "shot"}), "")
            if args[:3] == ["docker", "exec", "candidate"] and args[3] == "cat" and args[4].endswith(".png"):
                return subprocess.CompletedProcess(args, 0, png_bytes, "")
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}})
            with patch.object(judge_verify, "run_dir", return_value=run), patch.object(judge_verify, "read_host_pi_config", return_value=pi_config), patch.object(judge_verify, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-verify.py", "run", "--label", "cache-check"]):
                judge_verify.main()

            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            manifest = common.read_json(run / observations[0]["evidence"])
            self.assertEqual(manifest["discovery"], {"method": "cache", "log_path": None, "env": {}})

    def test_judge_verify_reports_honest_unavailability_when_no_live_app_is_found_anywhere(self) -> None:
        # Genuine "nothing is running" case: default discovery fails and the
        # log scan turns up nothing live either (no candidate logs at all).
        # All five artifacts must be reported unavailable with the SAME
        # distinct "no live app found" reason — never the per-capture
        # sentinel reasons, which would wrongly suggest a live app was found
        # but one particular lens failed — and no capture RPC should even be
        # attempted since discovery already knows they're doomed.
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}

        def fake_command(args, **kwargs):
            if args[:5] == ["docker", "exec", "candidate", "python3", judge_verify.DRIVER]:
                if args[5] == "contract":
                    return subprocess.CompletedProcess(args, 1, "", "error: could not find Dart VM service URI")
                raise AssertionError(f"no live app was found; no capture should have been attempted: {args}")
            if args[:2] == ["docker", "exec"] and "sh" in args and "-c" in args:
                return subprocess.CompletedProcess(args, 0, "", "")  # no flutter_run*.log at all
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}})
            with patch.object(judge_verify, "run_dir", return_value=run), patch.object(judge_verify, "read_host_pi_config", return_value=pi_config), patch.object(judge_verify, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-verify.py", "run", "--label", "no-app-check"]):
                judge_verify.main()

            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            availability = observations[0]["availability"]
            self.assertEqual(availability, {"runtime": False, "tree": False, "semantics": False, "settings": False, "screenshot": False})
            manifest = common.read_json(run / observations[0]["evidence"])
            self.assertEqual(manifest["discovery"], {"method": "unavailable", "log_path": None, "env": {}})
            self.assertEqual(set(manifest["unavailable_reasons"].values()), {judge_verify.NO_LIVE_APP_REASON})
            # Honest-unavailability behavior must be preserved: no genuine
            # capture at all means this observation must NOT satisfy the
            # judge-review "at least one real capture" gate.
            self.assertFalse(classify.has_genuine_capture({"kind": "verification", "availability": availability}))

    def test_judge_inspect_runtime_discovers_via_scanned_log_and_records_discovery(self) -> None:
        # Regression for the live bug: judge-inspect.py historically ran
        # `docker exec container python3 drive.py inspect` with no env
        # override, so it reported `{"available": false}` for a perfectly
        # live app whenever the candidate logged `flutter run` anywhere but
        # the default path — exactly what blocked classify-run.py's
        # validate_judge_review on the live campaign run. This exercises the
        # same discovery algorithm judge-verify.py uses (shared via
        # common.discover_drive_endpoint), reached here through
        # judge-inspect.py's own entry point.
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}
        winning_log = "/tmp/flutter_run_nothingness_linux_smoke4.log"

        def fake_command(args, **kwargs):
            if args[:2] == ["docker", "exec"] and "sh" in args and "-c" in args:
                return subprocess.CompletedProcess(args, 0, f"{winning_log}\n", "")
            # Bare default (no `-e` override): args = docker exec candidate python3 DRIVER <action> -- dead.
            if args[:5] == ["docker", "exec", "candidate", "python3", common.DRIVE_DRIVER]:
                return subprocess.CompletedProcess(args, 1, "", "error: could not find Dart VM service URI")
            # Scanned-log attempt: args = docker exec -e DRIVE_RUN_LOG=<winning_log> candidate python3 DRIVER <action>.
            if args[:8] == ["docker", "exec", "-e", f"DRIVE_RUN_LOG={winning_log}", "candidate", "python3", common.DRIVE_DRIVER, "contract"]:
                return subprocess.CompletedProcess(args, 0, json.dumps({"count": 1, "extensions": []}), "")
            if args[:8] == ["docker", "exec", "-e", f"DRIVE_RUN_LOG={winning_log}", "candidate", "python3", common.DRIVE_DRIVER, "inspect"]:
                return subprocess.CompletedProcess(args, 0, json.dumps({"playback": {"isPlaying": True}}), "")
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}, "novnc_url": None})
            with patch.object(judge_inspect, "run_dir", return_value=run), patch.object(judge_inspect, "read_host_pi_config", return_value=pi_config), patch.object(judge_inspect, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-inspect.py", "run", "--runtime"]):
                judge_inspect.main()

            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            self.assertEqual(len(observations), 1)
            snapshot = common.read_json(run / observations[0]["evidence"])
            # The real point of this test: the raw inspect payload came back
            # from the LIVE scanned log, not the dead default -- this is the
            # exact D-class bug (discovery finding nothing while the app is
            # alive), now fixed.
            self.assertEqual(snapshot["runtime"], {"playback": {"isPlaying": True}})
            self.assertEqual(snapshot["runtime_discovery"], {"method": "scanned_log", "log_path": winning_log, "env": {"DRIVE_RUN_LOG": winning_log}})

    def test_judge_inspect_reports_honest_unavailability_when_no_live_app_found(self) -> None:
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}

        def fake_command(args, **kwargs):
            if args[:5] == ["docker", "exec", "candidate", "python3", common.DRIVE_DRIVER]:
                if args[5] == "contract":
                    return subprocess.CompletedProcess(args, 1, "", "error: could not find Dart VM service URI")
                raise AssertionError(f"no live app was found; inspect should not have been attempted: {args}")
            if args[:2] == ["docker", "exec"] and "sh" in args and "-c" in args:
                return subprocess.CompletedProcess(args, 0, "", "")  # no flutter_run*.log at all
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}, "novnc_url": None})
            with patch.object(judge_inspect, "run_dir", return_value=run), patch.object(judge_inspect, "read_host_pi_config", return_value=pi_config), patch.object(judge_inspect, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-inspect.py", "run", "--runtime"]):
                judge_inspect.main()

            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            self.assertFalse(observations[0]["availability"]["runtime"])
            snapshot = common.read_json(run / observations[0]["evidence"])
            # Honest `{"available": false}` shape is preserved exactly as
            # before — the NEW information is `runtime_discovery`, which is
            # what lets a judge tell "no app anywhere" apart from "app found,
            # inspect itself failed".
            self.assertEqual(snapshot["runtime"], {"available": False})
            self.assertEqual(snapshot["runtime_discovery"]["method"], "unavailable")
            self.assertEqual(snapshot["runtime_discovery"]["reason"], common.DRIVE_NO_LIVE_APP_REASON)

    def test_judge_inspect_git_and_processes_do_not_trigger_drive_discovery(self) -> None:
        # Regression safety: discovery is runtime-specific plumbing. A
        # git/processes-only inspection must not pay for it or be blocked by
        # it -- no `drive.py`/`contract` docker exec should happen at all.
        fingerprints = {"auth.json": "a", "models.json": "b", "settings.json": "c"}
        pi_config = {"pi_config": {"auth": "{}", "models": "{}", "settings": "{}"}, "provider_env": {}, "config_fingerprints": fingerprints}

        def fake_command(args, **kwargs):
            if args[:4] == ["docker", "exec", "candidate", "git"]:
                return subprocess.CompletedProcess(args, 0, "", "")
            if args[:2] == ["docker", "top"]:
                return subprocess.CompletedProcess(args, 0, "PID PPID STAT ELAPSED COMMAND\n", "")
            raise AssertionError(f"unexpected call, discovery must not run without --runtime: {args}")

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            common.write_json(run / "run.json", {"container": "candidate", "selected_model": {"provider": "azure-openai-responses"}, "pi": {"config_fingerprints": fingerprints}, "novnc_url": None})
            with patch.object(judge_inspect, "run_dir", return_value=run), patch.object(judge_inspect, "read_host_pi_config", return_value=pi_config), patch.object(judge_inspect, "command", side_effect=fake_command), patch.object(sys, "argv", ["judge-inspect.py", "run", "--git", "--processes"]):
                judge_inspect.main()

            observations = [json.loads(line) for line in (run / "judge-observations.jsonl").read_text().splitlines()]
            self.assertNotIn("runtime", observations[0]["availability"] or {})
            snapshot = common.read_json(run / observations[0]["evidence"])
            self.assertNotIn("runtime", snapshot)
            self.assertNotIn("runtime_discovery", snapshot)

    def _build_verified_run(self, run: Path, task_id: str, delivered_ids: list[str]) -> None:
        requested = {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}
        # F1: the rubric hash must be frozen in run.json's rubric_contract at
        # "prepare" time, just like task_contract.manifest_sha256 — classify-run.py
        # now trusts *this* value, not one recomputed from the current file.
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        common.write_json(run / "run.json", {"requested_model": requested, "selected_model": requested, "fixture_commit": "fixture", "task_id": task_id, "task_contract": {"prompt": "task"}, "rubric_contract": {"manifest_sha256": common.sha256(rubric_path)}, "image": {"immutable_id": "image"}, "pi": {"config_fingerprints": {"a": "b"}}})
        common.write_json(run / "admission.json", {"identity_verified": True, "requested_model": requested, "selected_model": requested})
        # `model_identity_verified` here stands in for summarize-run.py's real
        # derivation from the candidate transcript's own served-model evidence
        # (see summarize-run.py's `served_model_of`/`model_identity_verified`);
        # this fixture doesn't run a real candidate session, so it asserts the
        # fact a genuine run would have proven for a matching transcript.
        common.write_json(run / "summary.json", {"cost_usd": {"admission": None, "candidate": None, "combined": None}, "candidate": {"tokens": 1}, "model_identity_verified": True})
        common.write_json(run / "interventions.json", [{"id": identifier, "timestamp": "t", "classification": "recovery", "mode": "steer", "message": "m", "reason": "r", "delivery": "delivered"} for identifier in delivered_ids])
        (run / "artifacts").mkdir()
        common.write_json(run / "artifacts" / "candidate-completion.json", {"timed_out": False, "reason": "judge_finish:done", "terminal_event_sequence": 8, "judge_finish_phase": "awaiting_judge"})
        (run / "artifacts" / "git-status.txt").write_text("")
        lifecycle_lines = "".join(json.dumps({"source": "judge_intervention", "event": {"id": identifier, "delivery": "delivered"}}) + "\n" for identifier in delivered_ids)
        (run / "artifacts" / "lifecycle.jsonl").write_text(lifecycle_lines)
        common.write_json(run / "artifacts" / "progress.json", {})

        def observation(observation_id: str, evidence: dict[str, object], **fields):
            path = run / f"{observation_id}.json"
            common.write_json(path, {"observation_id": observation_id, **evidence})
            return {"observation_id": observation_id, "evidence": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), **fields}

        events = observation("events-1", {"after": 0, "next_sequence": 8, "events": [{"sequence": sequence} for sequence in range(1, 9)]}, kind="events", after=0, next_sequence=8, event_count=8)
        inspection = observation("inspection-1", {"runtime": {"playback": {}}, "git": {"available": True}, "processes": {"available": True}}, kind="inspection", runtime=True, git=True, processes=True)
        # A realistic, fully-successful judge-verify.py capture — genuine
        # availability across all five lenses, not the placeholder
        # `{"label": "check"}` fixture (with no availability map at all) that
        # let a D1/D2 exploit stay green: every expectation's evidence_ref
        # could point at this one observation regardless of what it actually
        # captured, because nothing here was ever checked.
        verification = observation("verification-1", {"label": "check", "runtime": {"playback": {"isPlaying": True}}, "tree": "Root\n  Cassette\n", "semantics": {"semantics": "SemanticsNode#1(label: cassette)"}, "settings": {"screenType": "cassette"}, "screenshot": "screenshot.png"}, kind="verification", label="check", availability={"runtime": True, "tree": True, "semantics": True, "settings": True, "screenshot": True})
        with (run / "judge-observations.jsonl").open("w", encoding="utf-8") as handle:
            for item in (events, inspection, verification):
                handle.write(json.dumps(item) + "\n")

    def _scorecard_file(self, run: Path, task_id: str, expectations: list[dict[str, object]], *, rubric_sha256: str | None = None, scorecard_task_id: str | None = None) -> Path:
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        scorecard_path = run / "scorecard.json"
        scorecard_path.write_text(json.dumps({
            "task_id": scorecard_task_id if scorecard_task_id is not None else task_id,
            "rubric_sha256": rubric_sha256 if rubric_sha256 is not None else common.sha256(rubric_path),
            "expectations": expectations,
        }))
        return scorecard_path

    def _classify_with_scorecard(self, run: Path, scorecard: list[dict[str, object]]) -> dict[str, object]:
        task_id = common.read_json(run / "run.json")["task_id"]
        scorecard_path = self._scorecard_file(run, task_id, scorecard)
        arguments = ["classify-run.py", "run", "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed live", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
        with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
            classify.main()
        return common.read_json(run / "result.json")

    def test_non_t1_task_classifies_as_pass_partial_and_fail_from_its_rubric(self) -> None:
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "pass-run"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "ok", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]
            result = self._classify_with_scorecard(run, scorecard)
            self.assertEqual(result["outcome"], "pass")
            self.assertEqual(result["score"], 3)
            self.assertFalse(result["assisted"])

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "partial-run"
            run.mkdir()
            self._build_verified_run(run, task_id, ["judge-1"])
            secondary_ids = [identifier for identifier, value in expectations.items() if value["tier"] == "secondary"][:2]
            scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "unmet" if identifier in secondary_ids else "met", "note": "ok", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]
            result = self._classify_with_scorecard(run, scorecard)
            self.assertEqual(result["outcome"], "partial")
            self.assertIn(result["score"], (1, 2))
            self.assertTrue(result["assisted"])
            self.assertEqual(result["intervention_count"], 1)

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "fail-run"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "unmet", "note": "not there", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]
            result = self._classify_with_scorecard(run, scorecard)
            self.assertEqual(result["outcome"], "fail")
            self.assertEqual(result["score"], 0)

    def test_classify_rejects_a_valid_run_whose_candidate_transcript_never_verified_identity(self) -> None:
        # The core (a) regression test: classify-run.py used to hardcode
        # `model_identity_verified: True` unconditionally into result.json.
        # A `valid` run must now be rejected if summarize-run.py's own
        # transcript-derived check came back false -- e.g. the candidate
        # session crashed before completing a turn, or (the scenario that
        # actually matters) pi served a different model than requested.
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)
        scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "ok", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "unverified-identity-run"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            summary = common.read_json(run / "summary.json")
            summary["model_identity_verified"] = False
            common.write_json(run / "summary.json", summary)
            scorecard_path = self._scorecard_file(run, task_id, scorecard)
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit) as context:
                    classify.main()
            self.assertEqual(context.exception.code, 2)
            self.assertFalse((run / "result.json").is_file())

    def test_classify_rejects_a_valid_run_whose_admission_probe_never_verified_identity(self) -> None:
        # Same regression, the other independent evidence source: the
        # admission probe (preflight.py) is what actually calls pi before
        # launch and should hard-fail on a mismatch by never reaching
        # classify-run.py at all (fail(4) in preflight.py) -- but if a run
        # somehow reached classification with an admission.json that never
        # verified identity, classify-run.py must still refuse to call it valid.
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)
        scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "ok", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "unverified-admission-run"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            admission = common.read_json(run / "admission.json")
            admission["identity_verified"] = False
            common.write_json(run / "admission.json", admission)
            scorecard_path = self._scorecard_file(run, task_id, scorecard)
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit) as context:
                    classify.main()
            self.assertEqual(context.exception.code, 2)
            self.assertFalse((run / "result.json").is_file())

    def test_classify_records_honest_false_identity_for_invalid_infrastructure_runs(self) -> None:
        # An invalid_infrastructure run (e.g. preflight never even ran) has
        # no selected_model and no admission/summary evidence at all --
        # result.json must say so plainly (False), never hardcode True the
        # way it used to.
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary)
            common.write_json(run / "run.json", {"requested_model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}, "selected_model": None, "fixture_commit": "fixture", "task_id": "t1-playback-smoke-linux", "task_contract": {"prompt": "task"}, "image": {"immutable_id": "image"}, "pi": {"config_fingerprints": {}}})
            arguments = ["classify-run.py", str(run.name), "--validity", "invalid_infrastructure", "--notes", "container never started"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                classify.main()
            result = common.read_json(run / "result.json")
        self.assertEqual(result["validity"], "invalid_infrastructure")
        self.assertIsNone(result["selected_model"])
        self.assertFalse(result["model_identity_verified"])

    def test_scorecard_evidence_must_match_the_kind_the_rubric_declares(self) -> None:
        # D1 regression: qa-1 pointed every T2 expectation's evidence_ref at
        # an `inspection` (git/process) observation and got pass/3; qa-2 did
        # the same with a bare `events` sequence marker. Every T2 expectation
        # declares (or defaults to) `verification` — citing anything else must
        # be rejected, naming the offending expectation.
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)
        for wrong_kind, wrong_ref in (("inspection", "inspection-1"), ("events", "events-1")):
            with tempfile.TemporaryDirectory() as temporary:
                run = Path(temporary) / f"wrong-{wrong_kind}"
                run.mkdir()
                self._build_verified_run(run, task_id, [])
                scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": f"judged from {wrong_kind} alone, never looked at the app", "evidence_ref": wrong_ref} for identifier, value in expectations.items()]
                scorecard_path = self._scorecard_file(run, task_id, scorecard)
                arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
                with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                    with self.assertRaises(SystemExit):
                        classify.main()
                self.assertFalse((run / "result.json").is_file())

    def test_classify_rejects_scorecard_whose_rubric_hash_or_task_no_longer_matches(self) -> None:
        # D4 regression: qa-2 swapped a rubric expectation's statement after
        # building the scorecard against the original file and still got
        # pass/3, because only {id: tier} shape was compared, never the hash
        # the judge actually read. Simulated here without touching the real
        # rubric file: a scorecard claiming a stale hash, and one claiming
        # the wrong task, must both be rejected before scoring.
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)
        scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "ok", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "stale-hash"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            scorecard_path = self._scorecard_file(run, task_id, scorecard, rubric_sha256="0" * 64)
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit):
                    classify.main()
            self.assertFalse((run / "result.json").is_file())

        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "wrong-task"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            scorecard_path = self._scorecard_file(run, task_id, scorecard, scorecard_task_id="t1-playback-smoke-linux")
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit):
                    classify.main()
            self.assertFalse((run / "result.json").is_file())

    def test_classify_rejects_a_rubric_that_drifted_since_prepare_even_if_the_scorecard_agrees_with_the_current_file(self) -> None:
        # F1 regression: the previous control recomputed the rubric hash from
        # disk at scoring time and compared it only against the scorecard's
        # own self-declared field — both written by the same actor at the
        # same time, so a judge who edits the rubric and then re-hashes it
        # for the scorecard sails through. The real fix anchors to a hash
        # frozen in run.json's rubric_contract *before the candidate ever saw
        # the prompt* (mirroring task_contract.manifest_sha256). This
        # simulates "the file drifted after prepare" without touching the
        # real rubric file: run.json claims a frozen hash that does NOT
        # match the current file, while the scorecard's declared hash DOES
        # match the current (drifted) file — exactly the shape of qa-2's
        # exploit. It must still be rejected, because the frozen value in
        # run.json, not the current file, is authoritative.
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        current_hash = common.sha256(rubric_path)
        expectations = classify.rubric_expectations(rubric_path)
        scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "ok", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "drifted-rubric"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            drifted = common.read_json(run / "run.json")
            drifted["rubric_contract"] = {"manifest_sha256": "1" * 64}  # frozen at a stale value
            common.write_json(run / "run.json", drifted)
            scorecard_path = self._scorecard_file(run, task_id, scorecard, rubric_sha256=current_hash)  # judge re-hashed the (in this simulation, drifted) current file
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit) as context:
                    classify.main()
            self.assertEqual(context.exception.code, 4)
            self.assertFalse((run / "result.json").is_file())

    def test_scorecard_evidence_check_applies_per_entry_not_just_to_the_aggregate_citation(self) -> None:
        # F2 regression, qa-1's exploit: has_genuine_capture was checked once
        # against the aggregate --observation-id list, decoupled from what
        # any individual scorecard entry cited. A genuine verification
        # observation was cited via --observation-id purely to satisfy that
        # aggregate gate, while every scorecard entry's own evidence_ref
        # pointed at a second, wholly-empty verification observation. That
        # must now be rejected per entry.
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            # A second, wholly-empty verification observation, appended
            # alongside the genuine "verification-1" the fixture already
            # provides (which stays cited via --observation-id to satisfy
            # the aggregate "judge looked at all" gate).
            empty_path = run / "verification-empty.json"
            common.write_json(empty_path, {"observation_id": "verification-empty", "label": "check"})
            empty_ledger_entry = {"observation_id": "verification-empty", "kind": "verification", "label": "check", "availability": {"runtime": False, "tree": False, "semantics": False, "settings": False, "screenshot": False}, "evidence": empty_path.name, "sha256": hashlib.sha256(empty_path.read_bytes()).hexdigest()}
            with (run / "judge-observations.jsonl").open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(empty_ledger_entry) + "\n")
            scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "judged from the empty observation", "evidence_ref": "verification-empty"} for identifier, value in expectations.items()]
            scorecard_path = self._scorecard_file(run, task_id, scorecard)
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit):
                    classify.main()
            self.assertFalse((run / "result.json").is_file())

    def test_screenshot_only_expectation_rejects_evidence_missing_the_screenshot_lens(self) -> None:
        # F2 regression, qa-2's exploit: an observation where only `runtime`
        # succeeded was cited as evidence for T2/E5 ("The required screenshot
        # was actually captured and is on-point") and scored met/pass. E5 now
        # declares `**Evidence:** verification:screenshot`, so a runtime-only
        # capture must be rejected specifically for E5 — while remaining
        # acceptable for an expectation that only needs *some* genuine
        # capture (contrast case, same observation, different expectation).
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)
        self.assertEqual(expectations["E5"]["lens"], "screenshot")
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            runtime_only_path = run / "verification-runtime-only.json"
            common.write_json(runtime_only_path, {"observation_id": "verification-runtime-only", "label": "check"})
            runtime_only_entry = {"observation_id": "verification-runtime-only", "kind": "verification", "label": "check", "availability": {"runtime": True, "tree": False, "semantics": False, "settings": False, "screenshot": False}, "evidence": runtime_only_path.name, "sha256": hashlib.sha256(runtime_only_path.read_bytes()).hexdigest()}
            with (run / "judge-observations.jsonl").open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(runtime_only_entry) + "\n")
            scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "judged from a runtime-only capture", "evidence_ref": "verification-runtime-only"} for identifier, value in expectations.items()]
            scorecard_path = self._scorecard_file(run, task_id, scorecard)
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit):
                    classify.main()
            self.assertFalse((run / "result.json").is_file())

        # Contrast: the same runtime-only observation legitimately settles an
        # unqualified `verification` expectation (E1), which only needs *some*
        # genuine capture — proving the rejection above is E5's lens
        # requirement specifically, not a blanket rejection of this observation.
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            self._build_verified_run(run, task_id, [])
            runtime_only_path = run / "verification-runtime-only.json"
            common.write_json(runtime_only_path, {"observation_id": "verification-runtime-only", "label": "check"})
            runtime_only_entry = {"observation_id": "verification-runtime-only", "kind": "verification", "label": "check", "availability": {"runtime": True, "tree": False, "semantics": False, "settings": False, "screenshot": False}, "evidence": runtime_only_path.name, "sha256": hashlib.sha256(runtime_only_path.read_bytes()).hexdigest()}
            with (run / "judge-observations.jsonl").open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(runtime_only_entry) + "\n")
            self.assertIsNone(expectations["E1"]["lens"])
            scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "ok", "evidence_ref": "verification-runtime-only" if identifier == "E1" else "verification-1"} for identifier, value in expectations.items()]
            result = self._classify_with_scorecard(run, scorecard)
            self.assertEqual(result["outcome"], "pass")

    def test_prepare_run_fails_cleanly_for_a_task_with_no_rubric_yet(self) -> None:
        # F1: a task that cannot be scored must not be launched. This used to
        # exercise T3, which had no rubric yet at the time; WP7 has since
        # written rubrics for all seven real tasks, so that premise no longer
        # holds against the committed tree. Restored here with a
        # self-contained fake suite + task under a temporary ROOT instead of
        # relying on (or, worse, deleting) any committed file: same code path
        # — prepare-run.py's real main(), the real rubric gate — against a
        # task id that genuinely has no rubric on disk and can never
        # accidentally grow one later.
        prepare_run = load_script("prepare-run.py")
        task_id = "t9-no-such-rubric-linux"
        with tempfile.TemporaryDirectory() as temporary:
            fake_root = Path(temporary)
            suite_id = "fake-suite-no-rubric-test"
            suite_path = fake_root / "evals" / "suites" / "fake-suite.json"
            common.write_json(suite_path, {"schema_version": 1, "id": suite_id, "requested_model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}, "tasks": [{"id": task_id, "valid_trials": 1}]})
            common.write_json(fake_root / "evals" / "tasks" / f"{task_id}.json", {"id": task_id, "fixture_commit": "5fc7e04", "scoring": {"mode": "rubric"}})
            rubric_path = fake_root / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
            self.assertFalse(rubric_path.is_file(), "fixture setup must not accidentally create the rubric")
            run_id = f"{suite_id}-{task_id}-calibration-attempt-01"
            run = common.run_dir(run_id)
            self.assertFalse(run.exists())
            arguments = ["prepare-run.py", task_id, run_id, "--suite", str(suite_path), "--trial", "1", "--calibration"]
            with patch.object(common, "ROOT", fake_root), patch.object(prepare_run, "ROOT", fake_root), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit) as context:
                    prepare_run.main()
            self.assertEqual(context.exception.code, 2)
            self.assertFalse(run.exists(), "must fail before creating the run directory")

    def test_prepare_run_does_not_block_a_task_that_has_a_rubric(self) -> None:
        # Contrast to the T3 case above: T2 has a rubric, so prepare-run.py's
        # new rubric gate must not be what stops main() from proceeding.
        # `resolve_pi` — the next real step, needing host pi/docker state
        # that's out of scope for this test tier — is stubbed to fail with a
        # distinct, controlled exit code, so this can tell "blocked by the
        # rubric gate" (exit 2, rubric_not_found) apart from "got past it."
        # No real docker/pi call happens: resolve_pi is replaced before
        # main() ever reaches it.
        prepare_run = load_script("prepare-run.py")
        suite_path = ROOT / "evals" / "suites" / "t1-t7-gpt-5.4-nano-medium.json"
        task_id = "t2-settings-placement-linux"
        suite_id = json.loads(suite_path.read_text())["id"]
        run_id = f"{suite_id}-{task_id}-calibration-attempt-99"
        arguments = ["prepare-run.py", task_id, run_id, "--suite", str(suite_path), "--trial", "1", "--calibration"]
        with patch.object(prepare_run, "resolve_pi", side_effect=SystemExit(97)), patch.object(sys, "argv", arguments):
            with self.assertRaises(SystemExit) as context:
                prepare_run.main()
        self.assertEqual(context.exception.code, 97)

    def test_validate_frozen_rubric_distinguishes_missing_from_changed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            rubric_path = Path(temporary) / "task.md"
            rubric_path.write_text("## Required expectations\n\n### E1\n**Statement:** x\n")
            frozen = {"rubric_contract": {"manifest_sha256": common.sha256(rubric_path)}}
            common.validate_frozen_rubric(frozen, rubric_path)  # no raise: matches
            with self.assertRaises(SystemExit) as missing:
                common.validate_frozen_rubric(frozen, Path(temporary) / "does-not-exist.md")
            self.assertEqual(missing.exception.code, 2)
            rubric_path.write_text("## Required expectations\n\n### E1\n**Statement:** changed\n")
            with self.assertRaises(SystemExit) as changed:
                common.validate_frozen_rubric(frozen, rubric_path)
            self.assertEqual(changed.exception.code, 4)
            with self.assertRaises(SystemExit) as no_contract:
                common.validate_frozen_rubric({}, rubric_path)
            self.assertEqual(no_contract.exception.code, 4)

    def test_classify_gives_a_clean_error_for_a_missing_rubric_not_a_traceback(self) -> None:
        # F3: classify-run.py must not let a raw FileNotFoundError escape when
        # the rubric named by run.json's frozen contract doesn't exist.
        task_id = "t9-no-such-rubric-linux"
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            self._build_verified_run(run, "t2-settings-placement-linux", [])
            metadata = common.read_json(run / "run.json")
            metadata["task_id"] = task_id
            metadata["rubric_contract"] = {"manifest_sha256": "0" * 64}
            common.write_json(run / "run.json", metadata)
            scorecard_path = run / "scorecard.json"
            scorecard_path.write_text(json.dumps({"task_id": task_id, "rubric_sha256": "0" * 64, "expectations": []}))
            arguments = ["classify-run.py", str(run.name), "--validity", "valid", "--scorecard", str(scorecard_path), "--notes", "reviewed", "--observation-id", "events-1", "--observation-id", "inspection-1", "--observation-id", "verification-1"]
            with patch.object(classify, "run_dir", return_value=run), patch.object(sys, "argv", arguments):
                with self.assertRaises(SystemExit) as context:
                    classify.main()
            self.assertEqual(context.exception.code, 2)

    def test_judge_run_decide_forwards_scorecard_to_classify_run_end_to_end(self) -> None:
        # Regression test for judge-run.py's `decide` still building the old
        # --outcome/--score classify-run.py invocation instead of --scorecard.
        # This deliberately does NOT mock classify-run.py or `command`: it lets
        # `judge_run.decide` shell out to the real classify-run.py script (no
        # docker involved, so this is safe) to prove the two scripts' CLIs
        # actually agree with each other, not just that each is internally
        # consistent. The run directory is uniquely named per invocation
        # (a reviewer hit `OSError: Directory not empty` with a fixed name
        # under concurrent test activity).
        task_id = "t2-settings-placement-linux"
        rubric_path = ROOT / "evals" / "tasks" / "rubrics" / f"{task_id}.md"
        expectations = classify.rubric_expectations(rubric_path)
        run_id = f"wp3-judge-run-decide-end-to-end-{uuid.uuid4().hex[:12]}"
        run = common.run_dir(run_id)
        if run.exists():
            shutil.rmtree(run)
        run.mkdir(parents=True)
        try:
            self._build_verified_run(run, task_id, [])
            scorecard = [{"id": identifier, "tier": value["tier"], "verdict": "met", "note": "ok", "evidence_ref": "verification-1"} for identifier, value in expectations.items()]
            scorecard_path = self._scorecard_file(run, task_id, scorecard)
            arguments = argparse.Namespace(run_id=run_id, validity="valid", scorecard=str(scorecard_path), notes="reviewed live", observation_id=["events-1", "inspection-1", "verification-1"])
            judge_run.decide(arguments)
            result = common.read_json(run / "result.json")
            self.assertEqual(result["outcome"], "pass")
            self.assertEqual(result["score"], 3)
        finally:
            shutil.rmtree(run, ignore_errors=True)

    def test_campaign_records_ordered_tasks_and_per_task_run_ids_without_deciding(self) -> None:
        task_ids = [f"t{n}-task-linux" for n in range(1, 8)]
        suite = {"id": "suite-x", "requested_model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}, "tasks": [{"id": task_id, "valid_trials": 1} for task_id in task_ids]}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            suite_path = root / "suite.json"
            suite_path.write_text(json.dumps(suite))
            campaigns_root = root / "campaigns"
            with patch.object(campaign, "CAMPAIGNS_ROOT", campaigns_root), patch.object(campaign, "load_suite", return_value=suite):
                with patch.object(sys, "argv", ["campaign.py", "new", str(suite_path), "--campaign-id", "camp-1"]):
                    campaign.main()
                with self.assertRaises(SystemExit), patch.object(sys, "argv", ["campaign.py", "new", str(suite_path), "--campaign-id", "camp-1"]):
                    campaign.main()
                with patch.object(sys, "argv", ["campaign.py", "add-run", "camp-1", task_ids[0], "run-1"]):
                    campaign.main()
                with patch.object(sys, "argv", ["campaign.py", "add-run", "camp-1", task_ids[0], "run-2"]):
                    campaign.main()
                with self.assertRaises(SystemExit), patch.object(sys, "argv", ["campaign.py", "add-run", "camp-1", "not-a-real-task", "run-3"]):
                    campaign.main()
                with self.assertRaises(SystemExit), patch.object(sys, "argv", ["campaign.py", "add-run", "camp-1", task_ids[0], "run-1"]):
                    campaign.main()
                with self.assertRaises(SystemExit), patch.object(sys, "argv", ["campaign.py", "status", "no-such-campaign"]):
                    campaign.main()
                state = campaign.load_campaign("camp-1")
            self.assertEqual(state["tasks"], task_ids)
            self.assertEqual(state["runs"][task_ids[0]], ["run-1", "run-2"])
            self.assertEqual(state["runs"][task_ids[1]], [])
            self.assertEqual(state["model"], suite["requested_model"])

    def test_judge_wall_seconds_is_prepare_plus_candidate_budget_plus_score(self) -> None:
        self.assertEqual(campaign.judge_wall_seconds(1800), 3600)
        self.assertEqual(campaign.judge_wall_seconds(2700), 4500)
        self.assertEqual(campaign.judge_wall_seconds(1200), 3000)
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            campaign.judge_wall_seconds(0)

    def test_campaign_next_prints_judge_wall_from_the_task_budget(self) -> None:
        suite = {
            "id": "suite-wall",
            "requested_model": {"provider": "azure-openai-responses", "model": "gpt-5.4-nano", "thinking": "medium"},
            "tasks": [{"id": "t4-swipe-to-seek-linux"}, {"id": "t7-opus-shuffled-playlist-linux"}],
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            suite_path = root / "suite.json"
            suite_path.write_text(json.dumps(suite))
            campaigns_root = root / "campaigns"
            runs_root = root / "runs"
            with patch.object(campaign, "CAMPAIGNS_ROOT", campaigns_root), patch.object(campaign, "RUNS_ROOT", runs_root), patch.object(campaign, "load_suite", return_value=suite):
                with patch.object(sys, "argv", ["campaign.py", "new", str(suite_path), "--campaign-id", "camp-wall"]):
                    campaign.main()
                buffer = io.StringIO()
                with contextlib.redirect_stdout(buffer), patch.object(sys, "argv", ["campaign.py", "next", "camp-wall"]):
                    campaign.main()
        payload = json.loads(buffer.getvalue())
        self.assertEqual(payload["task_id"], "t4-swipe-to-seek-linux")
        self.assertEqual(payload["timeout_seconds"], 1800)
        self.assertEqual(payload["judge_wall_seconds"], 3600)

    def test_campaign_dashboard_renders_seven_task_rows_with_unknown_cost_and_no_percentage(self) -> None:
        task_ids = [f"t{n}-task-linux" for n in range(1, 8)]
        suite_id = "suite-seven"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runs_root = root / "runs"
            campaigns_root = root / "campaigns"
            write_fixture_run(
                runs_root,
                "run-t1",
                suite_id,
                task_ids[0],
                progress={"phase": "completed", "elapsed_seconds": 192, "timeout_seconds": 1200, "tool_calls": 42, "tokens": {"totalTokens": 5213}, "cost_usd": 0.026, "last_activity": "candidate completed", "last_activity_at": "2026-01-01T00:05:00Z"},
                result={"validity": "valid", "outcome": "unassisted_pass", "score": 3},
                summary={"cost_usd": {"candidate": 0.026}, "candidate": {"usage": {"aggregate": {"tokens": {"total": 5213}}}}},
                admission={"normalized_usage": {"cost_usd": {"total": 0.0004}, "tokens": {"total": 88}}},
            )
            write_fixture_run(
                runs_root,
                "run-t2",
                suite_id,
                task_ids[1],
                progress={"phase": "completed", "elapsed_seconds": 340, "timeout_seconds": 1200, "tool_calls": 25, "tokens": {"totalTokens": 3210}, "cost_usd": None, "last_activity": "candidate completed", "last_activity_at": "2026-01-01T00:10:00Z"},
                result={"validity": "valid", "outcome": "assisted_pass", "score": 2},
            )
            common.write_json(campaigns_root / "camp-seven" / "campaign.json", {"schema_version": 1, "campaign_id": "camp-seven", "suite_id": suite_id, "model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}, "tasks": task_ids, "runs": {task_ids[0]: ["run-t1"], task_ids[1]: ["run-t2"], **{task_id: [] for task_id in task_ids[2:]}}, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:10:00Z"})
            with patch.object(watch, "RUNS_ROOT", runs_root), patch.object(watch, "CAMPAIGNS_ROOT", campaigns_root), patch.object(watch, "command", return_value=subprocess.CompletedProcess([], 1, "", "")):
                display, finished = watch.render("camp-seven")
        lines = display.splitlines()
        task_lines = [line for line in lines if any(line.startswith(task_id) for task_id in task_ids)]
        self.assertEqual(len(task_lines), 7)
        self.assertEqual([line.split()[0] for line in task_lines], task_ids)
        self.assertIn("unknown", task_lines[1])
        self.assertIn("not started", task_lines[2])
        self.assertFalse(finished)
        self.assertNotIn("%", display)

    def test_campaign_dashboard_token_totals_propagate_unknown_independent_of_known_cost(self) -> None:
        task_ids = [f"t{n}-task-linux" for n in range(1, 8)]
        suite_id = "suite-tokens"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runs_root = root / "runs"
            campaigns_root = root / "campaigns"
            write_fixture_run(
                runs_root,
                "run-t1",
                suite_id,
                task_ids[0],
                progress={"phase": "completed", "elapsed_seconds": 192, "timeout_seconds": 1200, "tool_calls": 42, "tokens": {"totalTokens": 5213}, "cost_usd": 0.026, "last_activity": "candidate completed", "last_activity_at": "2026-01-01T00:05:00Z"},
                result={"validity": "valid", "outcome": "unassisted_pass", "score": 3},
                summary={"cost_usd": {"candidate": 0.026}, "candidate": {"usage": {"aggregate": {"tokens": {"total": 5213}}}}},
                admission={"normalized_usage": {"cost_usd": {"total": 0.0004}, "tokens": {"total": 88}}},
            )
            # run-t2 has a fully known cost (candidate + admission cost both present) but its
            # admission record omits token usage entirely, so the token component is genuinely
            # unknown even though the cost component is not. This must not be zero-filled, and
            # it must not be masked by the fact that cost happens to be known for this same row.
            write_fixture_run(
                runs_root,
                "run-t2",
                suite_id,
                task_ids[1],
                progress={"phase": "completed", "elapsed_seconds": 300, "timeout_seconds": 1200, "tool_calls": 20, "tokens": {"totalTokens": 4000}, "cost_usd": 0.02, "last_activity": "candidate completed", "last_activity_at": "2026-01-01T00:06:00Z"},
                result={"validity": "valid", "outcome": "assisted_pass", "score": 2},
                summary={"cost_usd": {"candidate": 0.02}, "candidate": {"usage": {"aggregate": {"tokens": {"total": 4000}}}}},
                admission={"normalized_usage": {"cost_usd": {"total": 0.0004}}},
            )
            common.write_json(campaigns_root / "camp-tokens" / "campaign.json", {"schema_version": 1, "campaign_id": "camp-tokens", "suite_id": suite_id, "model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}, "tasks": task_ids, "runs": {task_ids[0]: ["run-t1"], task_ids[1]: ["run-t2"], **{task_id: [] for task_id in task_ids[2:]}}, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:06:00Z"})
            with patch.object(watch, "RUNS_ROOT", runs_root), patch.object(watch, "CAMPAIGNS_ROOT", campaigns_root), patch.object(watch, "command", return_value=subprocess.CompletedProcess([], 1, "", "")):
                display, finished = watch.render("camp-tokens")
        lines = display.splitlines()
        task_lines = [line for line in lines if any(line.startswith(task_id) for task_id in task_ids)]
        totals_line = next(line for line in lines if line.startswith("Totals"))
        columns_t1 = task_lines[0].split()
        columns_t2 = task_lines[1].split()
        self.assertEqual(columns_t1[5], "5,301")
        self.assertEqual(columns_t1[6], "$0.0264")
        self.assertEqual(columns_t2[5], "unknown")
        self.assertEqual(columns_t2[6], "$0.0204")
        self.assertIn("unknown tokens", totals_line)
        self.assertIn("$0.0468", totals_line)
        self.assertFalse(finished)

    def _write_image_sources(self, root: Path) -> Path:
        image_dir = root / "evals" / "image"
        image_dir.mkdir(parents=True)
        for name in common.IMAGE_SOURCE_FILES:
            (image_dir / name).write_text(f"content of {name}")
        return image_dir

    def test_image_source_hash_changes_only_for_the_file_that_actually_changed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image_dir = self._write_image_sources(root)
            hashes = common.image_source_hashes(root)
            baseline = common.image_source_sha256(hashes)
            # The bug this whole feature exists to catch: an edit lands in
            # candidate.py (e.g. adding `served_model` capture) -- the combined
            # digest must move, but every other file's own hash must stay put
            # so a mismatch can name exactly which file drifted.
            (image_dir / "candidate.py").write_text("served_model added after the image was built")
            mutated = common.image_source_hashes(root)
            self.assertNotEqual(common.image_source_sha256(mutated), baseline)
            self.assertNotEqual(mutated["candidate.py"], hashes["candidate.py"])
            for name in common.IMAGE_SOURCE_FILES:
                if name != "candidate.py":
                    self.assertEqual(mutated[name], hashes[name])

    def test_validate_image_matches_sources_accepts_a_matching_image_and_returns_its_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._write_image_sources(root)
            hashes = common.image_source_hashes(root)
            expected = common.image_source_sha256(hashes)
            labels = {common.IMAGE_SOURCE_HASH_LABEL: expected, common.IMAGE_SOURCE_MANIFEST_LABEL: json.dumps(hashes)}
            self.assertEqual(common.validate_image_matches_sources(labels, root), expected)

    def test_validate_image_matches_sources_rejects_a_stale_image_naming_the_changed_file(self) -> None:
        # This is the exact scenario from the incident: candidate.py was
        # edited on the host *after* the image baked its labels, so the image
        # still runs the old code. `run_id`/`prepare-run.py` must refuse this
        # before a single container is created, and the operator must be able
        # to tell from the message alone which file drifted and what to do.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image_dir = self._write_image_sources(root)
            hashes = common.image_source_hashes(root)
            labels = {common.IMAGE_SOURCE_HASH_LABEL: common.image_source_sha256(hashes), common.IMAGE_SOURCE_MANIFEST_LABEL: json.dumps(hashes)}
            (image_dir / "candidate.py").write_text("served_model added after the image was built")
            buffer = io.StringIO()
            with contextlib.redirect_stderr(buffer), self.assertRaises(SystemExit) as context:
                common.validate_image_matches_sources(labels, root)
            self.assertEqual(context.exception.code, 4)
            reason = json.loads(buffer.getvalue())["reason"]
            self.assertIn("image_stale_vs_sources", reason)
            self.assertIn("candidate.py", reason)
            self.assertNotIn("pi.py", reason)
            self.assertIn("verify-offline-baseline.py --build-image", reason)

    def test_validate_image_matches_sources_fails_closed_when_the_image_has_no_baked_label(self) -> None:
        # An image built before this check existed (or with build-image.py
        # bypassed) has no baseline to trust it against -- it must fail
        # exactly like a genuine mismatch, never be waved through as
        # "unverifiable, therefore fine".
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._write_image_sources(root)
            with self.assertRaises(SystemExit) as context:
                common.validate_image_matches_sources({}, root)
            self.assertEqual(context.exception.code, 4)

    def test_build_image_bakes_the_current_source_hash_and_per_file_manifest_as_labels(self) -> None:
        hashes = {name: f"hash-{name}" for name in common.IMAGE_SOURCE_FILES}
        arguments = build_image.source_labels(hashes)
        self.assertEqual(arguments.count("--label"), 2)
        hash_label = next(item for item in arguments if item.startswith(f"{common.IMAGE_SOURCE_HASH_LABEL}="))
        manifest_label = next(item for item in arguments if item.startswith(f"{common.IMAGE_SOURCE_MANIFEST_LABEL}="))
        self.assertEqual(hash_label, f"{common.IMAGE_SOURCE_HASH_LABEL}={common.image_source_sha256(hashes)}")
        self.assertEqual(json.loads(manifest_label.split("=", 1)[1]), hashes)

    def test_admission_probe_process_failure_is_distinguished_from_a_provider_rejection(self) -> None:
        probe = subprocess.CompletedProcess(["docker"], 1, "", "")
        probe_result = subprocess.CompletedProcess(["docker"], 0, "{}", "")
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer), self.assertRaises(SystemExit) as context:
            preflight.evaluate_admission_probe(probe, probe_result)
        self.assertEqual(context.exception.code, 4)
        self.assertEqual(json.loads(buffer.getvalue())["reason"], "admission_probe_process_failed:exit=1")

    def test_missing_or_unparseable_result_json_is_distinguished_from_a_provider_rejection(self) -> None:
        probe = subprocess.CompletedProcess(["docker"], 0, "", "")
        missing = subprocess.CompletedProcess(["docker"], 1, "", "")
        with self.assertRaises(SystemExit) as context:
            preflight.evaluate_admission_probe(probe, missing)
        self.assertEqual(context.exception.code, 4)
        unparseable = subprocess.CompletedProcess(["docker"], 0, "not json", "")
        with self.assertRaises(SystemExit) as context:
            preflight.evaluate_admission_probe(probe, unparseable)
        self.assertEqual(context.exception.code, 4)

    def test_probe_reported_ok_false_is_the_genuine_provider_rejection_with_its_own_detail(self) -> None:
        probe = subprocess.CompletedProcess(["docker"], 0, "", "")
        rejected = json.dumps({"ok": False, "exit_code": 1, "stop_reason": "error", "text": "insufficient_quota"})
        probe_result = subprocess.CompletedProcess(["docker"], 0, rejected, "")
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer), self.assertRaises(SystemExit) as context:
            preflight.evaluate_admission_probe(probe, probe_result)
        self.assertEqual(context.exception.code, 4)
        reason = json.loads(buffer.getvalue())["reason"]
        self.assertTrue(reason.startswith("admission_rejected:"))
        self.assertIn("insufficient_quota", reason)

    def test_probe_timeout_or_decode_error_is_still_reported_as_a_genuine_rejection(self) -> None:
        # candidate.py's run_probe except branch writes only {"ok": False,
        # "elapsed_ms": ...} with none of exit_code/stop_reason/text -- there
        # must still be a usable, non-empty detail rather than an empty string.
        probe = subprocess.CompletedProcess(["docker"], 0, "", "")
        timed_out = json.dumps({"ok": False, "elapsed_ms": 60000})
        probe_result = subprocess.CompletedProcess(["docker"], 0, timed_out, "")
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer), self.assertRaises(SystemExit):
            preflight.evaluate_admission_probe(probe, probe_result)
        reason = json.loads(buffer.getvalue())["reason"]
        self.assertEqual(reason, "admission_rejected:probe_timed_out_or_output_undecodable")

    def test_missing_usage_is_flagged_as_our_own_contract_violation(self) -> None:
        probe = subprocess.CompletedProcess(["docker"], 0, "", "")
        result = json.dumps({"ok": True, "served_model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini"}})
        probe_result = subprocess.CompletedProcess(["docker"], 0, result, "")
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer), self.assertRaises(SystemExit) as context:
            preflight.evaluate_admission_probe(probe, probe_result)
        self.assertEqual(context.exception.code, 4)
        self.assertEqual(json.loads(buffer.getvalue())["reason"], "admission_usage_missing")

    def test_missing_served_model_is_flagged_as_our_own_contract_violation_not_a_provider_rejection(self) -> None:
        # This is the exact regression under repair: a stale image running an
        # older candidate.py that never emitted `served_model` must not be
        # reported as the old catch-all `pi_admission_failed` -- which reads
        # as "the provider rejected us" and sends an operator to check Azure
        # credentials for a defect that is entirely on our own side.
        probe = subprocess.CompletedProcess(["docker"], 0, "", "")
        result = json.dumps({"ok": True, "usage": {"totalTokens": 10}})
        probe_result = subprocess.CompletedProcess(["docker"], 0, result, "")
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer), self.assertRaises(SystemExit) as context:
            preflight.evaluate_admission_probe(probe, probe_result)
        self.assertEqual(context.exception.code, 4)
        reason = json.loads(buffer.getvalue())["reason"]
        self.assertEqual(reason, "admission_served_model_missing")
        self.assertNotIn("pi_admission_failed", reason)

    def test_evaluate_admission_probe_returns_the_parsed_triple_on_genuine_success(self) -> None:
        served = {"provider": "azure-openai-responses", "model": "gpt-5.4-mini"}
        probe = subprocess.CompletedProcess(["docker"], 0, "", "")
        result = json.dumps({"ok": True, "usage": {"totalTokens": 10}, "served_model": served})
        probe_result = subprocess.CompletedProcess(["docker"], 0, result, "")
        raw_admission, usage, served_out = preflight.evaluate_admission_probe(probe, probe_result)
        self.assertTrue(raw_admission["ok"])
        self.assertEqual(usage, {"totalTokens": 10})
        self.assertEqual(served_out, served)

    def test_campaign_dashboard_reflects_task_transition_without_mutating_recorded_state(self) -> None:
        task_ids = [f"t{n}-task-linux" for n in range(1, 8)]
        suite_id = "suite-transition"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runs_root = root / "runs"
            campaigns_root = root / "campaigns"
            write_fixture_run(runs_root, "run-t1", suite_id, task_ids[0], progress={"phase": "running", "started_at_unix": 0, "timeout_seconds": 1200, "tool_calls": 3, "tokens": {"totalTokens": 100}, "cost_usd": None, "last_activity": "tool call: bash", "last_activity_at": "2026-01-01T00:01:00Z"})
            campaign_path = campaigns_root / "camp-t" / "campaign.json"
            common.write_json(campaign_path, {"schema_version": 1, "campaign_id": "camp-t", "suite_id": suite_id, "model": {"provider": "azure-openai-responses", "model": "gpt-5.4-mini", "thinking": "medium"}, "tasks": task_ids, "runs": {task_ids[0]: ["run-t1"], **{task_id: [] for task_id in task_ids[1:]}}, "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"})
            before_digest = hashlib.sha256(campaign_path.read_bytes()).hexdigest()
            with patch.object(watch, "RUNS_ROOT", runs_root), patch.object(watch, "CAMPAIGNS_ROOT", campaigns_root), patch.object(watch, "command", return_value=subprocess.CompletedProcess([], 1, "", "")):
                before_display, before_finished = watch.render("camp-t")
                task_line = next(line for line in before_display.splitlines() if line.startswith(task_ids[0]))
                self.assertIn("RUNNING", task_line)
                self.assertFalse(before_finished)
                (runs_root / "run-t1" / "artifacts" / "progress.json").write_text(json.dumps({"phase": "completed", "elapsed_seconds": 90, "timeout_seconds": 1200, "tool_calls": 6, "tokens": {"totalTokens": 400}, "cost_usd": 0.01, "last_activity": "candidate completed", "last_activity_at": "2026-01-01T00:02:00Z"}))
                (runs_root / "run-t1" / "result.json").write_text(json.dumps({"validity": "valid", "outcome": "unassisted_pass", "score": 3}))
                after_display, after_finished = watch.render("camp-t")
            after_digest = hashlib.sha256(campaign_path.read_bytes()).hexdigest()
        self.assertIn("RUNNING", before_display)
        self.assertNotIn("RUNNING", after_display)
        self.assertIn("unassisted_pass", after_display)
        self.assertFalse(after_finished)
        self.assertEqual(before_digest, after_digest)


if __name__ == "__main__":
    unittest.main()