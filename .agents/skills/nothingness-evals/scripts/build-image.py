from __future__ import annotations

import gzip
import os
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

from common import IMAGE_NAME, ROOT, command_or_fail, emit_json, pi_package_roots, require_command, resolve_pi, sha256


def reproducible_archive(destination: Path, sources: tuple[tuple[Path, str], ...]) -> None:
    uncompressed = destination.with_suffix("")

    def normalize(member: tarfile.TarInfo) -> tarfile.TarInfo:
        member.uid = member.gid = 0
        member.uname = member.gname = "root"
        member.mtime = 0
        return member

    with tarfile.open(uncompressed, "w", format=tarfile.PAX_FORMAT) as output:
        for source, arcname in sources:
            output.add(source, arcname=arcname, filter=normalize)
    with uncompressed.open("rb") as source, destination.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed)
    uncompressed.unlink()


def main() -> None:
    require_command("docker")
    pi = resolve_pi()
    payload = Path(pi["payload"])

    with tempfile.TemporaryDirectory(prefix="nothingness-eval-image.") as temporary:
        context = Path(temporary)
        for name in ("Dockerfile", "entrypoint.py", "candidate.py", "egress_proxy.py", "pi.py", ".dockerignore"):
            shutil.copy2(ROOT / "evals" / "image" / name, context / name)
        media = context / "media"
        media.mkdir()
        for source in (ROOT / "evals" / "assets" / "opus").glob("*.opus"):
            shutil.copy2(source, media / source.name)
        shutil.copy2(ROOT / "evals" / "assets" / "opus" / "manifest.json", media / "manifest.json")
        archive = context / "pi-artifact.tar.gz"
        reproducible_archive(archive, ((payload, "pi"),))
        artifact_sha = sha256(archive)
        packages_archive = context / "pi-packages.tar.gz"
        reproducible_archive(packages_archive, tuple((root, root.name) for root in pi_package_roots()))
        packages_sha = sha256(packages_archive)
        dependency_seed = context / "dependency-seed"
        (dependency_seed / "soloud").mkdir(parents=True)
        for repository_path, destination in (("pubspec.yaml", dependency_seed / "pubspec.yaml"), ("soloud/pubspec.yaml", dependency_seed / "soloud" / "pubspec.yaml")):
            destination.write_bytes(command_or_fail(["git", "show", f"5fc7e04:{repository_path}"], 3, "fixture_dependency_manifest_failed", stdout=subprocess.PIPE, text=False).stdout)
        command_or_fail(
            ["docker", "build", "--label", "nothingness.eval=true", "--label", f"nothingness.eval.pi_packages_sha256={packages_sha}", "--build-arg", f"PI_ARTIFACT_SHA256={artifact_sha}", "--build-arg", f"PI_PACKAGES_SHA256={packages_sha}", "-t", IMAGE_NAME, str(context)],
            3,
            "image_build_failed",
            stdout=os.devnull,
        )
    emit_json({"ok": True, "image": IMAGE_NAME, "pi_version": pi["version"], "pi_artifact_sha256": artifact_sha, "pi_packages_sha256": packages_sha})


if __name__ == "__main__":
    main()