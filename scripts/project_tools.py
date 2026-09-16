"""Safe, reproducible project commands used by the Makefile."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import tomllib
from collections import defaultdict
from collections.abc import Callable, Sequence

ROOT = Path(__file__).resolve().parents[1]
FUNCTIONS = ROOT / "supabase" / "functions"
FUNCTION_TESTS = ROOT / "supabase" / "tests"
GENERATED_TYPES = FUNCTIONS / "_shared" / "database.types.ts"
PROJECT_REF_PATTERN = re.compile(r"^[a-z0-9]{20}$")
FUNCTION_PATTERN = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
MIGRATION_PATTERN = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
SOURCE_EXTENSIONS = {".ts", ".tsx", ".js", ".jsx", ".mts", ".cts", ".mjs", ".cjs"}
TEST_SUFFIXES = ("_test", ".test", "-test")


class ProjectToolError(RuntimeError):
    """An actionable tooling error that does not reveal command output or secrets."""


def configured_versions() -> dict[str, str]:
    config = json.loads((ROOT / "scripts" / "tool-versions.json").read_text())
    return config["runtime"]


def run_quietly(
    command: Sequence[str],
    *,
    cwd: Path = ROOT,
    runner: Callable | None = None,
    input_text: str | None = None,
) -> subprocess.CompletedProcess:
    execute = runner or subprocess.run
    result = execute(
        list(command),
        cwd=cwd,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        name = Path(command[0]).name
        raise ProjectToolError(f"{name} command failed; detailed output was suppressed.")
    return result


def executable_version(command: Sequence[str], args: Sequence[str]) -> str:
    try:
        result = subprocess.run(
            [*command, *args], text=True, capture_output=True, check=False
        )
    except OSError as error:
        raise ProjectToolError(f"Required tool is unavailable: {command[0]}.") from error
    if result.returncode:
        raise ProjectToolError(f"Could not read the version of {command[0]}.")
    return (result.stdout or result.stderr).strip()


def doctor(python_command: str, deno_command: str, supabase_command: str) -> None:
    configured = configured_versions()
    python = shlex.split(python_command)
    deno = shlex.split(deno_command)
    supabase = shlex.split(supabase_command)
    for required in ("make", "git", "docker"):
        if shutil.which(required) is None:
            raise ProjectToolError(f"Required tool is unavailable: {required}.")

    make_version = executable_version(["make"], ["--version"])
    make_match = re.search(r"^GNU Make\s+(\d+)\.(\d+)", make_version, re.MULTILINE)
    make_minimum = tuple(int(part) for part in configured["make_minimum"].split("."))
    if not make_match or tuple(map(int, make_match.groups())) < make_minimum:
        found = make_match.group(1) + "." + make_match.group(2) if make_match else "non-GNU Make"
        raise ProjectToolError(
            f"GNU Make {configured['make_minimum']} or newer is required; found {found}."
        )

    python_version = executable_version(python, ["--version"])
    match = re.search(r"(\d+)\.(\d+)", python_version)
    minimum = tuple(int(part) for part in configured["python_minimum"].split("."))
    if not match or tuple(map(int, match.groups())) < minimum:
        raise ProjectToolError(
            f"Python {configured['python_minimum']} or newer is required; found {python_version}."
        )

    deno_version = executable_version(deno, ["--version"])
    deno_match = re.search(r"^deno\s+(\S+)", deno_version, re.MULTILINE)
    if not deno_match or deno_match.group(1) != configured["deno"]:
        found = deno_match.group(1) if deno_match else "unknown"
        raise ProjectToolError(f"Deno {configured['deno']} is required; found {found}.")

    supabase_version = executable_version(supabase, ["--version"])
    if supabase_version != configured["supabase_cli"]:
        raise ProjectToolError(
            f"Supabase CLI {configured['supabase_cli']} is required; found {supabase_version}."
        )

    python_version = python_version.removeprefix("Python ")
    print(f"Tool versions are ready (GNU Make {make_match.group(1)}.{make_match.group(2)}, "
          f"Python {python_version}, Deno {configured['deno']}, "
          f"Supabase CLI {configured['supabase_cli']}).")


def source_files(paths: Sequence[Path] | None = None) -> list[Path]:
    roots = paths or (FUNCTIONS, FUNCTION_TESTS)
    return sorted(
        path
        for root in roots
        if root.exists()
        for path in root.rglob("*")
        if path.is_file() and path.suffix in SOURCE_EXTENSIONS
    )


def test_files() -> list[Path]:
    return [
        path
        for path in source_files((FUNCTION_TESTS,))
        if path.stem == "test" or any(path.stem.endswith(suffix) for suffix in TEST_SUFFIXES)
    ]


def typecheck(deno_command: str) -> None:
    deno = shlex.split(deno_command)
    files = source_files()
    if not files:
        print("Type-check skipped: no Deno source files exist yet.")
        return

    groups: dict[Path, list[Path]] = defaultdict(list)
    for path in files:
        config = next(
            (parent / "deno.json" for parent in path.parents if (parent / "deno.json").is_file()),
            ROOT / "deno.json",
        )
        groups[config].append(path)

    for config, entries in sorted(groups.items()):
        try:
            run_quietly([*deno, "check", "--config", str(config), *map(str, entries)])
        except ProjectToolError as error:
            raise ProjectToolError(
                f"TypeScript check failed for {', '.join(path.relative_to(ROOT).as_posix() for path in entries)}; diagnostics were suppressed."
            ) from error
    print(f"Type-checked {len(files)} Deno source file(s).")


def run_function_tests(deno_command: str) -> None:
    files = test_files()
    if not files:
        print("Function tests skipped: no Deno test modules exist yet.")
        return
    deno = shlex.split(deno_command)
    command = [
        *deno,
        "test",
        "--config",
        str(ROOT / "deno.json"),
        "--allow-env=SUPABASE_URL,SUPABASE_ANON_KEY",
        "--allow-net=127.0.0.1,localhost",
        f"--allow-read={FUNCTION_TESTS},{ROOT / 'supabase' / 'functions'}",
        *map(str, files),
    ]
    subprocess.run(command, cwd=ROOT, check=True)


def run_database_tests(supabase_command: str) -> None:
    files = sorted(path for path in FUNCTION_TESTS.rglob("*.sql") if path.is_file())
    if not files:
        print("Database tests skipped: no pgTAP SQL test files exist yet.")
        return
    subprocess.run(
        [*shlex.split(supabase_command), "test", "db", "--local", *map(str, files)],
        cwd=ROOT,
        check=True,
    )


def local_project_id() -> str:
    with (ROOT / "supabase" / "config.toml").open("rb") as config_file:
        return tomllib.load(config_file)["project_id"]


def validate_project_ref(project_ref: str | None) -> str:
    if not project_ref:
        raise ProjectToolError("Set PROJECT_REF to the intended Supabase project reference.")
    if not PROJECT_REF_PATTERN.fullmatch(project_ref):
        raise ProjectToolError("PROJECT_REF must contain exactly 20 lowercase letters or digits.")
    return project_ref


def require_remote_confirmation(project_ref: str, confirmation: str | None) -> None:
    if confirmation != project_ref:
        raise ProjectToolError("Set CONFIRM_REMOTE to the exact PROJECT_REF before continuing.")


def linked_project_ref() -> str:
    link_file = ROOT / "supabase" / ".temp" / "project-ref"
    try:
        linked = link_file.read_text().strip()
    except OSError as error:
        raise ProjectToolError("No remote Supabase project is linked to this checkout.") from error
    if not PROJECT_REF_PATTERN.fullmatch(linked):
        raise ProjectToolError("The linked Supabase project reference is invalid.")
    return linked


def assert_linked_project(project_ref: str) -> None:
    if linked_project_ref() != project_ref:
        raise ProjectToolError("PROJECT_REF does not match the project linked to this checkout.")


def require_local_reset_confirmation(confirmation: str | None) -> None:
    if confirmation != local_project_id():
        raise ProjectToolError("Set CONFIRM_RESET to the local project_id before resetting.")


def reset_database(supabase_command: str, confirmation: str | None) -> None:
    require_local_reset_confirmation(confirmation)
    subprocess.run(
        [*shlex.split(supabase_command), "db", "reset", "--local", "--yes"],
        cwd=ROOT,
        check=True,
    )


def safe_status(supabase_command: str) -> None:
    try:
        run_quietly([*shlex.split(supabase_command), "status", "--output-format", "json"])
    except ProjectToolError:
        print("Local Supabase stack is not running.")
        return
    print("Local Supabase stack is running. Credentials and URLs were suppressed.")


def create_migration(supabase_command: str, name: str | None) -> None:
    if not name or not MIGRATION_PATTERN.fullmatch(name):
        raise ProjectToolError("Set NAME to a snake_case migration name beginning with a letter.")
    subprocess.run(
        [*shlex.split(supabase_command), "migration", "new", name], cwd=ROOT, check=True
    )


def generated_types(supabase_command: str) -> bytes:
    result = run_quietly(
        [
            *shlex.split(supabase_command),
            "gen",
            "types",
            "--local",
            "--lang=typescript",
            "--schema",
            "public",
        ]
    )
    generated = result.stdout.encode()
    formatted = subprocess.run(
        [
            *shlex.split(os.environ.get("DENO", "deno")),
            "fmt",
            "--config",
            str(ROOT / "deno.json"),
            "--ext=ts",
            "-",
        ],
        input=generated,
        capture_output=True,
        check=False,
    )
    if formatted.returncode:
        raise ProjectToolError("Could not format generated database types; output was suppressed.")
    return formatted.stdout


def write_types(supabase_command: str) -> None:
    content = generated_types(supabase_command)
    GENERATED_TYPES.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=GENERATED_TYPES.parent, prefix=".database.types.", delete=False
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, GENERATED_TYPES)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
    print("Generated public-schema types from the local Supabase database.")


def check_types(supabase_command: str) -> None:
    if not GENERATED_TYPES.is_file():
        print("Type generation check skipped: database.types.ts does not exist yet.")
        return
    generated = generated_types(supabase_command)
    if GENERATED_TYPES.read_bytes() != generated:
        raise ProjectToolError("Generated database types are stale; run `make types`.")
    print("Generated public-schema types are up to date.")


def remote_link(supabase_command: str, project_ref: str | None, confirmation: str | None) -> None:
    ref = validate_project_ref(project_ref)
    require_remote_confirmation(ref, confirmation)
    subprocess.run(
        [*shlex.split(supabase_command), "link", "--project-ref", ref],
        cwd=ROOT,
        check=True,
    )
    print("Supabase project link completed for the confirmed project.")


def deploy_function(
    supabase_command: str,
    function_name: str | None,
    project_ref: str | None,
    confirmation: str | None,
) -> None:
    if not function_name or not FUNCTION_PATTERN.fullmatch(function_name):
        raise ProjectToolError("Set FUNCTION to a kebab-case Edge Function name.")
    ref = validate_project_ref(project_ref)
    require_remote_confirmation(ref, confirmation)
    assert_linked_project(ref)
    function_dir = FUNCTIONS / function_name
    if not function_dir.is_dir():
        raise ProjectToolError("FUNCTION must name an existing Edge Function directory.")
    if not function_dir.resolve().is_relative_to(FUNCTIONS.resolve()):
        raise ProjectToolError("FUNCTION must resolve inside the Edge Functions directory.")
    subprocess.run(["make", "check"], cwd=ROOT, check=True)
    run_quietly(
        [*shlex.split(supabase_command), "functions", "deploy", function_name]
    )
    print("The requested Edge Function deployment completed for the confirmed project.")


def push_database(
    supabase_command: str,
    project_ref: str | None,
    confirmation: str | None,
    *,
    runner: Callable | None = None,
) -> None:
    ref = validate_project_ref(project_ref)
    require_remote_confirmation(ref, confirmation)
    assert_linked_project(ref)
    base_command = [*shlex.split(supabase_command), "db", "push", "--linked"]
    run_quietly([*base_command, "--dry-run"], runner=runner)
    run_quietly([*base_command, "--yes"], runner=runner)
    print("Remote database migrations were applied to the confirmed linked project.")


def staged_typescript_check(deno_command: str, *, cwd: Path | None = None) -> None:
    repo = cwd or Path.cwd()
    listing = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR"],
        cwd=repo,
        capture_output=True,
        check=True,
    )
    paths = [os.fsdecode(path) for path in listing.stdout.split(b"\0") if path]
    staged = [path for path in paths if Path(path).suffix in SOURCE_EXTENSIONS]
    if not staged:
        print("Staged Deno check skipped: no changed TypeScript or JavaScript files.")
        return

    deno = shlex.split(deno_command)
    config = ROOT / "deno.json"
    for path in staged:
        content = subprocess.run(
            ["git", "show", f":{path}"], cwd=repo, capture_output=True, check=True
        ).stdout
        extension = Path(path).suffix.lstrip(".")
        formatted = subprocess.run(
            [*deno, "fmt", "--config", str(config), f"--ext={extension}", "-"],
            input=content,
            capture_output=True,
            check=False,
        )
        if formatted.returncode or formatted.stdout != content:
            raise ProjectToolError(f"Staged file is not Deno-formatted: {path}.")
        linted = subprocess.run(
            [*deno, "lint", "--config", str(config), f"--ext={extension}", "-"],
            input=content,
            capture_output=True,
            check=False,
        )
        if linted.returncode:
            raise ProjectToolError(f"Deno lint failed for staged file: {path}; diagnostics suppressed.")
    print(f"Staged Deno checks passed for {len(staged)} file(s).")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)

    command = commands.add_parser("doctor")
    command.add_argument("--python", default="python3")
    command.add_argument("--deno", default="deno")
    command.add_argument("--supabase", default="supabase")

    for name in ("typecheck", "test-functions"):
        command = commands.add_parser(name)
        command.add_argument("--deno", default="deno")

    for name in ("test-db", "status", "db-reset", "migration", "types", "types-check", "remote-link", "deploy-function", "db-push", "serve-function"):
        command = commands.add_parser(name)
        command.add_argument("--supabase", default="supabase")

    commands.add_parser("confirm-reset")

    commands.choices["db-reset"].add_argument("--confirm", default=os.environ.get("CONFIRM_RESET"))
    commands.choices["migration"].add_argument("--name", default=os.environ.get("NAME"))
    commands.choices["remote-link"].add_argument("--project-ref", default=os.environ.get("PROJECT_REF"))
    commands.choices["remote-link"].add_argument("--confirm", default=os.environ.get("CONFIRM_REMOTE"))
    for name in ("deploy-function", "db-push"):
        command = commands.choices[name]
        command.add_argument("--project-ref", default=os.environ.get("PROJECT_REF"))
        command.add_argument("--confirm", default=os.environ.get("CONFIRM_REMOTE"))
    commands.choices["deploy-function"].add_argument("--function", default=os.environ.get("FUNCTION"))
    commands.choices["serve-function"].add_argument("--function", default=os.environ.get("FUNCTION"))

    command = commands.add_parser("types-staged-check")
    command.add_argument("--deno", default="deno")
    return result


def main(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "doctor":
            doctor(args.python, args.deno, args.supabase)
        elif args.command == "typecheck":
            typecheck(args.deno)
        elif args.command == "test-functions":
            run_function_tests(args.deno)
        elif args.command == "test-db":
            run_database_tests(args.supabase)
        elif args.command == "status":
            safe_status(args.supabase)
        elif args.command == "db-reset":
            reset_database(args.supabase, args.confirm)
        elif args.command == "confirm-reset":
            require_local_reset_confirmation(os.environ.get("CONFIRM_RESET"))
            print("Local database reset confirmation validated.")
        elif args.command == "migration":
            create_migration(args.supabase, args.name)
        elif args.command == "types":
            write_types(args.supabase)
        elif args.command == "types-check":
            check_types(args.supabase)
        elif args.command == "remote-link":
            remote_link(args.supabase, args.project_ref, args.confirm)
        elif args.command == "deploy-function":
            deploy_function(args.supabase, args.function, args.project_ref, args.confirm)
        elif args.command == "db-push":
            push_database(args.supabase, args.project_ref, args.confirm)
        elif args.command == "serve-function":
            if not args.function or not FUNCTION_PATTERN.fullmatch(args.function):
                raise ProjectToolError("Set FUNCTION to a kebab-case Edge Function name.")
            if not (FUNCTIONS / args.function).is_dir():
                raise ProjectToolError("FUNCTION must name an existing Edge Function directory.")
            subprocess.run(
                [*shlex.split(args.supabase), "functions", "serve", args.function],
                cwd=ROOT,
                check=True,
            )
        elif args.command == "types-staged-check":
            staged_typescript_check(args.deno)
        return 0
    except (ProjectToolError, subprocess.CalledProcessError, OSError) as error:
        if isinstance(error, ProjectToolError):
            print(f"Project command failed: {error}", file=sys.stderr)
        else:
            print("Project command failed; detailed command output was suppressed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
