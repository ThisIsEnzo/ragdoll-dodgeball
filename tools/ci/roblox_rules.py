#!/usr/bin/env python3
"""Project-specific Roblox invariants; static checks for recurring runtime mistakes."""
from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
SCRIPT_SUFFIXES = (".server.lua", ".client.lua")
RE_RETURN_VALUE = re.compile(r"^return\s+\S", re.MULTILINE)
RE_TECHNOLOGY = re.compile(r"Lighting\s*\.\s*Technology\s*=")
RE_IF_ARG = re.compile(r"[\w\]]\s*\(\s*if\s|:\s*\w+\s*\(\s*if\s")
RE_RESOLVE = re.compile(r'Resolve\s*\.\s*Require\s*\(\s*[\w_]+\s*,\s*"([\w_]+)"')
RE_SHARED_REQ = re.compile(r'require\s*\(\s*Shared\s*:\s*WaitForChild\s*\(\s*"([\w_]+)"')
RE_CFG_SECTION = re.compile(r"\bCFG\s*\.\s*([A-Za-z_]\w*)")
RE_CONFIG_SECTION = re.compile(r"^\t([A-Za-z_]\w*)\s*=\s*\{", re.MULTILINE)

class Report:
    def __init__(self, github: bool) -> None:
        self.github = github
        self.errors: list[str] = []
        self.warnings: list[str] = []
    def error(self, rule: str, path: Path, line: int, message: str) -> None:
        rel = path.relative_to(ROOT).as_posix()
        self.errors.append(f"{rule}  {rel}:{line}  {message}")
        if self.github:
            print(f"::error file={rel},line={line},title={rule}::{message}")
    def warn(self, rule: str, path: Path, line: int, message: str) -> None:
        rel = path.relative_to(ROOT).as_posix()
        self.warnings.append(f"{rule}  {rel}:{line}  {message}")
        if self.github:
            print(f"::warning file={rel},line={line},title={rule}::{message}")

def lua_files() -> list[Path]:
    return sorted(p for p in SRC.rglob("*.lua") if p.is_file()) if SRC.exists() else []
def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1
def read_text(path: Path) -> str:
    return path.read_bytes().decode("utf-8", errors="replace")

def check_scripts_return(rep: Report, files: list[Path]) -> None:
    for path in files:
        if not path.name.endswith(SCRIPT_SUFFIXES):
            continue
        text = read_text(path)
        for match in RE_RETURN_VALUE.finditer(text):
            rep.error("R01", path, line_of(text, match.start()),
                "Script returns a value. Only ModuleScript may do this; remove return or use a ModuleScript.")

def check_protected(rep: Report, files: list[Path]) -> None:
    for path in files:
        text = read_text(path)
        for match in RE_TECHNOLOGY.finditer(text):
            rep.error("R02", path, line_of(text, match.start()),
                "Lighting.Technology is protected; configure it in Studio properties.")

def check_if_argument(rep: Report, files: list[Path]) -> None:
    for path in files:
        text = read_text(path)
        for match in RE_IF_ARG.finditer(text):
            rep.error("R03", path, line_of(text, match.start()),
                "if-expression passed directly as call argument; assign to local or parenthesize.")

def module_index(files: list[Path]) -> dict[str, list[Path]]:
    index: dict[str, list[Path]] = {}
    for path in files:
        name = path.name
        for suffix in SCRIPT_SUFFIXES:
            if name.endswith(suffix):
                name = name[:-len(suffix)]
                break
        else:
            name = path.stem
        index.setdefault(name, []).append(path)
    return index

def check_resolve_targets(rep: Report, files: list[Path]) -> None:
    index = module_index(files)
    for path in files:
        text = read_text(path)
        for match in RE_RESOLVE.finditer(text):
            target = match.group(1)
            if target not in index:
                rep.error("R04", path, line_of(text, match.start()),
                    f'Resolve.Require target "{target}" has no file under src.')

def check_shared_requires(rep: Report, files: list[Path]) -> None:
    shared = {p.stem for p in (SRC / "shared").glob("*.lua")} if (SRC / "shared").exists() else set()
    for path in files:
        text = read_text(path)
        for match in RE_SHARED_REQ.finditer(text):
            target = match.group(1)
            if target not in shared:
                rep.error("R05", path, line_of(text, match.start()),
                    f'require(Shared:WaitForChild("{target}")) missing src/shared/{target}.lua')

def check_project_json(rep: Report) -> None:
    project = ROOT / "default.project.json"
    if not project.exists():
        rep.error("R06", project, 1, "default.project.json is missing.")
        return
    try:
        data = json.loads(project.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        rep.error("R06", project, exc.lineno, f"Invalid JSON: {exc.msg}")
        return
    def walk(node: object, trail: str) -> None:
        if isinstance(node, dict):
            path_value = node.get("$path")
            if isinstance(path_value, str):
                target = (ROOT / path_value).resolve()
                if not target.exists():
                    rep.error("R06", project, 1, f'Rojo path "{path_value}" ({trail}) does not exist.')
            for key, value in node.items():
                if not key.startswith("$"):
                    walk(value, f"{trail}.{key}")
    walk(data, str(data.get("name", "root")))

def check_encoding(rep: Report, files: list[Path]) -> None:
    for path in files:
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            rep.error("R07", path, 1, "UTF-8 BOM present; Rojo embeds it in Source.")
        if b"\r\n" in raw:
            rep.warn("R10", path, 1, "CRLF line endings (normalization may break patch scripts).")

def check_config_sections(rep: Report, files: list[Path]) -> None:
    config = SRC / "shared" / "BalanceConfig.lua"
    if not config.exists():
        return
    sections = set(RE_CONFIG_SECTION.findall(read_text(config)))
    for path in files:
        text = read_text(path)
        for match in RE_CFG_SECTION.finditer(text):
            name = match.group(1)
            if name not in sections:
                rep.error("R08", path, line_of(text, match.start()),
                    f"CFG.{name} is not defined in BalanceConfig.")

def check_duplicates(rep: Report, files: list[Path]) -> None:
    for root_name in ("server", "client", "shared"):
        root = SRC / root_name
        if not root.exists():
            continue
        seen: dict[str, Path] = {}
        for path in sorted(root.rglob("*.lua")):
            name = path.name
            for suffix in SCRIPT_SUFFIXES:
                if name.endswith(suffix):
                    name = name[:-len(suffix)]
                    break
            else:
                name = path.stem
            if name in seen:
                rep.error("R09", path, 1,
                    f'Duplicate module "{name}" also at {seen[name].relative_to(ROOT).as_posix()}; Resolve name collision.')
            else:
                seen[name] = path

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github", action="store_true")
    args = parser.parse_args()
    rep = Report(args.github)
    files = lua_files()
    if not files:
        print("No Lua files under src/; nothing to check.")
        return 0
    checks = (check_scripts_return, check_protected, check_if_argument, check_resolve_targets,
              check_shared_requires, check_encoding, check_config_sections, check_duplicates)
    for check in checks:
        check(rep, files)
    check_project_json(rep)
    print(f"Scanned {len(files)} Lua files.")
    if rep.errors:
        print(f"{len(rep.errors)} error(s):")
        for item in rep.errors: print("  " + item)
    if rep.warnings:
        print(f"{len(rep.warnings)} warning(s):")
        for item in rep.warnings: print("  " + item)
    if not rep.errors and not rep.warnings:
        print("All Roblox invariants hold.")
    return 1 if rep.errors else 0
if __name__ == "__main__":
    sys.exit(main())
