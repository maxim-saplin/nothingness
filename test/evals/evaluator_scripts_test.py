from __future__ import annotations

import importlib.util
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / ".agents" / "skills" / "nothingness-evals" / "scripts"
sys.path.insert(0, str(SCRIPTS))


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
consolidate = load_script("consolidate.py")
cleanup = load_script("cleanup.py")
preflight = load_script("preflight.py")
offline_baseline = load_script("verify-offline-baseline.py")
runtime_baseline = load_script("verify-runtime-baseline.py")
watch = load_script("watch-eval.py")
judge_control = load_script("judge-control.py")
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
            classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, inspection], ["events-1", "inspection-1"])
            unavailable_runtime_evidence = {"runtime": {"available": False}, "git": {"available": True}, "processes": {"available": True}}
            unavailable_runtime = observation("inspection-unavailable", unavailable_runtime_evidence, kind="inspection", runtime=True, git=True, processes=True, availability={"runtime": False, "git": True, "processes": True})
            classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, unavailable_runtime], ["events-1", "inspection-unavailable"])
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 9}, [events, inspection], ["events-1", "inspection-1"])
            without_processes = observation("inspection-2", {"runtime": {}, "git": {"available": True}}, kind="inspection", runtime=True, git=True, processes=False, availability={"runtime": None, "git": True})
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, without_processes], ["events-1", "inspection-2"])
            (run / "events-1.json").write_text("tampered")
            with self.assertRaises(SystemExit):
                classify.validate_judge_review(run, {"terminal_event_sequence": 8}, [events, inspection], ["events-1", "inspection-1"])

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
            for event_observations in (
                [observation("terminal-only", 0, [8])],
                [observation("truncated", 0, [1, 2, 3, 4])],
                [observation("first", 0, [1, 2, 3, 4, 5]), observation("overlap", 4, [5, 6, 7, 8])],
            ):
                observations = [*event_observations, inspection]
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

    def test_consolidation_rejects_duplicate_and_mixed_cohorts(self) -> None:
        base = {"run_id": "run-1", "validity": "valid", "model_identity_verified": True, "task_id": "t1", "fixture_commit": "fixture", "requested_model": {"provider": "p", "model": "m", "thinking": "medium"}, "selected_model": {"provider": "p", "model": "m", "thinking": "medium"}, "image": {"immutable_id": "image"}, "config_fingerprints": {"a": "b"}, "task_contract": {"prompt": "task"}, "score": 3, "outcome": "unassisted_pass"}
        with self.assertRaises(SystemExit):
            consolidate.consolidate_results([base, base, base], 3)
        mixed = [base, base | {"run_id": "run-2"}, base | {"run_id": "run-3", "selected_model": {"provider": "p", "model": "other", "thinking": "medium"}}]
        with self.assertRaises(SystemExit):
            consolidate.consolidate_results(mixed, 3)

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

    def test_t1_oracle_requires_successful_actions_and_valid_opus_state(self) -> None:
        commands = ["drive.py play /opt/nothingness/media/a.opus", "drive.py pause", "drive.py next", "drive.py seek 0:05"]
        events = []
        for index, value in enumerate(commands):
            events.extend(({"type": "tool_execution_start", "toolCallId": str(index), "args": {"command": value}}, {"type": "tool_execution_end", "toolCallId": str(index), "isError": False}))
        playback = {"playback": {"queueLength": 2, "currentIndex": 1, "songInfo": {"path": "/opt/nothingness/media/b.opus"}}}
        with tempfile.TemporaryDirectory() as temporary:
            transcript = Path(temporary) / "candidate.jsonl"
            transcript.write_text("".join(json.dumps(event) + "\n" for event in events))
            result = collect.t1_task_evidence(transcript, subprocess.CompletedProcess([], 0, json.dumps(playback), ""))
        self.assertTrue(result["passed"])
        self.assertEqual(result["actions"], {"play": True, "pause": True, "skip": True, "seek": True})

    def test_t1_oracle_rejects_mentions_chains_and_failed_actions(self) -> None:
        commands = [
            ("echo drive.py play", False),
            ("printf 'drive.py pause'", False),
            ("drive.py next && echo ok", False),
            ("drive.py seek 0:05", True),
            ("drive.py play 2>&1", False),
            ("drive.py pause &>out", False),
            ("drive.py next >|out", False),
            ("drive.py play <<<text", False),
            ("drive.py seek $(echo 5)", False),
            ("drive.py play `printf /x.opus`", False),
        ]
        events = []
        for index, (value, failed) in enumerate(commands):
            events.extend(({"type": "tool_execution_start", "toolCallId": str(index), "args": {"command": value}}, {"type": "tool_execution_end", "toolCallId": str(index), "isError": failed}))
        playback = {"playback": {"queueLength": 2, "currentIndex": 1, "songInfo": {"path": "/opt/nothingness/media/b.opus"}}}
        with tempfile.TemporaryDirectory() as temporary:
            transcript = Path(temporary) / "candidate.jsonl"
            transcript.write_text("".join(json.dumps(event) + "\n" for event in events))
            result = collect.t1_task_evidence(transcript, subprocess.CompletedProcess([], 0, json.dumps(playback), ""))
        self.assertFalse(result["passed"])
        self.assertEqual(result["actions"], {"play": False, "pause": False, "skip": False, "seek": False})

    def test_t1_oracle_accepts_fail_fast_drive_variable_wrappers(self) -> None:
        commands = [
            "set -euo pipefail\nD=./.agents/skills/agent-emulator-debugging/scripts/drive.py\n$D resume >/tmp/play.json",
            "set -euo pipefail\nD=./.agents/skills/agent-emulator-debugging/scripts/drive.py\n$D pause > /tmp/pause.json",
            "set -euo pipefail\nD=./.agents/skills/agent-emulator-debugging/scripts/drive.py\n$D next >/tmp/next.json",
            "set -euo pipefail\nD=./.agents/skills/agent-emulator-debugging/scripts/drive.py\n$D seek 0:30 >/tmp/seek.json",
        ]
        events = []
        for index, value in enumerate(commands):
            events.extend(({"type": "tool_execution_start", "toolCallId": str(index), "args": {"command": value}}, {"type": "tool_execution_end", "toolCallId": str(index), "isError": False}))
        playback = {"playback": {"queueLength": 3, "currentIndex": 2, "songInfo": {"path": "/opt/nothingness/media/c.opus"}}}
        with tempfile.TemporaryDirectory() as temporary:
            transcript = Path(temporary) / "candidate.jsonl"
            transcript.write_text("".join(json.dumps(event) + "\n" for event in events))
            result = collect.t1_task_evidence(transcript, subprocess.CompletedProcess([], 0, json.dumps(playback), ""))
        self.assertTrue(result["passed"])
        self.assertEqual(result["actions"], {"play": True, "pause": True, "skip": True, "seek": True})

    def test_t1_oracle_rejects_unsafe_drive_variable_wrappers(self) -> None:
        commands = [
            "D=./drive.py\n$D pause",
            "set -euo pipefail\nD=$(printf ./drive.py)\n$D next",
            "set -euo pipefail\nD=./drive.py\n$D seek 0:30 && echo ok",
            "set -euo pipefail\nD=./drive.py\necho $D resume",
        ]
        self.assertTrue(all(not collect.drive_actions({"command": command}) for command in commands))

    def test_result_schema_rejects_invalid_score_combinations(self) -> None:
        classify.validate_classification("valid", "unassisted_pass", 3)
        classify.validate_classification("valid", "assisted_pass", 2)
        classify.validate_classification("valid", "candidate_fail", 0)
        with self.assertRaises(SystemExit):
            classify.validate_classification("invalid_infrastructure", "unassigned", 1)
        with self.assertRaises(SystemExit):
            classify.validate_classification("valid", "unassisted_pass", 4)
        with self.assertRaises(SystemExit):
            classify.validate_classification("valid", "candidate_fail", 3)
        with self.assertRaises(SystemExit):
            classify.validate_classification("invalid_infrastructure", "candidate_fail", None)


if __name__ == "__main__":
    unittest.main()