"""Test the daemon with real signature checks and isolated fake power commands."""
import plistlib
from pathlib import Path
import re
import select
import signal
import socket
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class HelperIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix="caffelid.tests.", dir="/private/tmp")
        cls.root = Path(cls.work.name)
        cls.log = cls.root / "commands"
        cls.fail_enable = cls.root / "fail-enable"
        cls.fail_restore = cls.root / "fail-restore"
        cls.requirement = cls.root / "client.req"
        cls.legacy_plist = cls.root / "legacy.plist"
        cls.legacy_helper = cls.root / "legacy.helper"
        cls.legacy_requirement = cls.root / "legacy.req"
        cls.migration_log = cls.root / "migration-commands"
        cls.fail_bootout = cls.root / "fail-bootout"
        cls.native_beta = cls.root / "native-beta"
        cls.caffelid_beta = cls.root / "caffelid-beta"
        cls.launchctl = cls.root / "launchctl"
        cls.pkgutil = cls.root / "pkgutil"
        for command in [cls.launchctl, cls.pkgutil]:
            command.write_text(
                '#!/bin/sh\n'
                f'if [ "$1" = "print" ]; then\n'
                f' if [ "$2" = "system/app.lungo.mac.sleep-service" ] && [ -e "{cls.native_beta}" ]; then exit 0; fi\n'
                f' if [ "$2" = "system/app.caffelid.mac.sleep-service" ] && [ -e "{cls.caffelid_beta}" ]; then exit 0; fi\n'
                ' exit 113; fi\n'
                f'printf "%s\\n" "$*" >> "{cls.migration_log}"\n'
                f'if [ "$1" = "bootout" ] && [ -e "{cls.fail_bootout}" ]; then exit 1; fi\n'
                f'if [ "$2" = "system/app.lungo.mac.sleep-service" ]; then rm -f "{cls.native_beta}"; fi\n'
                f'if [ "$2" = "system/app.caffelid.mac.sleep-service" ]; then rm -f "{cls.caffelid_beta}"; fi\n'
            )
            command.chmod(0o700)
        cls.path = str(cls.root / "control.sock")
        cls.fake = cls.root / "pmset"
        cls.fake.write_text(
            '#!/bin/sh\n'
            f'printf "%s\\n" "$*" >> "{cls.log}"\n'
            f'if [ "$3" = "1" ] && [ -e "{cls.fail_enable}" ]; then exit 1; fi\n'
            f'if [ "$3" = "0" ] && [ -e "{cls.fail_restore}" ]; then exit 1; fi\n'
        )
        cls.fake.chmod(0o700)
        cls.helper = cls.root / "helper"
        cls.client = cls.root / "client"
        common = [
            "xcrun", "clang", "-std=c17", "-Wall", "-Wextra", "-Werror", "-g",
            "-DCAFFELID_TESTING=1", f'-DCAFFELID_PMSET_PATH="{cls.fake}"',
            f'-DCAFFELID_LOCK_PATH="{cls.root / "lock"}"',
            f'-DCAFFELID_CLIENT_PATH="{cls.requirement}"', f'-DCAFFELID_SOCKET_PATH="{cls.path}"',
            f'-DCAFFELID_LEGACY_PLIST_PATH="{cls.legacy_plist}"',
            f'-DCAFFELID_LEGACY_EXECUTABLE_PATH="{cls.legacy_helper}"',
            f'-DCAFFELID_LEGACY_REQUIREMENT_PATH="{cls.legacy_requirement}"',
            f'-DCAFFELID_LAUNCHCTL_PATH="{cls.launchctl}"',
            f'-DCAFFELID_PKGUTIL_PATH="{cls.pkgutil}"',
            "-I", str(PROJECT / "Sources/CaffelidIPC/include"),
            str(PROJECT / "Sources/CaffelidIPC/IPC.c"),
            str(PROJECT / "Sources/CaffelidIPC/Service.c"), "-framework", "Security", "-framework", "CoreFoundation",
        ]
        subprocess.run(common + ["-fsanitize=address,undefined",
            str(PROJECT / "Sources/CaffelidHelper/main.c"),
            str(PROJECT / "Sources/CaffelidHelper/LegacyMigration.c"), "-o", str(cls.helper)], check=True)
        subprocess.run(common + [str(PROJECT / "Tests/service_client.c"), "-o", str(cls.client)], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(cls.client)], check=True)
        signature = subprocess.run(["codesign", "-d", "--verbose=4", str(cls.client)],
                                   capture_output=True, text=True, check=True).stderr
        cls.digest = re.search(r"^CDHash=([a-f0-9]{40})$", signature, re.MULTILINE).group(1)
        subprocess.run(["csreq", "-r", f'=cdhash H"{cls.digest}"', "-b", str(cls.requirement)], check=True)
        cls.requirement_data = cls.requirement.read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def setUp(self):
        for path in [self.log, self.fail_enable, self.fail_restore, self.legacy_plist,
                     self.legacy_helper, self.legacy_requirement, self.migration_log, self.fail_bootout,
                     self.native_beta, self.caffelid_beta]:
            path.unlink(missing_ok=True)
        self.requirement.unlink(missing_ok=True)
        self.requirement.write_bytes(self.requirement_data)
        self.requirement.chmod(0o600)
        Path(self.path).unlink(missing_ok=True)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen(8)
        self.processes = []

    def tearDown(self):
        self.fail_restore.unlink(missing_ok=True)
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
            out, err = process.communicate(timeout=10)
            self.assertNotIn(b"Sanitizer", err or b"")
        self.server.close()

    def commands(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def spawn(self):
        process = subprocess.Popen([str(self.helper), "--serve-test", str(self.server.fileno())],
            pass_fds=[self.server.fileno()], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.processes.append(process)
        return process

    def line(self, client):
        ready, _, _ = select.select([client.stdout], [], [], 8)
        self.assertTrue(ready, "Timed out waiting for service response")
        return client.stdout.readline().decode().strip()

    def connect(self):
        client = subprocess.Popen([str(self.client)], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.processes.append(client)
        self.assertEqual(self.line(client), "READY")
        return client

    def request(self, client, command):
        client.stdin.write((command + "\n").encode())
        client.stdin.flush()
        return self.line(client)

    def finish(self, process, code=0):
        out, err = process.communicate(timeout=10)
        self.assertEqual(process.returncode, code, (out + err).decode())
        self.assertNotIn(b"Sanitizer", err)

    def test_multiple_activations_use_the_same_installed_service(self):
        daemon = self.spawn()
        for _ in range(3):
            client = self.connect()
            self.assertEqual(self.request(client, "ON"), "ON")
            self.assertEqual(self.request(client, "OFF"), "OFF")
            self.finish(client)
        self.assertIsNone(daemon.poll())
        self.assertEqual(self.commands(), ["-a disablesleep 0"] +
                         ["-a disablesleep 1", "-a disablesleep 0"] * 3)

    def legacy_installation(self):
        self.legacy_plist.write_bytes(plistlib.dumps({
            "Label": "app.lungo.mac.helper",
            "ProgramArguments": [str(self.legacy_helper)],
        }))
        self.legacy_helper.write_text("previous helper")
        self.legacy_requirement.write_text("previous requirement")
        for path in [self.legacy_plist, self.legacy_helper, self.legacy_requirement]:
            path.chmod(0o600)

    def test_migrates_only_the_previous_lungo_installation(self):
        self.legacy_installation()
        unrelated = self.root / "unrelated.service"
        unrelated.write_text("keep")
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "RESET"), "OFF")
        for path in [self.legacy_plist, self.legacy_helper, self.legacy_requirement]:
            self.assertFalse(path.exists())
        self.assertEqual(unrelated.read_text(), "keep")
        self.assertEqual(self.migration_log.read_text().splitlines(),
                         ["bootout system/app.lungo.mac.helper", "--forget app.lungo.mac.support"])

    def test_no_legacy_installation_does_not_run_migration_commands(self):
        self.spawn()
        self.connect()
        self.assertFalse(self.migration_log.exists())

    def test_removes_native_beta_left_running_after_app_deletion(self):
        self.native_beta.touch()
        unrelated = self.root / "unrelated-native-service"
        unrelated.write_text("keep")
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ON")
        self.assertEqual(self.request(client, "OFF"), "OFF")
        self.assertFalse(self.native_beta.exists())
        self.assertEqual(unrelated.read_text(), "keep")
        self.assertEqual(self.migration_log.read_text().splitlines(),
                         ["bootout system/app.lungo.mac.sleep-service"])

    def test_retires_caffelid_beta_without_touching_unrelated_jobs(self):
        self.caffelid_beta.touch()
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ON")
        self.assertEqual(self.request(client, "OFF"), "OFF")
        self.assertFalse(self.caffelid_beta.exists())
        self.assertEqual(self.migration_log.read_text().splitlines(),
                         ["bootout system/app.caffelid.mac.sleep-service"])

    def test_failed_caffelid_beta_stop_prevents_power_changes(self):
        self.caffelid_beta.touch()
        self.fail_bootout.touch()
        self.finish(self.spawn(), 78)
        self.assertTrue(self.caffelid_beta.exists())
        self.assertEqual(self.commands(), [])

    def test_failed_native_beta_stop_prevents_power_changes(self):
        self.native_beta.touch()
        self.fail_bootout.touch()
        self.finish(self.spawn(), 78)
        self.assertTrue(self.native_beta.exists())
        self.assertEqual(self.commands(), [])

    def test_failed_legacy_stop_preserves_files_and_power_settings(self):
        self.legacy_installation()
        self.fail_bootout.touch()
        self.finish(self.spawn(), 78)
        self.assertTrue(self.legacy_plist.exists())
        self.assertTrue(self.legacy_helper.exists())
        self.assertTrue(self.legacy_requirement.exists())
        self.assertEqual(self.commands(), [])

    def test_unrecognized_legacy_job_is_left_untouched(self):
        self.legacy_installation()
        self.legacy_plist.write_bytes(plistlib.dumps({"Label": "unrelated"}))
        self.finish(self.spawn(), 78)
        self.assertTrue(self.legacy_helper.exists())
        self.assertFalse(self.migration_log.exists())
        self.assertEqual(self.commands(), [])

    def test_untrusted_legacy_files_are_left_untouched(self):
        self.legacy_installation()
        self.legacy_helper.chmod(0o666)
        self.finish(self.spawn(), 78)
        self.assertTrue(self.legacy_helper.exists())
        self.assertFalse(self.migration_log.exists())
        self.assertEqual(self.commands(), [])

    def test_legacy_symlink_is_left_untouched(self):
        self.legacy_installation()
        self.legacy_helper.unlink()
        self.legacy_helper.symlink_to(self.requirement)
        self.finish(self.spawn(), 78)
        self.assertTrue(self.legacy_helper.is_symlink())
        self.assertFalse(self.migration_log.exists())
        self.assertEqual(self.commands(), [])

    def test_gui_connection_loss_restores_sleep(self):
        daemon = self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ON")
        client.kill()
        client.wait(timeout=5)
        recovery = self.connect()  # Accepted only after the previous session restores.
        self.assertEqual(self.request(recovery, "RESET"), "OFF")
        self.assertIsNone(daemon.poll())
        self.assertEqual(self.commands(), ["-a disablesleep 0", "-a disablesleep 1",
                                          "-a disablesleep 0", "-a disablesleep 0"])

    def test_termination_restores_sleep(self):
        daemon = self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ON")
        daemon.send_signal(signal.SIGTERM)
        self.assertEqual(self.line(client), "OFF")
        self.finish(daemon)
        self.assertEqual(self.commands()[-1], "-a disablesleep 0")

    def test_rejects_unsigned_client(self):
        self.spawn()
        peer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        peer.settimeout(5)
        peer.connect(self.path)
        self.assertEqual(peer.recv(32), b"")
        peer.close()
        trusted = self.connect()
        self.assertEqual(self.request(trusted, "RESET"), "OFF")
        self.assertNotIn("-a disablesleep 1", self.commands())

    def test_rejects_wrong_signature(self):
        subprocess.run(["csreq", "-r", '=cdhash H"' + "0" * 40 + '"',
                        "-b", str(self.requirement)], check=True)
        self.spawn()
        client = subprocess.Popen([str(self.client)], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.processes.append(client)
        self.finish(client, 74)
        self.assertNotIn("-a disablesleep 1", self.commands())

    def test_refuses_writable_requirement(self):
        self.requirement.chmod(0o666)
        daemon = self.spawn()
        self.finish(daemon, 77)
        self.assertEqual(self.commands(), [])

    def test_refuses_symlink_requirement(self):
        target = self.root / "symlink-target"
        target.write_bytes(self.requirement_data)
        self.requirement.unlink()
        self.requirement.symlink_to(target)
        daemon = self.spawn()
        self.finish(daemon, 77)
        self.assertEqual(self.commands(), [])

    def test_failed_enable_is_rolled_back(self):
        self.fail_enable.touch()
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ERROR")
        self.assertEqual(self.commands()[:3], ["-a disablesleep 0", "-a disablesleep 1", "-a disablesleep 0"])

    def test_failed_restore_is_reported_and_retried(self):
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ON")
        self.fail_restore.touch()
        self.assertEqual(self.request(client, "OFF"), "ERROR")
        self.assertGreaterEqual(self.commands().count("-a disablesleep 0"), 4)

    def test_another_daemon_cannot_override_active_owner(self):
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ON")
        other = self.spawn()
        self.finish(other, 75)
        self.assertEqual(self.commands(), ["-a disablesleep 0", "-a disablesleep 1"])
        self.assertEqual(self.request(client, "OFF"), "OFF")

    def test_reset_does_not_enable(self):
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "RESET"), "OFF")
        self.assertEqual(self.commands(), ["-a disablesleep 0", "-a disablesleep 0"])

    def test_restart_after_hard_kill_starts_inactive(self):
        daemon = self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "ON"), "ON")
        daemon.kill()
        daemon.wait(timeout=5)
        self.finish(client)
        self.spawn()
        new_client = self.connect()
        self.assertEqual(self.commands()[-1], "-a disablesleep 0")
        self.assertEqual(self.request(new_client, "RESET"), "OFF")

    def test_unknown_command_does_not_enable(self):
        self.spawn()
        client = self.connect()
        self.assertEqual(self.request(client, "/bin/sh"), "ERROR")
        self.assertEqual(self.commands(), ["-a disablesleep 0"])

    def test_invalid_arguments_have_no_side_effects(self):
        for args in [[], ["--reset"], ["--serve-test", "-1"], ["--run", "whoami"]]:
            result = subprocess.run([str(self.helper)] + args, capture_output=True)
            self.assertEqual(result.returncode, 64, args)
        self.assertEqual(self.commands(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
