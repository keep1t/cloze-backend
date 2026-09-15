import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gate', ROOT / 'scripts/security_gate.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class HooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cloze-hook-test-')
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Synthetic Test')
        self.git('config', 'user.email', 'test@example.invalid')
        shutil.copytree(ROOT / '.githooks', self.repo / '.githooks')
        (self.repo / 'scripts').mkdir()
        shutil.copy(ROOT / 'scripts/security_gate.py', self.repo / 'scripts/security_gate.py')
        shutil.copy(ROOT / 'scripts/tool-versions.json', self.repo / 'scripts/tool-versions.json')
        (self.repo / '.tools').mkdir()
        shutil.copy(ROOT / '.tools/gitleaks', self.repo / '.tools/gitleaks')
        (self.repo / '.tools/gitleaks').chmod(0o755)
        self.git('config', 'core.hooksPath', '.githooks')

    def git(self, *args, input=None, check=True):
        return subprocess.run(['git', *args], cwd=self.repo, input=input,
                              text=True, capture_output=True, check=check)

    def test_real_commit_accepts_clean_content(self):
        (self.repo / 'README.md').write_text('Synthetic fixture\n')
        self.git('add', 'README.md')
        self.assertEqual(self.git('commit', '-qm', 'clean', check=False).returncode, 0)

    def test_real_commit_blocks_index_secret_even_after_worktree_fix(self):
        fake = 'ghp_' + '0123456789abcdef' * 2 + 'abcd'
        path = self.repo / 'credentials.txt'
        path.write_text('token=' + fake)
        self.git('add', 'credentials.txt')
        path.write_text('removed from worktree only')
        result = self.git('commit', '-qm', 'blocked', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Security gate failed', result.stderr)
        self.assertNotIn(fake, result.stdout + result.stderr)

    def test_real_commit_blocks_hardcoded_setting(self):
        (self.repo / 'handler.ts').write_text('const timeoutMs = 5000;\n')
        self.git('add', 'handler.ts')
        self.assertNotEqual(self.git('commit', '-qm', 'blocked', check=False).returncode, 0)

    def test_push_blocks_secret_removed_from_tip(self):
        # Build synthetic history with plumbing; no real secret and no hook bypass flags.
        (self.repo / 'old.txt').write_text('token=' + 'ghp_' + '0123456789abcdef' * 2 + 'abcd')
        self.git('add', 'old.txt')
        tree = self.git('write-tree').stdout.strip()
        first = self.git('commit-tree', tree, '-m', 'synthetic historical fixture').stdout.strip()
        self.git('rm', '-f', 'old.txt')
        tree = self.git('write-tree').stdout.strip()
        tip = self.git('commit-tree', tree, '-p', first, '-m', 'removed').stdout.strip()
        self.git('update-ref', 'refs/heads/check', tip)
        remote = Path(self.temp.name) / 'remote.git'
        self.git('init', '--bare', str(remote))
        result = self.git('push', str(remote), 'refs/heads/check', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Security gate failed', result.stderr)

    def test_push_blocks_secret_in_ref_name_without_echoing_it(self):
        fake = 'ghp_' + '0123456789abcdef' * 2 + 'abcd'
        input_data = f'refs/heads/{fake} {"1" * 40} refs/heads/remote {"2" * 40}\n'
        result = subprocess.run(
            ['python3', 'scripts/security_gate.py', 'push'], cwd=self.repo,
            input=input_data, text=True, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Security gate failed', result.stderr)
        self.assertNotIn(fake, result.stdout + result.stderr)

    def test_push_rejects_malformed_input(self):
        result = subprocess.run(
            ['python3', 'scripts/security_gate.py', 'push'], cwd=self.repo,
            input='malformed\n', text=True, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('malformed', result.stdout + result.stderr)

    def test_patterns_and_environment_examples(self):
        self.assertTrue(gate.violations('.env.example', b'GEMINI_API_KEY=nonempty'))
        self.assertFalse(gate.violations('.env.example', b'GEMINI_API_KEY=\n'))
        self.assertTrue(gate.violations('a.ts', b'const x = Deno.env.get("X") ?? "fallback";'))
        self.assertFalse(gate.violations('a.ts', b'const timeoutMs = config.requestTimeoutMs;'))

    def test_scanner_error_blocks(self):
        with self.assertRaises(RuntimeError):
            gate.scan([('safe.txt', b'safe')], '/usr/bin/false')

    def test_scanner_environment_is_allowlisted(self):
        self.assertEqual(gate.scanner_environment(), {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})

    def test_range_scans_removed_secret_from_intermediate_commit(self):
        base_tree = self.git('write-tree').stdout.strip()
        base = self.git('commit-tree', base_tree, '-m', 'synthetic base').stdout.strip()
        fake = 'ghp_' + '0123456789abcdef' * 2 + 'abcd'
        (self.repo / 'history.txt').write_text('token=' + fake)
        self.git('add', 'history.txt')
        exposed = self.git('write-tree').stdout.strip()
        middle = self.git('commit-tree', exposed, '-p', base, '-m', 'synthetic middle').stdout.strip()
        self.git('rm', '-f', 'history.txt')
        clean = self.git('write-tree').stdout.strip()
        head = self.git('commit-tree', clean, '-p', middle, '-m', 'synthetic head').stdout.strip()
        result = subprocess.run(
            ['python3', 'scripts/security_gate.py', 'range', base, head],
            cwd=self.repo, text=True, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(fake, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
