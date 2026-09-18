"""Run declared local PostgreSQL concurrency manifests without exposing credentials."""

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import re
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit
import uuid


ROOT = Path(__file__).resolve().parents[1]
MANIFESTS = ROOT / "supabase" / "tests" / "database" / "concurrency"
FIELDS = frozenset({"name", "bootstrap_sql", "create_sql", "lock_sql", "replay_sql", "teardown_sql", "replay_marker", "lock_expression", "lock_input"})
PLACEHOLDER = "{{USER_ID}}"
OPERATION_PLACEHOLDER = "{{OPERATION_ID}}"
LOCK_EXPRESSION = "owner_operation_hashtextextended_v1"
LOCK_INPUT = PLACEHOLDER + ":" + OPERATION_PLACEHOLDER
LOOPBACK = frozenset({"localhost", "127.0.0.1", "::1"})
FILENAME = re.compile(r"^[a-z0-9][a-z0-9_-]*\.json$")
MARKER = re.compile(r"^[A-Za-z0-9_.:-]+$")
UNSAFE_SQL = re.compile(r"\\|copy\b.*\bprogram\b|\bprogram\s*\(", re.IGNORECASE | re.DOTALL)
AUTH_INSERT = re.compile(r"^insert\s+into\s+auth\.users\s*\(", re.IGNORECASE)
IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]*$")


class ConcurrencyError(RuntimeError):
    """A sanitized harness failure."""


def _parenthesized(sql: str, opening: int) -> tuple[str, int] | None:
    depth = 0
    quote = False
    index = opening
    while index < len(sql):
        character = sql[index]
        if quote:
            if character == "'":
                if index + 1 < len(sql) and sql[index + 1] == "'":
                    index += 2
                    continue
                quote = False
        elif character == "'":
            quote = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return sql[opening + 1:index], index + 1
            if depth < 0:
                return None
        index += 1
    return None


def _split_sql_list(value: str) -> list[str] | None:
    entries = []
    start = 0
    depth = 0
    quote = False
    index = 0
    while index < len(value):
        character = value[index]
        if quote:
            if character == "'":
                if index + 1 < len(value) and value[index + 1] == "'":
                    index += 2
                    continue
                quote = False
        elif character == "'":
            quote = True
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth < 0:
                return None
        elif character == "," and depth == 0:
            entries.append(value[start:index].strip())
            start = index + 1
        index += 1
    if quote or depth != 0:
        return None
    entries.append(value[start:].strip())
    return entries if all(entries) else None


def _allows_empty_auth_fixture(sql: str) -> bool:
    """Allow only the exact synthetic auth.users insert used by the manifest."""
    if "--" in sql or "/*" in sql or "*/" in sql:
        return False
    source = sql.strip()
    if source.lower().count("password") != 1:
        return False
    match = AUTH_INSERT.match(source)
    if not match:
        return False
    columns = _parenthesized(source, match.end() - 1)
    if columns is None:
        return False
    column_text, position = columns
    rest = source[position:].lstrip()
    values_match = re.match(r"values\s*\(", rest, re.IGNORECASE)
    if not values_match:
        return False
    values = _parenthesized(rest, values_match.end() - 1)
    if values is None:
        return False
    suffix = rest[values[1]:].strip()
    if suffix not in ("", ";"):
        return False
    column_list = _split_sql_list(column_text)
    value_list = _split_sql_list(values[0])
    if column_list is None or value_list is None or len(column_list) != len(value_list):
        return False
    if any(not IDENTIFIER.fullmatch(column) for column in column_list):
        return False
    password_columns = [index for index, column in enumerate(column_list) if column == "encrypted_password"]
    return len(password_columns) == 1 and value_list[password_columns[0]] == "''"


def database_url_from_status(output: str) -> str:
    try:
        status = json.loads(output)
        value = status["DB_URL"]
    except (json.JSONDecodeError, KeyError, TypeError):
        raise ConcurrencyError("Local Supabase status did not contain a database URL.") from None
    if not isinstance(value, str) or not value:
        raise ConcurrencyError("Local Supabase status contained an invalid database URL.")
    return value


def connection_parts(database_url: str) -> tuple[str, int, str, str, str]:
    try:
        parsed = urlsplit(database_url)
        host = parsed.hostname
        port = parsed.port
    except ValueError:
        raise ConcurrencyError("Local database URL is malformed.") from None
    if parsed.scheme not in {"postgres", "postgresql"} or host not in LOOPBACK or port is None:
        raise ConcurrencyError("Only a loopback PostgreSQL database is allowed.")
    if not parsed.username or parsed.password is None or not parsed.path.strip("/"):
        raise ConcurrencyError("Local database URL is incomplete.")
    return host, port, unquote(parsed.path.lstrip("/")), unquote(parsed.username), unquote(parsed.password)


def discover_manifests(directory: Path = MANIFESTS) -> list[Path]:
    if not directory.exists():
        return []
    entries = sorted(directory.iterdir())
    if any(not path.is_file() and path.name != ".gitkeep" for path in entries):
        raise ConcurrencyError("Concurrency manifest directory contains an invalid entry.")
    manifests = [path for path in entries if path.is_file() and path.suffix == ".json"]
    for path in manifests:
        if not FILENAME.fullmatch(path.name):
            raise ConcurrencyError("Concurrency manifest filename is invalid.")
    return manifests


def load_manifest(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        raise ConcurrencyError("Concurrency manifest could not be read.") from None
    if not isinstance(value, dict) or set(value) != FIELDS:
        raise ConcurrencyError("Concurrency manifest schema is invalid.")
    if not isinstance(value["name"], str) or not MARKER.fullmatch(value["name"]):
        raise ConcurrencyError("Concurrency manifest name is invalid.")
    if not isinstance(value["replay_marker"], str) or not MARKER.fullmatch(value["replay_marker"]):
        raise ConcurrencyError("Concurrency replay marker is invalid.")
    if value["lock_expression"] != LOCK_EXPRESSION or value["lock_input"] != LOCK_INPUT:
        raise ConcurrencyError("Concurrency advisory-lock declaration is invalid.")
    for key, item in value.items():
        if not isinstance(item, str) or not item or "\x00" in item:
            raise ConcurrencyError("Concurrency manifest contains an invalid field.")
        password_exception = key == "bootstrap_sql" and _allows_empty_auth_fixture(item)
        if key.endswith("_sql") and (UNSAFE_SQL.search(item) or "http://" in item.lower() or "https://" in item.lower() or ("password" in item.lower() and not password_exception) or "secret" in item.lower() or "shell" in item.lower() or "${" in item or "`" in item):
            raise ConcurrencyError("Concurrency manifest contains a prohibited SQL fragment.")
    if any(placeholder not in value[key] for key in ("create_sql", "lock_sql", "replay_sql", "teardown_sql") for placeholder in (PLACEHOLDER, OPERATION_PLACEHOLDER)):
        raise ConcurrencyError("Concurrency manifest must use the synthetic user placeholder.")
    return value


def _phase(command: list[str], environment: dict[str, str], sql: str, marker: str | None = None) -> subprocess.Popen:
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment)
    try:
        assert process.stdin is not None
        process.stdin.write(sql + "\n")
        process.stdin.flush()
        if marker is not None:
            assert process.stdout is not None
            while True:
                line = process.stdout.readline()
                if not line:
                    raise ConcurrencyError("Database session ended before its marker.")
                if line.strip() == marker:
                    break
        return process
    except (OSError, BrokenPipeError):
        process.kill()
        raise ConcurrencyError("Database session could not execute its phase.") from None


def _finish(process: subprocess.Popen, sql: str, expected_marker: str | None = None) -> str:
    try:
        assert process.stdin is not None
        process.stdin.write(sql + "\n\\q\n")
        process.stdin.close()
        process.wait()
        assert process.stdout is not None
        stdout = process.stdout.read()
    except (OSError, BrokenPipeError):
        process.kill()
        process.wait()
        raise ConcurrencyError("Database session failed.") from None
    if process.returncode:
        raise ConcurrencyError("Database session reported an error.")
    result = next((line.strip() for line in stdout.splitlines() if line.strip() == expected_marker), "") if expected_marker is not None else stdout.strip()
    if expected_marker is not None and not result:
        raise ConcurrencyError("Database session returned an unexpected marker.")
    return result


def run_manifest(manifest: dict[str, object], command: list[str], environment: dict[str, str]) -> None:
    user_id = str(uuid.uuid4())
    operation_id = str(uuid.uuid4())
    sql = lambda key: str(manifest[key]).replace(PLACEHOLDER, user_id).replace(OPERATION_PLACEHOLDER, operation_id)
    _finish(_phase(command, environment, "set role service_role;\n" + sql("bootstrap_sql")), "", None)
    session_a = session_b = None
    try:
        session_a = _phase(command, environment, "begin;\nset role service_role;\n" + sql("create_sql") + "\nselect 'A_READY';", "A_READY")
        lock_marker = "__CLOZE_B_LOCK_" + uuid.uuid4().hex + "__"
        session_b = _phase(command, environment, "begin;\nset role service_role;\n" + sql("lock_sql") + "\nselect '" + lock_marker + "=' || pg_try_advisory_xact_lock(hashtextextended('" + user_id + "' || ':' || '" + operation_id + "', 0));", lock_marker + "=f")
        _finish(session_a, "commit;", None)
        _finish(session_b, "rollback;\nbegin;\nset role service_role;\n" + sql("replay_sql") + "\nselect '" + str(manifest["replay_marker"]) + "';", str(manifest["replay_marker"]))
    finally:
        for process in (session_a, session_b):
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()
        _finish(_phase(command, environment, "set role service_role;\n" + sql("teardown_sql")), "", None)


def run(supabase_command: str) -> None:
    manifests = discover_manifests(MANIFESTS)
    if not manifests:
        print("Database concurrency tests skipped: no manifests exist yet.")
        return
    status = subprocess.run([*shlex.split(supabase_command), "status", "--output", "json"], cwd=ROOT, text=True, capture_output=True, check=False)
    if status.returncode:
        raise ConcurrencyError("Local Supabase status failed; diagnostics were suppressed.")
    database_url = database_url_from_status(status.stdout)
    host, port, database, user, password = connection_parts(database_url)
    psql = shutil.which("psql")
    if not psql:
        raise ConcurrencyError("The local psql executable is unavailable.")
    with tempfile.TemporaryDirectory(prefix="cloze-concurrency-") as temp:
        passfile = Path(temp) / "pgpass"
        passfile.write_text(f"{host}:{port}:{database}:{user}:{password}\n", encoding="utf-8")
        passfile.chmod(0o600)
        environment = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C", "LANG": "C", "PGPASSFILE": str(passfile)}
        command = [psql, "--no-psqlrc", "--no-password", "--host", host, "--port", str(port), "--dbname", database, "--username", user, "--tuples-only", "--no-align", "--set", "ON_ERROR_STOP=1"]
        for path in manifests:
            run_manifest(load_manifest(path), command, environment)
        print(f"Database concurrency tests passed for {len(manifests)} manifest(s).")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase", default="supabase")
    try:
        run(parser.parse_args().supabase)
    except (ConcurrencyError, OSError, subprocess.SubprocessError):
        print("Database concurrency tests failed; diagnostics were suppressed.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
