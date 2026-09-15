#!/usr/bin/env python3
"""Scan exact Git snapshots; diagnostics never contain matched content."""
import os
from pathlib import Path
import hashlib
import json
import platform
import re
import subprocess
import sys
import tempfile


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL)


def scanner():
    root = Path(__file__).resolve().parents[1]
    config = json.loads((root / 'scripts/tool-versions.json').read_text())['gitleaks']
    architecture = {'x86_64': 'x64', 'aarch64': 'arm64'}.get(platform.machine())
    if platform.system() != 'Linux' or architecture is None:
        raise RuntimeError('Security gate supports Linux x64 and arm64 only.')
    platform_key = f'linux_{architecture}'
    binary = root / '.tools' / 'gitleaks'
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise RuntimeError('Verified Gitleaks missing. Run python3 scripts/install_gitleaks.py.')
    if hashlib.sha256(binary.read_bytes()).hexdigest() != config['binary_sha256'][platform_key]:
        raise RuntimeError('Gitleaks executable checksum mismatch; reinstall the verified version.')
    completed = subprocess.run([str(binary), 'version'], check=True,
                               capture_output=True, env=scanner_environment())
    version = (completed.stdout + completed.stderr).decode('utf-8', errors='replace').strip()
    if version != config['version']:
        raise RuntimeError('Gitleaks version mismatch; reinstall the verified version.')
    return binary


def scanner_environment():
    return {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}


def valid_object_id(value):
    return len(value) in (40, 64) and re.fullmatch(r'[0-9a-fA-F]+', value) is not None


SOURCE = {'.ts', '.tsx', '.js', '.mjs', '.cjs', '.sql', '.py', '.sh'}
PATTERNS = {
    'literal endpoint or machine path': r'''["'`](?:https?://|postgres(?:ql)?://|/home/|/Users/)[^"'`\s]+''',
    'environment fallback': r'''(?:Deno\.env\.get|os\.getenv|os\.environ\.get)\([^\n]*\)\s*(?:\|\||\?\?|or)\s*["'`\d]''',
    'literal operational setting': r'''(?ix)\b[\w]*(?:timeout|retries|retry_count|quota|price|port|model|endpoint|project_id|feature_flag|limit)[\w]*\s*(?::[^=;\n]+)?\s*(?:=|:)\s*(?:["'`][^"'`]+["'`]|\d+|true\b|false\b)''',
}


def violations(name, data):
    path = Path(name)
    result = []
    if (path.name.startswith('.env') and path.name != '.env.example') or path.suffix in {'.pem', '.key', '.p12', '.pfx'} or path.name == 'signing_keys.json':
        result.append('credential file prohibited')
    text = data.decode('utf-8', errors='replace')
    if path.name == '.env.example':
        if any(line.strip() and not line.lstrip().startswith('#') and not re.fullmatch(r'[A-Z][A-Z0-9_]*=\s*', line) for line in text.splitlines()):
            result.append('example environment must contain empty values only')
    # Test fixtures may have synthetic inputs, but always undergo secret scanning.
    if path.suffix in SOURCE and not name.startswith(('tests/', 'supabase/tests/')):
        for label, pattern in PATTERNS.items():
            if re.search(pattern, text):
                result.append(label)
    return result


def snapshot(ref=None):
    if ref is None:
        entries = git('ls-files', '--stage', '-z')
    else:
        entries = git('ls-tree', '-r', '-z', ref)
    for entry in entries.split(b'\0'):
        if not entry:
            continue
        metadata, name = entry.split(b'\t', 1)
        fields = metadata.split()
        if ref is None:
            mode, oid, stage = fields
            if stage != b'0':
                raise RuntimeError('Unresolved index entries block publication.')
        else:
            mode, kind, oid = fields
        if mode not in (b'100644', b'100755'):
            raise RuntimeError('Symlinks and submodules require an explicit scanning policy.')
        yield os.fsdecode(name), git('cat-file', 'blob', oid.decode())


def scan(entries, binary):
    failed = False
    with tempfile.TemporaryDirectory(prefix='cloze-security-') as directory:
        for name, data in entries:
            path = Path(name)
            if path.is_absolute() or '..' in path.parts:
                raise RuntimeError('Unsafe snapshot path.')
            for reason in violations(name, data):
                # ascii escapes filenames that could contain control characters.
                print(f'BLOCKED {ascii(name)}: {reason}', file=sys.stderr)
                failed = True
            target = Path(directory) / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        # Run outside the snapshot so repo config/ignore files cannot disable rules.
        env = scanner_environment()
        with tempfile.TemporaryDirectory(prefix='cloze-scanner-') as runner:
            completed = subprocess.run(
                [str(binary), 'dir', directory, '--redact', '--no-banner', '--ignore-gitleaks-allow'],
                cwd=runner, env=env, capture_output=True,
            )
        if completed.returncode:
            print('BLOCKED: secret scanner reported a finding or failed. Raw output withheld.', file=sys.stderr)
            failed = True
    if failed:
        raise RuntimeError('Security gate failed; publication blocked.')


def main():
    binary = scanner()
    mode = sys.argv[1]
    if mode == 'doctor':
        print('Python and Gitleaks available.')
    elif mode == 'staged':
        scan(snapshot(), binary)
    elif mode == 'message':
        scan([('commit-message.txt', Path(sys.argv[2]).read_bytes())], binary)
    elif mode == 'push':
        tips = []
        for line in sys.stdin:
            fields = line.split()
            if len(fields) != 4:
                raise RuntimeError('Malformed pre-push input.')
            local_ref, local_oid, remote_ref, remote_oid = fields
            if (not local_ref.startswith('refs/') or not remote_ref.startswith('refs/') or
                    not valid_object_id(local_oid) or not valid_object_id(remote_oid) or
                    len(local_oid) != len(remote_oid)):
                raise RuntimeError('Malformed pre-push input.')
            scan([('ref-name.txt', f'{local_ref}\n{remote_ref}\n'.encode())], binary)
            if set(local_oid) != {'0'}:
                tips.append(local_oid)
        if tips:
            for tip in tips:
                oid = tip
                while git('cat-file', '-t', oid).strip() == b'tag':
                    content = git('cat-file', 'tag', oid)
                    scan([('tag-message.txt', content)], binary)
                    oid = content.splitlines()[0].split()[1].decode()
            # All ancestors, including removed secrets in earlier commits and new branches.
            for commit in git('rev-list', *tips).decode().splitlines():
                scan(snapshot(commit), binary)
                scan([('commit-message.txt', git('show', '-s', '--format=%B', commit))], binary)
    elif mode == 'range':
        if len(sys.argv) != 4:
            raise RuntimeError('Range mode requires base and head revisions.')
        base, head = sys.argv[2:]
        if not valid_object_id(head) or (set(base) != {'0'} and not valid_object_id(base)):
            raise RuntimeError('Range mode requires valid commit IDs.')
        if set(base) == {'0'}:
            commits = git('rev-list', head).decode().splitlines()
        else:
            commits = git('rev-list', head, f'^{base}').decode().splitlines()
        for commit in commits:
            scan(snapshot(commit), binary)
            scan([('commit-message.txt', git('show', '-s', '--format=%B', commit))], binary)
    elif mode == 'worktree':
        names = git('ls-files', '--cached', '--others', '--exclude-standard', '-z')
        entries = []
        for raw in set(names.split(b'\0')) - {b''}:
            name = os.fsdecode(raw)
            path = Path(name)
            if path.is_symlink():
                raise RuntimeError('Symlink cannot be scanned.')
            if path.is_file():
                entries.append((name, path.read_bytes()))
        scan(entries, binary)
    else:
        raise RuntimeError('Unknown gate mode.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Subprocess errors may embed sensitive arguments; only explicit safe messages escape.
        print(str(error) if isinstance(error, RuntimeError) else 'Security gate error; blocked.', file=sys.stderr)
        sys.exit(1)
