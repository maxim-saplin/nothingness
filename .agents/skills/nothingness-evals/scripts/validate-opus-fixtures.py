from __future__ import annotations

from common import ROOT, command_or_fail, emit_json, fail, require_command, read_json, sha256


def main() -> None:
    for executable in ("ffmpeg", "ffprobe"):
        require_command(executable)
    fixture_dir = ROOT / "evals" / "assets" / "opus"
    manifest = read_json(fixture_dir / "manifest.json")
    files = list(fixture_dir.glob("*.opus"))
    if len(manifest) != 10 or len(files) != 10:
        fail(3, "invalid_opus_fixture_count")
    for item in manifest:
        relative_path = item["path"]
        source = ROOT / relative_path
        if not source.is_file():
            fail(3, f"missing_opus_fixture:{relative_path}")
        actual_sha = sha256(source)
        if actual_sha != item["sha256"]:
            fail(3, f"invalid_opus_fixture_sha256:{relative_path}")
        codec = command_or_fail(
            ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "default=nw=1:nk=1", str(source)],
            3,
            f"opus_probe_failed:{relative_path}",
            stdout=-1,
        ).stdout.strip()
        if codec != "opus":
            fail(3, f"invalid_opus_codec:{relative_path}")
        command_or_fail(["ffmpeg", "-nostdin", "-v", "error", "-i", str(source), "-f", "null", "-"], 3, f"opus_decode_failed:{relative_path}")
    emit_json({"ok": True, "count": len(manifest), "codec": "opus", "fullDecode": True})


if __name__ == "__main__":
    main()