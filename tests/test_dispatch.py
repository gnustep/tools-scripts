"""Exercise dispatch without installing packages or building GNUstep."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DispatchTests(unittest.TestCase):
    def run_dispatch(self, *args, root=ROOT, msystem="", workspace=None):
        env = dict(os.environ, MSYSTEM=msystem)
        env.pop("GNUSTEP_WORKSPACE_ROOT", None)
        if workspace is not None:
            env["GNUSTEP_WORKSPACE_ROOT"] = str(workspace)
        return subprocess.run(
            [str(root / "gnustep"), *args], cwd="/", env=env,
            text=True, capture_output=True,
        )

    def test_platform_aliases_and_fallback(self):
        for os_name, arch, expected in [
            ("macos", "aarch64", "darwin/any/default"),
            ("Linux", "amd64", "linux/any/default"),
            ("windows", "amd64", "windows/x86_64/gcc"),
        ]:
            with self.subTest(os=os_name):
                result = self.run_dispatch("build", "--os", os_name,
                                           "--arch", arch, "--dry-run")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(expected, result.stdout)

    def test_windows_environments(self):
        for msystem, expected in [
            ("MINGW32", "windows/x86/gcc"),
            ("MINGW64", "windows/x86_64/gcc"),
            ("CLANG64", "windows/x86_64/clang"),
            ("MSYS", "windows/x86_64/msys"),
        ]:
            with self.subTest(msystem=msystem):
                result = self.run_dispatch("build", "--os", "windows",
                                           "--dry-run", msystem=msystem)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(expected, result.stdout)

    def test_invalid_requests(self):
        for args in [
            ("build", "--os"),
            ("build", "--os", "../commands", "--dry-run"),
            ("build", "--toolchain", "missing", "--dry-run"),
            ("not-a-command",),
        ]:
            with self.subTest(args=args):
                self.assertNotEqual(self.run_dispatch(*args).returncode, 0)

    def test_execution_workspace_arguments_and_exit_status(self):
        with tempfile.TemporaryDirectory(prefix="gnustep test ") as tmp:
            root = Path(tmp) / "tools-scripts"
            root.mkdir()
            shutil.copy2(ROOT / "gnustep", root / "gnustep")
            script = root / "scripts/build/test/any/default"
            script.parent.mkdir(parents=True)
            script.write_text('#!/bin/sh\npwd\nprintf "%s\\n" "$@"\nexit 7\n')
            script.chmod(0o755)
            workspace = Path(tmp) / "custom workspace"
            workspace.mkdir()
            result = self.run_dispatch("build", "--os", "test", "--",
                                       "two words", "--flag", root=root,
                                       workspace=workspace)
            self.assertEqual(result.returncode, 7)
            self.assertEqual(result.stdout.splitlines()[-3:],
                             [str(workspace), "two words", "--flag"])

    def test_commands_preserve_working_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copy2(ROOT / "gnustep", root / "gnustep")
            script = root / "scripts/commands/test/probe"
            script.parent.mkdir(parents=True)
            script.write_text('#!/bin/sh\npwd\nprintf "%s\\n" "$1"\n')
            script.chmod(0o755)
            result = self.run_dispatch("probe", "two words", root=root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ["/", "two words"])


if __name__ == "__main__":
    unittest.main()
