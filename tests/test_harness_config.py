import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    'install_gitleaks', ROOT / 'scripts/install_gitleaks.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
gate_spec = importlib.util.spec_from_file_location(
    'security_gate', ROOT / 'scripts/security_gate.py')
gate = importlib.util.module_from_spec(gate_spec)
gate_spec.loader.exec_module(gate)


class HarnessConfigTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads((ROOT / 'opencode.json').read_text())

    def test_all_roles_are_subagents_with_external_access_and_delegation_denied(self):
        roles = self.config['agent']
        self.assertEqual(set(roles), {
            'cloze-architect', 'cloze-test-author', 'cloze-developer', 'cloze-reviewer'})
        for name, role in roles.items():
            permission = role['permission']
            self.assertEqual(role['mode'], 'subagent')
            self.assertEqual(permission['external_directory'], 'deny')
            self.assertEqual(permission['task'], 'deny')
            web_access = 'deny' if name == 'cloze-test-author' else 'ask'
            self.assertEqual(permission['webfetch'], web_access)
            self.assertEqual(permission['websearch'], web_access)
            self.assertEqual(permission['read']['**/.env'], 'deny')
            self.assertEqual(permission['read']['**/.env.example'], 'allow')
            self.assertEqual(permission['read']['**/credentials*'], 'deny')
            self.assertEqual(permission['read']['**/.ssh/**'], 'deny')
            self.assertEqual(permission['read']['supabase/.temp/**'], 'deny')
            self.assertEqual(permission['vercel_*'], 'deny')
            self.assertEqual(permission['read']['**/*.pem'], 'deny')

    def test_root_level_secret_read_paths_are_denied(self):
        paths = ('.env', 'signing_keys.json', '.npmrc')
        for role in self.config['agent'].values():
            rules = role['permission']['read']
            for path in paths:
                self.assertEqual(rules.get(path), 'deny', (path, rules.get(path)))
            for pattern in ('*.pem', '*.key', '*.p12', '*.pfx', 'credentials*',
                            '*credentials*', '.ssh/**'):
                self.assertEqual(rules.get(pattern), 'deny', (pattern, rules.get(pattern)))
            self.assertEqual(rules.get('.env.example'), 'allow')

    def test_architect_and_reviewer_are_read_only(self):
        for name in ('cloze-architect', 'cloze-reviewer'):
            permission = self.config['agent'][name]['permission']
            self.assertEqual(permission['edit'], 'deny')
            self.assertEqual(permission['bash'], 'deny')

    def test_test_author_can_edit_only_supabase_tests(self):
        permission = self.config['agent']['cloze-test-author']['permission']
        self.assertEqual(permission['edit'], {'*': 'deny', 'supabase/tests/**': 'allow'})
        self.assertEqual(permission['bash'], 'deny')

    def test_developer_requires_approval_for_unlisted_commands_and_blocks_publication(self):
        bash = self.config['agent']['cloze-developer']['permission']['bash']
        self.assertEqual(bash['*'], 'ask')
        self.assertEqual(bash['git status --short'], 'allow')
        self.assertEqual(bash['git diff --check'], 'allow')
        for command in ('python3 -m unittest*', 'python3 scripts/security_gate.py*',
                        'python3 scripts/install_gitleaks.py*', 'deno test*',
                        'deno fmt --check*', 'deno lint*'):
            self.assertNotIn(command, bash)
        self.assertNotIn('git diff*', bash)
        self.assertNotIn('git log*', bash)
        for command in ('git commit*', 'git push*', 'git reset*', 'git clean*',
                        'supabase functions deploy*', 'supabase db reset*',
                        'supabase secrets*', 'docker system prune*', 'printenv*'):
            self.assertEqual(bash[command], 'deny')

    def test_pipeline_requires_coordinator_verified_failure_before_ready(self):
        workflow = (ROOT / 'docs/development-workflow.md').read_text()
        atomic = (ROOT / 'docs/atomic-tasks.md').read_text()
        prompt = (ROOT / '.cursor/agents/cloze-test-author.md').read_text()
        self.assertIn('DESIGN_READY', workflow)
        self.assertIn('expected-failure evidence', workflow)
        self.assertIn('mark the task READY', atomic)
        self.assertIn('Never claim a test was run or passed', prompt)

    def test_ci_workflow_is_read_only_and_runs_all_gate_modes(self):
        workflow = (ROOT / '.github/workflows/security-gate.yml').read_text()
        self.assertIn('pull_request:', workflow)
        self.assertIn('push:', workflow)
        self.assertIn('branches: [main]', workflow)
        self.assertIn('permissions:\n  contents: read', workflow)
        self.assertIn('actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683', workflow)
        self.assertIn('fetch-depth: 0', workflow)
        self.assertIn('name: security-gate', workflow)
        for command in ('scripts/install_gitleaks.py', '-m unittest discover -s tests',
                        'scripts/security_gate.py worktree', 'scripts/security_gate.py range'):
            self.assertIn(command, workflow)
        self.assertNotIn('pull_request_target', workflow)
        self.assertNotIn('secrets.', workflow)

    def test_installer_supports_only_pinned_linux_architectures(self):
        x64, _, _ = installer.release_target('Linux', 'x86_64')
        arm64, _, _ = installer.release_target('Linux', 'aarch64')
        self.assertEqual(x64, 'gitleaks_8.24.3_linux_x64.tar.gz')
        self.assertEqual(arm64, 'gitleaks_8.24.3_linux_arm64.tar.gz')
        with self.assertRaises(RuntimeError):
            installer.release_target('Darwin', 'x86_64')

    def test_installer_rejects_checksum_mismatch(self):
        with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
            installer.extract_binary(b'not an archive', '0' * 64)

    def test_installer_rejects_unsafe_archive_members(self):
        archive_buffer = io.BytesIO()
        with tarfile.open(fileobj=archive_buffer, mode='w:gz') as archive:
            member = tarfile.TarInfo('../gitleaks')
            member.size = 4
            archive.addfile(member, io.BytesIO(b'data'))
        archive_data = archive_buffer.getvalue()
        with self.assertRaisesRegex(RuntimeError, 'unexpected contents'):
            installer.extract_binary(archive_data, hashlib.sha256(archive_data).hexdigest())

    def test_scanner_ignores_path_shadow_and_rejects_wrong_managed_version(self):
        from tempfile import TemporaryDirectory
        from unittest.mock import patch

        with TemporaryDirectory(prefix='cloze-scanner-test-') as temporary:
            project = Path(temporary) / 'project'
            scripts = project / 'scripts'
            managed = project / '.tools' / 'gitleaks'
            shadow = Path(temporary) / 'path' / 'gitleaks'
            scripts.mkdir(parents=True)
            managed.parent.mkdir()
            shadow.parent.mkdir()
            (scripts / 'security_gate.py').touch()
            (scripts / 'tool-versions.json').write_text(
                json.dumps(json.loads((ROOT / 'scripts/tool-versions.json').read_text())))
            managed.write_text('#!/bin/sh\nprintf "8.24.2\\n"\n')
            shadow.write_text('#!/bin/sh\nprintf "8.24.3\\n"\n')
            managed.chmod(0o755)
            shadow.chmod(0o755)
            config = json.loads((ROOT / 'scripts/tool-versions.json').read_text())
            with patch.object(gate, '__file__', str(scripts / 'security_gate.py')):
                with patch.dict('os.environ', {'PATH': str(shadow.parent)}):
                    with self.assertRaisesRegex(RuntimeError, 'executable checksum mismatch'):
                        gate.scanner()
            config['gitleaks']['binary_sha256']['linux_x64'] = hashlib.sha256(
                managed.read_bytes()).hexdigest()
            (scripts / 'tool-versions.json').write_text(json.dumps(config))
            with patch.object(gate, '__file__', str(scripts / 'security_gate.py')):
                with patch.dict('os.environ', {'PATH': str(shadow.parent)}):
                    with self.assertRaisesRegex(RuntimeError, 'version mismatch'):
                        gate.scanner()
                    managed.write_text('#!/bin/sh\nprintf "8.24.3\\n"\n')
                    config['gitleaks']['binary_sha256']['linux_x64'] = hashlib.sha256(
                        managed.read_bytes()).hexdigest()
                    (scripts / 'tool-versions.json').write_text(json.dumps(config))
                    self.assertEqual(gate.scanner(), managed)

    def test_scanner_child_does_not_receive_parent_environment(self):
        import os
        import tempfile

        with tempfile.TemporaryDirectory(prefix='cloze-scanner-env-') as temporary:
            marker = Path(temporary) / 'scanner-env.txt'
            executable = Path(temporary) / 'fake-gitleaks'
            executable.write_text(f'#!/bin/sh\n/usr/bin/env > {marker}\n')
            executable.chmod(0o755)
            previous = os.environ.get('CLOZE_SYNTHETIC_SECRET')
            os.environ['CLOZE_SYNTHETIC_SECRET'] = 'synthetic-only'
            try:
                gate.scan([('safe.txt', b'safe')], str(executable))
            finally:
                if previous is None:
                    os.environ.pop('CLOZE_SYNTHETIC_SECRET', None)
                else:
                    os.environ['CLOZE_SYNTHETIC_SECRET'] = previous
            self.assertNotIn('CLOZE_SYNTHETIC_SECRET', marker.read_text())


if __name__ == '__main__':
    unittest.main()
