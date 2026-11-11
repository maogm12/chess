#!/usr/bin/env python3
"""Exercise the integration runner's simulator selection without booting devices."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RUNNER = Path(__file__).resolve().parent / "run-ios-tests.sh"
PREFIX = "com.apple.CoreSimulator.SimRuntime.iOS-"


class IOSRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="forkchess-ios-runner-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.trace = self.root / "commands.jsonl"
        self.runtimes = []
        self.devices = {}
        self.stub("uname", 'print("arm64")')
        self.stub("xcrun", """
args = sys.argv[1:]
if args == ["simctl", "list", "devices", "available", "--json"]:
    print(os.environ["IOS_STUB_DEVICES"])
elif args == ["simctl", "list", "runtimes", "--json"]:
    print(os.environ["IOS_STUB_RUNTIMES"])
else:
    sys.exit("Unexpected simulator command")
""")
        self.stub("xcodebuild", """
args = sys.argv[1:]
if args == ["-version"]:
    print("Xcode test stub")
else:
    assert args[0] == "test", args
    assert args[args.index("-scheme") + 1] == "ForkChess", args
    assert args[args.index("-parallel-testing-enabled") + 1] == "NO", args
    Path(args[args.index("-resultBundlePath") + 1]).mkdir()
    print("integration runner output")
    sys.exit(int(os.environ.get("IOS_STUB_EXIT", "0")))
""")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\nfrom pathlib import Path\n"
            "with open(os.environ['IOS_STUB_TRACE'], 'a') as trace:\n"
            "    trace.write(json.dumps([Path(sys.argv[0]).name] + sys.argv[1:]) + '\\n')\n"
            + body
        )
        path.chmod(0o755)

    def runtime(self, suffix, version, name="iPhone 17 Pro", available=True):
        identifier = PREFIX + suffix
        self.runtimes.append({
            "identifier": identifier, "version": version, "isAvailable": available
        })
        self.devices[identifier] = [{
            "name": name, "udid": suffix, "isAvailable": True
        }]

    def run_script(self, **environment):
        return subprocess.run(
            ["/bin/bash", str(RUNNER), str(self.root / "results")],
            env={
                **os.environ,
                "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                "IOS_STUB_TRACE": str(self.trace),
                "IOS_STUB_DEVICES": json.dumps({"devices": self.devices}),
                "IOS_STUB_RUNTIMES": json.dumps({"runtimes": self.runtimes}),
                **environment,
            },
            capture_output=True, text=True, timeout=30,
        )

    def xctest_commands(self):
        commands = [json.loads(line) for line in self.trace.read_text().splitlines()]
        return [command for command in commands if command[:2] == ["xcodebuild", "test"]]

    def assert_selected(self, result, identifier):
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.xctest_commands()
        self.assertEqual(len(commands), 1)
        command = commands[0]
        self.assertEqual(command[command.index("-destination") + 1],
                         "platform=iOS Simulator,id=" + identifier)

    def test_device_specific_runtime_uses_numeric_version_metadata(self):
        self.runtime("27-1", "27.1")
        self.runtime("27-2-iPhone19-4", "27.2", name="iPhone Duo")
        self.assert_selected(self.run_script(), "27-2-iPhone19-4")

    def test_numeric_version_order_and_same_version_device_preference(self):
        self.runtime("27-2", "27.2")
        self.runtime("27-10", "27.10", name="iPhone 18 Pro")
        self.devices[PREFIX + "27-10"].append({
            "name": "iPhone 17 Pro", "udid": "preferred", "isAvailable": True
        })
        self.assert_selected(self.run_script(), "preferred")

    def test_unavailable_or_unknown_runtimes_and_unavailable_devices_are_skipped(self):
        self.runtime("27-2", "27.2")
        self.runtime("28-0", "28.0", available=False)
        self.runtime("29-0", "29.0")
        self.devices[PREFIX + "29-0"][0]["isAvailable"] = False
        self.devices[PREFIX + "unknown"] = [{
            "name": "iPhone 17 Pro", "udid": "unknown", "isAvailable": True
        }]
        self.assert_selected(self.run_script(), "27-2")

    def test_ipad_only_inventory_stops_before_xctest(self):
        self.runtime("27-2", "27.2", name="iPad mini (A20 Pro)")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No available iPhone simulator", result.stderr)
        self.assertEqual(self.xctest_commands(), [])

    def test_xctest_failure_retains_log_and_exit_code(self):
        self.runtime("27-2", "27.2")
        result = self.run_script(IOS_STUB_EXIT="65")
        self.assertEqual(result.returncode, 65, result.stderr)
        self.assertIn("integration runner output",
                      (self.root / "results/ios.log").read_text())


if __name__ == "__main__":
    unittest.main()
