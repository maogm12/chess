#!/usr/bin/env python3
"""Check simulator ownership and failure propagation without launching a simulator."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RUNNER = Path(__file__).resolve().parent / "run-e2e-tests.sh"
SIMULATOR = "11111111-1111-1111-1111-111111111111"


class E2ERunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="forkchess-runner-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.trace = self.root / "commands.jsonl"
        self.environment = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "E2E_RUNNER_TRACE": str(self.trace),
            "E2E_IOS_VERSION": "",
        }
        self.stub("uname", 'print("arm64")')
        self.stub("xcrun", """
args = sys.argv[1:]
if args[:3] == ["simctl", "list", "runtimes"]:
    family = os.environ.get("E2E_STUB_FAMILY", "iPhone")
    devices = [] if family == "none" else [{
        "name": "iPhone 17 Pro" if family == "iPhone" else "iPad mini (A17 Pro)",
        "identifier": "test-device-type"
    }]
    runtimes = [{
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        "version": "26.5", "isAvailable": True, "supportedDeviceTypes": devices
    }]
    if os.environ.get("E2E_STUB_DUO"):
        runtimes.append({
            "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
            "version": "27.1", "isAvailable": True,
            "supportedDeviceTypes": [{"name": "iPhone Duo", "identifier": "duo-type"}]
        })
    if os.environ.get("E2E_STUB_NEWER"):
        runtimes.append({
            "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            "version": "27.0", "isAvailable": True, "supportedDeviceTypes": devices
        })
    print(json.dumps({"runtimes": runtimes}))
elif args[:2] == ["simctl", "create"]:
    print("11111111-1111-1111-1111-111111111111")
elif args[:2] == ["simctl", "bootstatus"]:
    assert args[2] == "11111111-1111-1111-1111-111111111111", args
    if args[3:] == ["-b"]:
        print(os.environ.get("E2E_STUB_BOOT_STATUS", "Simulator boot status"))
        sys.exit(int(os.environ.get("E2E_STUB_BOOT_EXIT", "0")))
    assert args[3:] == ["-d"], args
    sequence = json.loads(os.environ.get("E2E_STUB_MIGRATION_SEQUENCE", "[]"))
    counter = Path(os.environ["E2E_RUNNER_TRACE"] + ".migration")
    attempt = int(counter.read_text()) if counter.exists() else 0
    if sequence:
        print(sequence[min(attempt, len(sequence) - 1)])
        counter.write_text(str(attempt + 1))
    else:
        print(os.environ.get(
            "E2E_STUB_MIGRATION_DETAILS",
            "com.apple.migration : duration: 0.1, status: success"))
    sys.exit(int(os.environ.get("E2E_STUB_DETAILS_EXIT", "0")))
elif args[:2] not in (["simctl", "shutdown"], ["simctl", "delete"]):
    sys.exit("Unexpected simctl command")
""")
        self.stub("xcodebuild", """
args = sys.argv[1:]
if args == ["-version"]:
    print("Xcode test stub")
else:
    assert args[0] == "test", args
    assert args[args.index("-scheme") + 1] == "ForkChessE2E", args
    assert args[args.index("-parallel-testing-enabled") + 1] == "NO", args
    assert args[args.index("-collect-test-diagnostics") + 1] == "never", args
    assert args[args.index("-destination") + 1].endswith("11111111-1111-1111-1111-111111111111"), args
    Path(args[args.index("-resultBundlePath") + 1]).mkdir()
    print("UI runner output")
    sys.exit(int(os.environ.get("E2E_STUB_EXIT", "0")))
""")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\nfrom pathlib import Path\n"
            "with open(os.environ['E2E_RUNNER_TRACE'], 'a') as trace:\n"
            "    trace.write(json.dumps([Path(sys.argv[0]).name] + sys.argv[1:]) + '\\n')\n"
            + body
        )
        path.chmod(0o755)

    def run_script(self, family="iPhone", **environment):
        return subprocess.run(
            ["/bin/bash", str(RUNNER), str(self.root / "results"), family],
            env={**self.environment, **environment},
            capture_output=True,
            text=True,
            timeout=60,
        )

    def commands(self):
        if not self.trace.exists():
            return []
        return [json.loads(line) for line in self.trace.read_text().splitlines()]

    def assert_cleanup(self):
        self.assertEqual(self.commands()[-2:], [
            ["xcrun", "simctl", "shutdown", SIMULATOR],
            ["xcrun", "simctl", "delete", SIMULATOR],
        ])

    def test_success_uses_and_removes_only_its_own_simulator(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cleanup()
        self.assertIn("UI runner output", (self.root / "results/e2e.log").read_text())
        self.assertEqual((self.root / "results/simulator-id.txt").read_text().strip(), SIMULATOR)
        boot = ["xcrun", "simctl", "bootstatus", SIMULATOR, "-b"]
        test = next(command for command in self.commands() if command[:2] == ["xcodebuild", "test"])
        self.assertLess(self.commands().index(boot), self.commands().index(test))
        self.assertIn("Simulator boot status", (self.root / "results/boot.log").read_text())

    def test_boot_failure_preserves_logs_and_cleans_up_without_testing(self):
        result = self.run_script(E2E_STUB_BOOT_EXIT="43")
        self.assertEqual(result.returncode, 43, result.stderr)
        self.assert_cleanup()
        self.assertIn("Simulator boot status", (self.root / "results/boot.log").read_text())
        self.assertFalse(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_migration_failure_with_zero_exit_does_not_start_tests(self):
        status = "Status=3, isTerminal=YES\n\tData Migration Failed"
        details = "com.apple.migration : duration: 0.1, status: failed"
        result = self.run_script(E2E_STUB_BOOT_STATUS=status,
                                 E2E_STUB_MIGRATION_DETAILS=details)
        self.assertNotEqual(result.returncode, 0)
        self.assert_cleanup()
        self.assertIn("Data Migration Failed", (self.root / "results/boot.log").read_text())
        self.assertIn("status: failed", (self.root / "results/migration.log").read_text())
        self.assertFalse(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_premature_boot_completion_with_pending_migration_stops_testing(self):
        details = ("com.apple.first : duration: 0.1, status: success\n"
                   "com.apple.second : duration: 0.0, status: pending\n")
        result = self.run_script(E2E_STUB_MIGRATION_DETAILS=details,
                                 E2E_MIGRATION_TIMEOUT_SECONDS="0")
        self.assertNotEqual(result.returncode, 0)
        self.assert_cleanup()
        self.assertIn("status: pending", (self.root / "results/migration.log").read_text())
        self.assertFalse(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_missing_migration_details_stops_testing(self):
        result = self.run_script(E2E_STUB_MIGRATION_DETAILS="")
        self.assertNotEqual(result.returncode, 0)
        self.assert_cleanup()
        self.assertFalse(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_pending_migration_is_polled_until_success(self):
        pending = "com.apple.migration : duration: 0.0, status: running"
        success = "com.apple.migration : duration: 0.1, status: success"
        result = self.run_script(
            E2E_STUB_MIGRATION_SEQUENCE=json.dumps([pending, success]),
            E2E_MIGRATION_POLL_SECONDS="0.01",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cleanup()
        self.assertIn(success, (self.root / "results/migration.log").read_text())
        self.assertTrue(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_inconsistent_boot_summary_requires_successful_plugin_details(self):
        details = ("Data migration details:\n"
                   "\tcom.apple.first : duration: 0.1, status: success\n"
                   "\tcom.apple.second : duration: 0.2, status: success\n")
        result = self.run_script(E2E_STUB_BOOT_STATUS="Data Migration Failed",
                                 E2E_STUB_MIGRATION_DETAILS=details)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cleanup()
        self.assertIn(details, (self.root / "results/migration.log").read_text())
        self.assertTrue(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_one_failed_migration_plugin_stops_testing(self):
        details = ("com.apple.first : duration: 0.1, status: failed\n"
                   "com.apple.second : duration: 0.2, status: success\n")
        result = self.run_script(E2E_STUB_BOOT_STATUS="Data Migration Failed",
                                 E2E_STUB_MIGRATION_DETAILS=details)
        self.assertNotEqual(result.returncode, 0)
        self.assert_cleanup()
        self.assertIn("status: failed", (self.root / "results/migration.log").read_text())
        self.assertFalse(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_migration_details_command_failure_stops_testing(self):
        result = self.run_script(E2E_STUB_DETAILS_EXIT="44")
        self.assertEqual(result.returncode, 44, result.stderr)
        self.assert_cleanup()
        self.assertFalse(any(command[:2] == ["xcodebuild", "test"] for command in self.commands()))

    def test_xcodebuild_failure_keeps_evidence_and_propagates_exit_code(self):
        result = self.run_script(E2E_STUB_EXIT="42")
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assert_cleanup()
        self.assertTrue((self.root / "results/EndToEnd.xcresult").is_dir())
        self.assertIn("UI runner output", (self.root / "results/e2e.log").read_text())

    def test_ipad_selection(self):
        result = self.run_script("iPad", E2E_STUB_FAMILY="iPad")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(command for command in self.commands() if command[1:3] == ["simctl", "create"])
        self.assertEqual(create[3:], [
            "ForkChess E2E iPad", "test-device-type",
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        ])
        self.assert_cleanup()

    def test_newest_runtime_takes_precedence_over_preferred_screen_size(self):
        result = self.run_script(E2E_STUB_DUO="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(command for command in self.commands() if command[1:3] == ["simctl", "create"])
        self.assertEqual(create[-2:], ["duo-type", "com.apple.CoreSimulator.SimRuntime.iOS-27-1"])
        self.assert_cleanup()

    def test_requested_version_keeps_newer_installed_runtime_out_of_ci(self):
        result = self.run_script(E2E_STUB_NEWER="1", E2E_IOS_VERSION="26.5")
        self.assertEqual(result.returncode, 0, result.stderr)
        create = next(command for command in self.commands() if command[1:3] == ["simctl", "create"])
        self.assertEqual(create[-1], "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
        self.assert_cleanup()

    def test_missing_requested_runtime_does_not_create_a_device(self):
        result = self.run_script(E2E_IOS_VERSION="99.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No available iPhone simulator on iOS 99.0", result.stderr)
        self.assertFalse(any(command[1:3] in (["simctl", "create"], ["simctl", "delete"])
                             for command in self.commands()))

    def test_existing_result_is_not_overwritten(self):
        (self.root / "results/EndToEnd.xcresult").mkdir(parents=True)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fresh output directory", result.stderr)
        self.assertFalse(any(command[0] == "xcrun" for command in self.commands()))

    def test_invalid_family_does_not_touch_simulators(self):
        result = self.run_script("Mac")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(command[0] == "xcrun" for command in self.commands()))

    def test_missing_runtime_does_not_delete_an_existing_simulator(self):
        result = self.run_script(E2E_STUB_FAMILY="none")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No available iPhone simulator", result.stderr)
        self.assertFalse(any(command[1:3] in (["simctl", "create"], ["simctl", "delete"])
                             for command in self.commands()))


if __name__ == "__main__":
    unittest.main()
