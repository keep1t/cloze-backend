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


if __name__ == "__main__":
    unittest.main()
