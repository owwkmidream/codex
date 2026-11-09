"""用隔离 Git 仓库验证 CI 补丁应用，不接触真实安装或远端。"""

import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "apply-patches.sh"


class ApplyPatchesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex-patch-test-", ignore_cleanup_errors=True)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.origin = self.root / "origin"
        self.origin.mkdir()
        self.git(self.origin, "init", "-b", "main")
        self.git(self.origin, "config", "user.name", "Fixture")
        self.git(self.origin, "config", "user.email", "fixture@localhost")
        self.git(self.origin, "config", "core.autocrlf", "false")
        self.source = self.origin / "feature.txt"
        (self.origin / ".cargo").mkdir()
        (self.origin / ".cargo" / "config.toml").write_text("[build]\njobs = 2\n", newline="\n")
        self.source.write_text("first\ncontext\nbase\nlast\n", encoding="utf-8", newline="\n")
        self.commit("baseline")
        self.git(self.origin, "tag", "rust-v1")
        self.source.write_text("first\ncontext\nfeature\nlast\n", encoding="utf-8", newline="\n")
        self.commit("feat: quote")
        self.source.write_text("first\ncontext\nfeature-fixed\nlast\n", encoding="utf-8", newline="\n")
        self.commit("fix: quote")
        self.series = self.root / "patches" / "series" / "rust-v1"
        self.series.mkdir(parents=True)
        self.git(self.origin, "format-patch", "--full-index", "-o", str(self.series), "rust-v1..HEAD")
        self.patch = self.root / "patches" / "rust-v1.patch"
        self.patch.write_text(self.git(self.origin, "diff", "--full-index", "rust-v1", "HEAD"), encoding="utf-8", newline="\n")
        self.expected_tree = self.git(self.origin, "rev-parse", "HEAD^{tree}").strip()
        self.git(self.origin, "switch", "-c", "next", "rust-v1")

    def git(self, repo, *args):
        return subprocess.run(
            ["git", "-C", str(repo), *args], check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", timeout=20,
        ).stdout

    def commit(self, message):
        self.git(self.origin, "add", ".")
        self.git(self.origin, "commit", "-m", message)

    def apply(self, name="target"):
        target = self.root / name
        self.git(self.root, "clone", "--depth=1", "--branch", "next", self.origin.as_uri(), str(target))
        output = self.root / f"{name}.outputs"
        report = self.root / f"{name}-reports"
        result = subprocess.run(
            [shutil.which("bash"), SCRIPT.as_posix(), target.as_posix(), self.patch.as_posix(), "rust-v1", report.as_posix()],
            env={**os.environ, "GITHUB_OUTPUT": str(output)},
            capture_output=True, text=True, encoding="utf-8", timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return target, output.read_text(encoding="utf-8"), report

    def test_exact_series_matches_aggregate_and_has_stable_commits(self):
        target, output, _ = self.apply()
        self.assertIn("applied=true", output)
        self.assertIn("strategy=git am --3way", output)
        self.assertEqual(self.git(target, "rev-parse", "HEAD^{tree}").strip(), self.expected_tree)
        self.assertEqual(self.git(target, "log", "-2", "--format=%s").splitlines(), ["fix: quote", "feat: quote"])
        again, _, _ = self.apply("repeat")
        self.assertEqual(self.git(target, "rev-parse", "HEAD"), self.git(again, "rev-parse", "HEAD"))

    def test_new_version_merges_context_drift_and_dependent_feature(self):
        # 同一文件附近的上游变更使第二个补丁需要基线链中的中间原像。
        self.source.write_text("upstream\ncontext\nbase\nlast\n", encoding="utf-8", newline="\n")
        self.commit("upstream context")
        target, output, _ = self.apply()
        self.assertIn("applied=true", output)
        self.assertEqual((target / "feature.txt").read_text(), "upstream\ncontext\nfeature-fixed\nlast\n")

    def test_conflict_names_feature_and_stops_before_later_commits(self):
        self.source.write_text("first\ncontext\nconflicting-upstream\nlast\n", encoding="utf-8", newline="\n")
        self.commit("upstream conflict")
        target, output, report = self.apply()
        self.assertIn("applied=false", output)
        self.assertIn("0001-feat-quote.patch", (report / "conflict.log").read_text(encoding="utf-8"))
        self.assertIn("feature.txt", (report / "conflict-files.txt").read_text())
        self.assertEqual(self.git(target, "log", "-1", "--format=%s").strip(), "upstream conflict")

    def test_invalid_baseline_series_reports_its_feature(self):
        first = sorted(self.series.glob("*.patch"))[0]
        first.write_text("invalid mail patch\n", encoding="utf-8")
        (self.origin / "new.txt").write_text("new upstream\n")
        self.commit("next version")
        _, output, report = self.apply()
        self.assertIn("applied=false", output)
        self.assertIn("基线重建：0001-feat-quote.patch", (report / "conflict.log").read_text(encoding="utf-8"))

    def test_legacy_aggregate_without_series(self):
        self.series.rename(self.series.with_name("saved-series"))
        target, output, _ = self.apply()
        self.assertIn("applied=true", output)
        self.assertEqual(self.git(target, "rev-parse", "HEAD^{tree}").strip(), self.expected_tree)

    def test_legacy_aggregate_three_way_merge(self):
        self.series.rename(self.series.with_name("saved-series"))
        self.source.write_text("upstream\ncontext\nbase\nlast\n", encoding="utf-8", newline="\n")
        self.commit("upstream context")
        target, output, _ = self.apply()
        self.assertIn("applied=true", output)
        self.assertIn("strategy=git apply --3way", output)
        self.assertEqual((target / "feature.txt").read_text(), "upstream\ncontext\nfeature-fixed\nlast\n")

    def test_source_archive_preserves_git_history_and_hidden_config(self):
        target, output, _ = self.apply()
        self.assertIn("applied=true", output)
        # 覆盖 Linux 源码中的相对链接，Windows 恢复时必须得到普通文件。
        (target / "COPYING").write_text("fixture license\n", encoding="utf-8", newline="\n")
        (target / "LICENSE").symlink_to("COPYING")
        archive = self.root / "patched-source.tar.gz"
        restored = self.root / "restored"
        restored.mkdir()
        tar = shutil.which("tar")
        subprocess.run([tar, "--dereference", "--hard-dereference", "-czf", archive.name, "-C", target.name, "."], cwd=self.root, check=True, timeout=10)
        with tarfile.open(archive) as source:
            self.assertTrue(source.getmember("./LICENSE").isfile())
            self.assertTrue(source.getmember("./COPYING").isfile())
        subprocess.run([tar, "-xzf", archive.name, "-C", restored.name], cwd=self.root, check=True, timeout=10)
        self.assertFalse((restored / "LICENSE").is_symlink())
        self.assertEqual((restored / "LICENSE").read_text(), "fixture license\n")
        self.assertTrue((restored / ".git").is_dir())
        self.assertEqual(self.git(restored, "log", "-2", "--format=%s").splitlines(), ["fix: quote", "feat: quote"])
        self.assertEqual((restored / ".cargo" / "config.toml").read_text(), "[build]\njobs = 2\n")


if __name__ == "__main__":
    unittest.main()
