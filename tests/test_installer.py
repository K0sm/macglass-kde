import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="macglass test ")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HERE": str(ROOT),
            "MG": str(self.home / "macglass"),
            "TUI_LOG": str(self.home / "install.log"),
            "CALLS": str(self.home / "calls"),
            "RESULT": str(self.home / "result"),
            "DO_PACKAGES": "1",
            "ASSUME_YES": "0",
            "TEST_CANCEL": "0",
            "TEST_FAIL": "0",
            "TEST_INSTALLED": "0",
        }

    def command(self, name, body):
        target = self.bin / name
        target.write_text("#!/usr/bin/env bash\nset -eu\n" + body + "\n")
        target.chmod(0o755)

    def packages(self, terminal=False, **env):
        self.command("sudo", """
if [[ $1 == -n ]]; then
    [[ $2 == true ]]
    exit
fi
if [[ $1 == --test-install ]]; then
    [[ -t 0 ]]
    [[ "$(ps -o tpgid= -p $$)" == "$(ps -o pgid= -p $$)" ]]
    printf 'sudo test prompt: '
    read -r answer
    [[ $answer == y ]]
    exit
fi
exec "$@"
""")
        self.command("pacman", """
printf 'pacman %s\\n' "$*" >> "$CALLS"
if [[ $1 == -Q ]]; then
    [[ $TEST_INSTALLED == 1 || -f "$MG/packages/$2/.test-installed" ]] || exit 1
    printf '%s installed-version\\n' "$2"
else
    [[ $TEST_FAIL == 0 ]] || { echo 'download error: 404'; exit 1; }
    if [[ ${TEST_READ:-0} == 1 ]]; then
        read -r answer
        [[ $answer == y ]]
    fi
fi
""")
        self.command("makepkg", """
printf "makepkg %s\\n" "$*" >> "$CALLS"
[[ ${TEST_BUILD_FAIL:-0} == 0 ]] || { echo 'test build failed'; exit 1; }
if [[ ${TEST_BUILD_TTY:-0} == 1 ]]; then sudo --test-install; fi
touch .test-installed
""")
        self.command("sleep", "exit 0")
        source = (ROOT / "install.sh").read_text()
        section = source.split("# 5. Packages\n", 1)[1].split("# 6. Files\n", 1)[0]
        script = """
set -euo pipefail
. "$HERE/lib/tui.sh"
TUI_FANCY=0
TUI_LOG="$HOME/install.log"
S_PACKAGES=0
SUDO_KEEPALIVE=
trap 'if [[ -n "$SUDO_KEEPALIVE" ]]; then kill "$SUDO_KEEPALIVE" 2>/dev/null || true; wait "$SUDO_KEEPALIVE" 2>/dev/null || true; fi' EXIT
tui_screen() { :; }
tui_menu() { printf -v "$1" '%s' "$TEST_CANCEL"; }
die() { tui_fail "$*"; }
""" + section
        command = ["bash", "-c", script]
        if terminal:
            command = ["script", "-q", "-e", "-c", shlex.join(command), "/dev/null"]
        return subprocess.run(
            command,
            env={**self.env, **env},
            text=True,
            input="y\n" * 7,
            capture_output=True,
            timeout=10,
        )

    def calls(self):
        path = self.home / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def test_update_and_build_missing_packages(self):
        result = self.packages()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertTrue(calls[0].startswith("pacman -Syu --needed base-devel "))
        self.assertNotIn("--noconfirm", calls[0])
        self.assertEqual(sum(call.startswith("makepkg ") for call in calls), 6)

    def test_yes_accepts_package_transaction(self):
        result = self.packages(ASSUME_YES="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("-Syu --needed --noconfirm", self.calls()[0])

    def test_package_confirmation_can_read_stdin(self):
        result = self.packages(TEST_READ="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_build_can_prompt_on_foreground_terminal(self):
        result = self.packages(terminal=True, TEST_BUILD_TTY="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("sudo test prompt:"), 6)
        self.assertEqual(sum(call.startswith("makepkg ") for call in self.calls()), 6)

    def test_failed_build_stops_and_logs_error(self):
        result = self.packages(TEST_BUILD_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sum(call.startswith("makepkg ") for call in self.calls()), 1)
        self.assertIn("test build failed", (self.home / "install.log").read_text())

    def test_cancel_does_not_run_package_commands(self):
        result = self.packages(TEST_CANCEL="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [])

    def test_failed_update_stops_before_builds_and_logs_error(self):
        result = self.packages(TEST_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertIn("404", (self.home / "install.log").read_text())
        self.assertIn("refresh your distro's mirrors", result.stderr)

    def test_no_packages_skips_update_and_builds(self):
        result = self.packages(DO_PACKAGES="0", TEST_INSTALLED="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(all(call.startswith("pacman -Q ") for call in self.calls()))

    def test_launcher_resolves_clone_path_without_executable_installer(self):
        try:
            import gi  # noqa: F401
        except ImportError:
            self.skipTest("PyGObject is needed to exercise desktop-entry launching")
        clone = self.home / "clone with spaces"
        clone.mkdir()
        desktop = clone / "Install MacGlass.desktop"
        shutil.copyfile(ROOT / desktop.name, desktop)
        installer = clone / "install.sh"
        installer.write_text('printf "launched" > "$RESULT"\n')
        installer.chmod(0o644)
        self.command("konsole", '[[ $1 == --hold && $2 == -e ]]; shift 2; exec "$@"')
        result = subprocess.run(
            ["python3", "-c", """
import sys
from gi.repository import Gio
app = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
assert app is not None
assert app.launch([], None)
""", str(desktop)],
            env=self.env, text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        marker = self.home / "result"
        deadline = time.monotonic() + 5
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(marker.exists(), "Launcher did not execute the installer")
        self.assertEqual(marker.read_text(), "launched")


if __name__ == "__main__":
    unittest.main()
