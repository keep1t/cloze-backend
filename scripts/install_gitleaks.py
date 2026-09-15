#!/usr/bin/env python3
"""Install the repository-pinned Gitleaks release with checksum verification."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import sys
import tarfile
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'scripts/tool-versions.json').read_text())['gitleaks']
VERSION = CONFIG['version']
CHECKSUMS = CONFIG['checksums']
BINARY_CHECKSUMS = CONFIG['binary_sha256']
DESTINATION = ROOT / '.tools' / 'gitleaks'


def release_target(system=None, machine=None):
    system = system or platform.system()
    machine = machine or platform.machine()
    if system != 'Linux':
        raise RuntimeError('Gitleaks installer supports Linux x64 and arm64 only.')
    architecture = {'x86_64': 'x64', 'aarch64': 'arm64'}.get(machine)
    if architecture is None:
        raise RuntimeError('Gitleaks installer supports Linux x64 and arm64 only.')
    filename = f'gitleaks_{VERSION}_linux_{architecture}.tar.gz'
    platform_key = f'linux_{architecture}'
    return filename, CHECKSUMS[platform_key], platform_key


def download(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'cloze-security-gate'})
    with urllib.request.urlopen(request, timeout=CONFIG['download_timeout_seconds']) as response:
        return response.read()


def extract_binary(archive_data, expected_sha256):
    actual = hashlib.sha256(archive_data).hexdigest()
    if actual != expected_sha256:
        raise RuntimeError('Gitleaks release checksum mismatch.')
    with tempfile.TemporaryDirectory(prefix='cloze-gitleaks-install-') as temporary:
        archive_path = Path(temporary) / 'release.tar.gz'
        archive_path.write_bytes(archive_data)
        with tarfile.open(archive_path, 'r:gz') as archive:
            members = archive.getmembers()
            binaries = [member for member in members if member.name == 'gitleaks']
            if len(binaries) != 1 or {item.name for item in members} != {
                    'gitleaks', 'LICENSE', 'README.md'}:
                raise RuntimeError('Gitleaks release archive has unexpected contents.')
            if len(members) != 3 or any(
                    not item.isfile() or item.issym() or item.islnk()
                    for item in members):
                raise RuntimeError('Gitleaks release archive contains unsafe entries.')
            member = binaries[0]
            if not member.isfile() or member.issym() or member.islnk():
                raise RuntimeError('Gitleaks release binary is not a regular file.')
            source = archive.extractfile(member)
            if source is None:
                raise RuntimeError('Gitleaks release binary is missing.')
            binary = source.read()
            if not binary.startswith(b'\x7fELF'):
                raise RuntimeError('Gitleaks release binary is invalid.')
            return binary


def install():
    filename, expected_sha256, platform_key = release_target()
    url = f"{CONFIG['release_base_url']}/v{VERSION}/{filename}"
    binary = extract_binary(download(url), expected_sha256)
    if hashlib.sha256(binary).hexdigest() != BINARY_CHECKSUMS[platform_key]:
        raise RuntimeError('Gitleaks executable checksum mismatch.')
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix='gitleaks-', dir=DESTINATION.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(binary)
        os.chmod(temporary_name, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                 stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        os.replace(temporary_name, DESTINATION)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)
    print(f'Installed verified Gitleaks {VERSION} at .tools/gitleaks.')


if __name__ == '__main__':
    try:
        install()
    except (OSError, RuntimeError, tarfile.TarError) as error:
        print(f'Gitleaks installation failed: {error}', file=sys.stderr)
        sys.exit(1)
