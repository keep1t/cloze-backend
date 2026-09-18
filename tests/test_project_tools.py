import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "project_tools", ROOT / "scripts" / "project_tools.py"
)
project_tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(project_tools)
runner_spec = importlib.util.spec_from_file_location(
    "db_concurrency_runner", ROOT / "scripts" / "db_concurrency_runner.py"
)
concurrency_runner = importlib.util.module_from_spec(runner_spec)
runner_spec.loader.exec_module(concurrency_runner)


class ProjectToolsTest(unittest.TestCase):
    def test_project_reference_requires_supabase_reference_shape(self):
        reference = "a" * 20
        self.assertEqual(project_tools.validate_project_ref(reference), reference)
        for invalid in (None, "short", "A" * 20, "a" * 19 + "-"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(project_tools.ProjectToolError):
                    project_tools.validate_project_ref(invalid)

    def test_remote_confirmation_must_match_exact_reference(self):
        reference = "b" * 20
        project_tools.require_remote_confirmation(reference, reference)
        for confirmation in (None, "c" * 20):
            with self.subTest(confirmation=confirmation):
                with self.assertRaises(project_tools.ProjectToolError):
                    project_tools.require_remote_confirmation(reference, confirmation)

    def test_remote_link_validates_confirmation_before_cli(self):
        with patch.object(project_tools.subprocess, "run") as run:
            with self.assertRaises(project_tools.ProjectToolError):
                project_tools.remote_link("supabase", "a" * 20, "wrong")
            run.assert_not_called()

            reference = "a" * 20
            with contextlib.redirect_stdout(io.StringIO()):
                project_tools.remote_link("supabase", reference, reference)
            self.assertEqual(
                run.call_args.args[0],
                ["supabase", "link", "--project-ref", reference],
            )

    def test_linked_project_must_match_confirmed_reference(self):
        reference = "a" * 20
        with tempfile.TemporaryDirectory(prefix="cloze-link-test-") as temp:
            project_root = Path(temp)
            link_file = project_root / "supabase" / ".temp" / "project-ref"
            link_file.parent.mkdir(parents=True)
            link_file.write_text("b" * 20)
            with patch.object(project_tools, "ROOT", project_root):
                with self.assertRaises(project_tools.ProjectToolError):
                    project_tools.assert_linked_project(reference)

    def test_db_push_rejects_link_mismatch_before_dry_run(self):
        reference = "a" * 20
        with patch.object(
            project_tools,
            "assert_linked_project",
            side_effect=project_tools.ProjectToolError("linked reference mismatch"),
        ):
            with patch.object(project_tools, "run_quietly") as run_quietly:
                with self.assertRaises(project_tools.ProjectToolError):
                    project_tools.push_database("supabase", reference, reference)
                run_quietly.assert_not_called()

    def test_db_reset_requires_configured_local_project_confirmation(self):
        project_id = project_tools.local_project_id()
        with patch.object(project_tools.subprocess, "run") as run:
            with self.assertRaises(project_tools.ProjectToolError):
                project_tools.reset_database("supabase", "wrong")
            run.assert_not_called()
            project_tools.reset_database("supabase", project_id)
            self.assertEqual(
                run.call_args.args[0],
                ["supabase", "db", "reset", "--local", "--yes"],
            )

    def test_migration_name_is_validated_before_supabase_cli(self):
        with patch.object(project_tools.subprocess, "run") as run:
            for invalid in (None, "BadName", "bad-name", "../bad", "bad__name"):
                with self.subTest(invalid=invalid):
                    with self.assertRaises(project_tools.ProjectToolError):
                        project_tools.create_migration("supabase", invalid)
            run.assert_not_called()

            project_tools.create_migration("supabase", "create_shares")
            self.assertEqual(
                run.call_args.args[0],
                ["supabase", "migration", "new", "create_shares"],
            )

    def test_db_push_dry_run_precedes_remote_apply(self):
        reference = "a" * 20
        calls = []

        def quiet(command, **_kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, "", "")

        with patch.object(project_tools, "assert_linked_project"):
            with patch.object(project_tools, "run_quietly", side_effect=quiet):
                with contextlib.redirect_stdout(io.StringIO()):
                    project_tools.push_database("supabase", reference, reference)

        self.assertEqual(calls, [
            ["supabase", "db", "push", "--linked", "--dry-run"],
            ["supabase", "db", "push", "--linked", "--yes"],
        ])

    def test_db_push_does_not_apply_after_failed_dry_run(self):
        reference = "a" * 20
        calls = []

        def quiet(command, **_kwargs):
            calls.append(command)
            raise project_tools.ProjectToolError("dry-run failed")

        with patch.object(project_tools, "assert_linked_project"):
            with patch.object(project_tools, "run_quietly", side_effect=quiet):
                with self.assertRaises(project_tools.ProjectToolError):
                    project_tools.push_database("supabase", reference, reference)
        self.assertEqual(len(calls), 1)
        self.assertIn("--dry-run", calls[0])

    def test_deploy_targets_only_named_function_after_check(self):
        reference = "a" * 20
        with tempfile.TemporaryDirectory(prefix="cloze-function-test-") as temp:
            function_root = Path(temp)
            (function_root / "share-outfit").mkdir()
            events = []

            def run(command, **_kwargs):
                events.append(command)
                return subprocess.CompletedProcess(command, 0, "", "")

            with patch.object(project_tools, "FUNCTIONS", function_root):
                with patch.object(project_tools, "assert_linked_project"):
                    with patch.object(project_tools.subprocess, "run", side_effect=run):
                        with patch.object(
                            project_tools, "run_quietly", side_effect=run
                        ):
                            with contextlib.redirect_stdout(io.StringIO()):
                                project_tools.deploy_function(
                                    "supabase", "share-outfit", reference, reference
                                )

        self.assertEqual(events[0], ["make", "check"])
        self.assertEqual(
            events[1], ["supabase", "functions", "deploy", "share-outfit"]
        )

    def test_deploy_rejects_invalid_function_before_check_or_cli(self):
        reference = "a" * 20
        with patch.object(project_tools.subprocess, "run") as run:
            with patch.object(project_tools, "run_quietly") as run_quietly:
                with self.assertRaises(project_tools.ProjectToolError):
                    project_tools.deploy_function(
                        "supabase", "../function", reference, reference
                    )
                run.assert_not_called()
                run_quietly.assert_not_called()

    def test_status_does_not_print_supabase_urls_or_keys(self):
        secret_marker = "synthetic-status-key"
        command_output = (
            '{"api_url":"https://example.invalid",'
            f'"anon_key":"{secret_marker}"}}'
        )
        output = io.StringIO()
        with patch.object(
            project_tools,
            "run_quietly",
            return_value=subprocess.CompletedProcess(
                ["supabase", "status"], 0, command_output, ""
            ),
        ):
            with contextlib.redirect_stdout(output):
                project_tools.safe_status("supabase")
        self.assertIn("stack is running", output.getvalue())
        self.assertNotIn(secret_marker, output.getvalue())
        self.assertNotIn("example.invalid", output.getvalue())

    def test_types_check_skips_before_first_generated_artifact(self):
        with tempfile.TemporaryDirectory(prefix="cloze-types-test-") as temp:
            generated = Path(temp) / "database.types.ts"
            output = io.StringIO()
            with patch.object(project_tools, "GENERATED_TYPES", generated):
                with patch.object(project_tools, "generated_types") as generate:
                    with contextlib.redirect_stdout(output):
                        project_tools.check_types("supabase")
                    generate.assert_not_called()
            self.assertIn("skipped", output.getvalue())

    def test_test_file_discovery_includes_plain_test_entrypoint(self):
        with tempfile.TemporaryDirectory(prefix="cloze-test-discovery-") as temp:
            paths = [
                Path(temp) / "test.ts",
                Path(temp) / "helpers.ts",
                Path(temp) / "handler_test.ts",
            ]
            with patch.object(project_tools, "source_files", return_value=paths):
                self.assertEqual(project_tools.test_files(), [paths[0], paths[2]])

    def test_generated_types_use_repository_formatter(self):
        generated = 'export const label: string = "outfit";\n'
        with patch.object(
            project_tools,
            "run_quietly",
            return_value=subprocess.CompletedProcess(
                ["supabase", "gen", "types"], 0, generated, ""
            ),
        ):
            self.assertEqual(
                project_tools.generated_types("supabase"),
                b"export const label: string = 'outfit';\n",
            )

    def test_concurrency_status_parser_does_not_accept_missing_or_malformed_status(self):
        self.assertEqual(
            concurrency_runner.database_url_from_status('{"DB_URL":"postgresql://u:p@localhost:5432/db"}'),
            "postgresql://u:p@localhost:5432/db",
        )
        for value in ("{}", "not-json", '{"DB_URL":null}'):
            with self.subTest(value=value):
                with self.assertRaises(concurrency_runner.ConcurrencyError):
                    concurrency_runner.database_url_from_status(value)

    def test_concurrency_connection_rejects_non_loopback_and_malformed_urls(self):
        for value in (
            "postgresql://u:p@example.invalid:5432/db",
            "postgresql://u:p@localhost/db",
            "https://u:p@localhost:5432/db",
            "not-a-url",
        ):
            with self.subTest(value=value):
                with self.assertRaises(concurrency_runner.ConcurrencyError):
                    concurrency_runner.connection_parts(value)

    def test_concurrency_manifest_schema_and_filename_are_strict(self):
        valid = {
            "name": "smoke",
            "bootstrap_sql": "select '{{USER_ID}}';",
            "create_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "lock_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}', false;",
            "replay_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "teardown_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "replay_marker": "REPLAY_OK", "lock_expression": concurrency_runner.LOCK_EXPRESSION,
            "lock_input": concurrency_runner.LOCK_INPUT,
        }
        with tempfile.TemporaryDirectory(prefix="cloze-manifest-test-") as temp:
            path = Path(temp) / "smoke.json"
            path.write_text(__import__("json").dumps(valid), encoding="utf-8")
            self.assertEqual(concurrency_runner.load_manifest(path)["name"], "smoke")
            path.write_text(__import__("json").dumps({**valid, "unknown": "x"}), encoding="utf-8")
            with self.assertRaises(concurrency_runner.ConcurrencyError):
                concurrency_runner.load_manifest(path)
            (Path(temp) / "bad.name.json").write_text(__import__("json").dumps(valid), encoding="utf-8")
            with self.assertRaises(concurrency_runner.ConcurrencyError):
                concurrency_runner.discover_manifests(Path(temp))

    def test_concurrency_allows_only_empty_auth_password_fixture(self):
        exact = "insert into auth.users (id, encrypted_password) values ('00000000-0000-0000-0000-000000000000', '');"
        self.assertTrue(concurrency_runner._allows_empty_auth_fixture(exact))
        rejected = (
            exact.replace("''", "'not-empty'"),
            exact.replace("''", "null"),
            exact.replace("''", "cast('' as text)"),
            exact.replace("encrypted_password", '"encrypted_password"'),
            exact.replace("encrypted_password", "password_hash"),
            exact.replace("auth.users", "public.users"),
            exact.replace(";", " returning id;"),
            exact.replace(";", " -- comment\n;"),
            "insert into auth.users (id, encrypted_password, note) values ('x', '', 'password');",
            "insert into auth.users (id, encrypted_password, encrypted_password) values ('x', '', '');",
        )
        for sql in rejected:
            with self.subTest(sql=sql):
                self.assertFalse(concurrency_runner._allows_empty_auth_fixture(sql))

    def test_concurrency_rejects_psql_metacommands_program_and_unsafe_marker(self):
        valid = {
            "name": "smoke", "bootstrap_sql": "select '{{USER_ID}}';",
            "create_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "lock_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "replay_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "teardown_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "replay_marker": "REPLAY_OK", "lock_expression": concurrency_runner.LOCK_EXPRESSION, "lock_input": concurrency_runner.LOCK_INPUT,
        }
        for field, fragment in (("create_sql", "select 1; \\! id"), ("lock_sql", "select 1; \\copy x to program 'id'"), ("replay_sql", "copy x from program 'id'")):
            with self.subTest(field=field):
                with tempfile.TemporaryDirectory() as temp:
                    path = Path(temp) / "smoke.json"
                    path.write_text(__import__("json").dumps({**valid, field: fragment}), encoding="utf-8")
                    with self.assertRaises(concurrency_runner.ConcurrencyError):
                        concurrency_runner.load_manifest(path)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "smoke.json"
            path.write_text(__import__("json").dumps({**valid, "replay_marker": "bad marker;"}), encoding="utf-8")
            with self.assertRaises(concurrency_runner.ConcurrencyError):
                concurrency_runner.load_manifest(path)

    def test_concurrency_finish_extracts_expected_scalar_marker(self):
        class FakeStream:
            def __init__(self): self.writes = []
            def write(self, value): self.writes.append(value)
            def flush(self): pass
            def close(self): pass
            def read(self): return "\nfalse\nREPLAY_OK\n"

        class FakeProcess:
            stdin = FakeStream()
            stdout = FakeStream()
            returncode = 0
            def wait(self): pass

        self.assertEqual(concurrency_runner._finish(FakeProcess(), "commit;", "REPLAY_OK"), "REPLAY_OK")

    def test_concurrency_finish_allows_marker_free_empty_output(self):
        class Stream:
            def write(self, _value): pass
            def close(self): pass
            def read(self): return ""
        class Process:
            stdin = Stream()
            stdout = Stream()
            returncode = 0
            def wait(self): pass
        self.assertEqual(concurrency_runner._finish(Process(), "commit;", None), "")

    def test_concurrency_required_marker_rejects_empty_output(self):
        class Stream:
            def write(self, _value): pass
            def close(self): pass
            def read(self): return ""
        class Process:
            stdin = Stream()
            stdout = Stream()
            returncode = 0
            def wait(self): pass
        with self.assertRaises(concurrency_runner.ConcurrencyError):
            concurrency_runner._finish(Process(), "select 1;", "REPLAY_OK")

    def test_concurrency_manifest_process_order_and_cleanup_on_both_outcomes(self):
        manifest = {
            "name": "smoke", "bootstrap_sql": "select '{{USER_ID}}';",
            "create_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "lock_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "replay_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "teardown_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "replay_marker": "REPLAY_OK", "lock_expression": concurrency_runner.LOCK_EXPRESSION, "lock_input": concurrency_runner.LOCK_INPUT,
        }
        class FakeProcess:
            def __init__(self): self.returncode = 0
            def poll(self): return 0
            def wait(self): pass
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            path = directory / "smoke.json"
            path.write_text(__import__("json").dumps(manifest), encoding="utf-8")
            events = []
            def phase(command, environment, sql, marker=None):
                events.append(("phase", marker, sql)); return FakeProcess()
            def finish(process, sql, expected_marker=None):
                events.append(("finish", sql, expected_marker)); return expected_marker or ""
            with patch.object(concurrency_runner, "MANIFESTS", directory), patch.object(concurrency_runner, "_phase", side_effect=phase), patch.object(concurrency_runner, "_finish", side_effect=finish):
                concurrency_runner.run_manifest(concurrency_runner.load_manifest(path), ["psql"], {"PGPASSFILE": "x"})
            self.assertEqual([event[0] for event in events], ["phase", "finish", "phase", "phase", "finish", "finish", "phase", "finish"])
            self.assertEqual([event[2] for event in events if event[0] == "finish"], [None, None, "REPLAY_OK", None])

    def test_concurrency_run_removes_password_file_after_success_and_failure(self):
        manifest = {"name": "smoke", "bootstrap_sql": "select '{{USER_ID}}';", "create_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "lock_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "replay_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "teardown_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "replay_marker": "OK", "lock_expression": concurrency_runner.LOCK_EXPRESSION, "lock_input": concurrency_runner.LOCK_INPUT}
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); (directory / "smoke.json").write_text(__import__("json").dumps(manifest), encoding="utf-8")
            seen = []
            commands = []
            def observe(_manifest, _command, environment):
                seen.append(Path(environment["PGPASSFILE"]))
                commands.append(_command)
                self.assertEqual(Path(environment["PGPASSFILE"]).stat().st_mode & 0o777, 0o600)
                self.assertNotIn("postgresql://", " ".join(_command))
                self.assertNotIn("synthetic-password", " ".join(_command))
            result = subprocess.CompletedProcess(["supabase"], 0, '{"DB_URL":"postgresql://postgres:pass@localhost:54322/postgres"}', "")
            with patch.object(concurrency_runner, "MANIFESTS", directory), patch.object(concurrency_runner.subprocess, "run", return_value=result), patch.object(concurrency_runner.shutil, "which", return_value="/bin/psql"), patch.object(concurrency_runner, "run_manifest", side_effect=observe):
                concurrency_runner.run("supabase")
            self.assertFalse(seen[0].exists())
            self.assertEqual(commands[0][0], "/bin/psql")
            self.assertNotIn("shell", " ".join(commands[0]))
            with patch.object(concurrency_runner, "MANIFESTS", directory), patch.object(concurrency_runner.subprocess, "run", return_value=result), patch.object(concurrency_runner.shutil, "which", return_value="/bin/psql"), patch.object(concurrency_runner, "run_manifest", side_effect=concurrency_runner.ConcurrencyError("sanitized")):
                with self.assertRaises(concurrency_runner.ConcurrencyError):
                    concurrency_runner.run("supabase")
            self.assertFalse(seen[0].exists())

    def test_concurrency_subprocess_failures_are_sanitized(self):
        secret_url = "postgresql://postgres:synthetic-password@localhost:54322/postgres"
        result = subprocess.CompletedProcess(["supabase"], 1, secret_url, secret_url)
        with patch.object(concurrency_runner, "discover_manifests", return_value=[Path("synthetic.json")]), patch.object(concurrency_runner.subprocess, "run", return_value=result):
            with self.assertRaises(concurrency_runner.ConcurrencyError) as error:
                concurrency_runner.run("supabase")
        self.assertNotIn("synthetic-password", str(error.exception))
        self.assertNotIn("postgresql://", str(error.exception))

    def test_concurrency_lock_marker_is_generated_and_cannot_be_manifest_spoofed(self):
        manifest = {
            "name": "smoke", "bootstrap_sql": "select '{{USER_ID}}';",
            "create_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "lock_sql": "select 'B_LOCK=f', '{{USER_ID}}', '{{OPERATION_ID}}';",
            "replay_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';", "teardown_sql": "select '{{USER_ID}}', '{{OPERATION_ID}}';",
            "replay_marker": "OK", "lock_expression": concurrency_runner.LOCK_EXPRESSION, "lock_input": concurrency_runner.LOCK_INPUT,
        }
        class Process:
            def poll(self): return 0
            def wait(self): pass
        phases = []
        def phase(command, environment, sql, marker=None):
            phases.append((sql, marker))
            if marker and marker.startswith("__CLOZE_B_LOCK_"):
                self.assertNotEqual(marker, "B_LOCK=f")
                self.assertIn("pg_try_advisory_xact_lock", sql)
            return Process()
        with patch.object(concurrency_runner, "_phase", side_effect=phase), patch.object(concurrency_runner, "_finish", return_value="OK"):
            concurrency_runner.run_manifest(manifest, ["/bin/psql"], {"PGPASSFILE": "x"})
        self.assertTrue(any(marker and marker.startswith("__CLOZE_B_LOCK_") for _, marker in phases))


if __name__ == "__main__":
    unittest.main()
