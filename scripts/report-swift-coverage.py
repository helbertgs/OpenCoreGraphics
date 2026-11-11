#!/usr/bin/env python3

import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, TextIO, Tuple


LineCounts = Tuple[int, int]
CoverageInventory = Dict[Path, Optional[LineCounts]]
ReviewedNoLineSources = Dict[Path, dict]
GL_PATH = ("Rendering", "GL")
WINDOW_DIRECTORY = ("Services", "Window Services")
EXCLUDED_WINDOW = WINDOW_DIRECTORY + ("CGWindow.swift",)


def has_path_sequence(path: Path, sequence: Tuple[str, ...]) -> bool:
    parts = path.parts
    return any(parts[index : index + len(sequence)] == sequence for index in range(len(parts)))


def is_eligible_core(path: Path) -> bool:
    return path.suffix == ".swift" and not has_path_sequence(path, GL_PATH) and path.parts != EXCLUDED_WINDOW


def collect_coverage(
    source_directory: Path,
    source_paths: Iterable[Path],
    llvm_files: Iterable[dict],
) -> CoverageInventory:
    source_root = source_directory.resolve()
    inventory = {
        source_path.resolve().relative_to(source_root)
        for source_path in source_paths
        if source_path.is_file() and source_path.suffix == ".swift"
    }
    coverage: CoverageInventory = {source_path: None for source_path in inventory}

    for file_report in llvm_files:
        llvm_path = Path(file_report["filename"]).resolve()
        try:
            relative_path = llvm_path.relative_to(source_root)
        except ValueError:
            continue
        if relative_path.suffix != ".swift" or relative_path not in inventory:
            continue
        if coverage[relative_path] is not None:
            raise ValueError("LLVM export contains duplicate source entry: {}".format(relative_path))

        line_summary = file_report["summary"]["lines"]
        covered = line_summary["covered"]
        total = line_summary["count"]
        if not isinstance(covered, int) or not isinstance(total, int) or covered < 0 or total < 0 or covered > total:
            raise ValueError("Invalid LLVM line summary for {}: {}/{}".format(relative_path, covered, total))
        coverage[relative_path] = (covered, total)
    return coverage


def load_reviewed_sources(manifest_path: Path) -> Tuple[str, ReviewedNoLineSources]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    platform = manifest.get("platform")
    entries = manifest.get("entries")
    if not isinstance(platform, str) or not platform or not isinstance(entries, dict):
        raise ValueError("Reviewed no-line manifest must contain platform and entries.")

    reviewed = {}
    for raw_path, entry in entries.items():
        path = Path(raw_path)
        if path.is_absolute() or path.suffix != ".swift" or ".." in path.parts:
            raise ValueError("Invalid reviewed source path: {}".format(raw_path))
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("sha256"), str)
            or not isinstance(entry.get("classification"), str)
            or not isinstance(entry.get("reason"), str)
            or not entry["sha256"]
            or not entry["classification"]
            or not entry["reason"]
        ):
            raise ValueError(
                "Reviewed source requires sha256, classification, and reason: {}".format(raw_path)
            )
        if len(entry["sha256"]) != 64 or any(
            character not in "0123456789abcdef" for character in entry["sha256"]
        ):
            raise ValueError("Reviewed source has an invalid SHA-256: {}".format(raw_path))
        reviewed[path] = entry
    return platform, reviewed


def verify_reviewed_sources(
    coverage: CoverageInventory,
    source_directory: Path,
    reviewed: ReviewedNoLineSources,
    errors: TextIO,
) -> Tuple[bool, List[Path], List[Path]]:
    eligible_unmapped = sorted(
        path
        for path, counts in coverage.items()
        if is_eligible_core(path) and (counts is None or counts[1] == 0)
    )
    unexpected = [path for path in eligible_unmapped if path not in reviewed]
    stale = [path for path in reviewed if path not in coverage]
    invalid_scope = [path for path in reviewed if not is_eligible_core(path)]
    newly_mapped = [
        path
        for path in reviewed
        if path in coverage and coverage[path] is not None and coverage[path][1] > 0
    ]
    changed = []

    for path in reviewed:
        if path not in coverage:
            continue
        source_path = source_directory / path
        if not source_path.is_file():
            changed.append(path)
            continue
        actual_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
        if actual_hash != reviewed[path]["sha256"]:
            changed.append(path)

    if unexpected or stale or invalid_scope or newly_mapped or changed:
        print("Coverage gate blocked: reviewed no-line source inventory mismatch.", file=errors)
        for path in unexpected:
            print("  Unmapped eligible source is not reviewed: {}".format(path), file=errors)
        for path in stale:
            print("  Reviewed source is no longer in the Swift target inventory: {}".format(path), file=errors)
        for path in invalid_scope:
            print("  Reviewed no-line exception is outside the eligible core: {}".format(path), file=errors)
        for path in newly_mapped:
            print("  Reviewed source now has LLVM line mapping; review it again: {}".format(path), file=errors)
        for path in changed:
            print("  Reviewed source contents changed; review its no-line status again: {}".format(path), file=errors)
        return False, eligible_unmapped, []

    all_no_line = sorted(
        path for path, counts in coverage.items() if counts is None or counts[1] == 0
    )
    return True, eligible_unmapped, all_no_line


def sum_lines(files: Iterable[Tuple[Path, Optional[LineCounts]]]) -> LineCounts:
    covered_total = 0
    line_total = 0
    for _, counts in files:
        if counts is not None:
            covered_total += counts[0]
            line_total += counts[1]
    return covered_total, line_total


def report_scope(
    label: str,
    files: List[Tuple[Path, Optional[LineCounts]]],
    output: TextIO,
) -> Tuple[int, int, float]:
    covered, total = sum_lines(files)
    if total <= 0:
        raise ValueError("{} has no LLVM-mapped instrumentable lines.".format(label))
    percentage = 100 * covered / total
    mapped_count = sum(counts is not None for _, counts in files)
    print(
        "{}: {}/{} instrumentable lines ({:.2f}%), {} source files ({} mapped)".format(
            label, covered, total, percentage, len(files), mapped_count
        ),
        file=output,
    )
    return covered, total, percentage


def render_report(
    coverage: CoverageInventory,
    source_directory: Path,
    reviewed: ReviewedNoLineSources,
    platform: str,
    output: TextIO,
    errors: TextIO,
) -> int:
    eligible = [(path, counts) for path, counts in coverage.items() if is_eligible_core(path)]
    gl_sources = [
        (path, counts)
        for path, counts in coverage.items()
        if path.suffix == ".swift" and has_path_sequence(path, GL_PATH)
    ]
    window_sources = [
        (path, counts)
        for path, counts in coverage.items()
        if path.suffix == ".swift" and path.parts[: len(WINDOW_DIRECTORY)] == WINDOW_DIRECTORY
    ]
    window_file = [
        (path, counts)
        for path, counts in coverage.items()
        if path.suffix == ".swift" and path.parts == EXCLUDED_WINDOW
    ]

    print("Coverage no-line review platform: {}".format(platform), file=output)
    print("Target Swift source inventory: {} files".format(len(coverage)), file=output)
    valid_review, eligible_unmapped, all_no_line = verify_reviewed_sources(
        coverage, source_directory, reviewed, errors
    )
    if not valid_review:
        return 1

    print(
        "Verified eligible sources with no instrumentable lines: {} files".format(
            len(eligible_unmapped)
        ),
        file=output,
    )
    for path in eligible_unmapped:
        entry = reviewed[path]
        print(
            "  {} [{}] sha256={} — {}".format(
                path, entry["classification"], entry["sha256"], entry["reason"]
            ),
            file=output,
        )

    other_no_line = [path for path in all_no_line if path not in eligible_unmapped]
    if other_no_line:
        print(
            "GL/window-excluded sources with no instrumentable lines (not included in core denominator): {}".format(
                len(other_no_line)
            ),
            file=output,
        )
        for path in other_no_line:
            print("  {}".format(path), file=output)

    try:
        _, _, eligible_percentage = report_scope("Eligible core", eligible, output)
        report_scope("Rendering/GL", gl_sources, output)
        report_scope("Window services including CGWindow.swift", window_sources, output)
        report_scope("CGWindow.swift (excluded from eligible core)", window_file, output)
    except ValueError as error:
        print("Coverage report invalid: {}".format(error), file=errors)
        return 1

    if eligible_percentage < 80:
        print(
            "Eligible core coverage is below the 80% target ({:.2f}%).".format(eligible_percentage),
            file=errors,
        )
        return 1
    return 0


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    build_path = subprocess.run(
        ["swift", "build", "--show-bin-path"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    build_directory = Path(build_path)
    profile = build_directory / "codecov" / "default.profdata"
    test_binary = (
        build_directory
        / "OpenCoreGraphicsTests.xctest"
        / "Contents"
        / "MacOS"
        / "OpenCoreGraphicsTests"
    )

    missing = [path for path in (profile, test_binary) if not path.is_file()]
    if missing:
        print(
            "Coverage artifacts are missing; first run `swift test --enable-code-coverage`.",
            file=sys.stderr,
        )
        for path in missing:
            print("  {}".format(path), file=sys.stderr)
        return 1

    exported = subprocess.run(
        [
            "xcrun",
            "llvm-cov",
            "export",
            "--instr-profile",
            str(profile),
            str(test_binary),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    coverage_data = json.loads(exported.stdout)
    source_directory = (root / "Sources" / "OpenCoreGraphics").resolve()
    source_paths = source_directory.rglob("*.swift")
    coverage = collect_coverage(source_directory, source_paths, coverage_data["data"][0]["files"])
    try:
        platform, reviewed = load_reviewed_sources(
            Path(__file__).with_name("coverage-reviewed-no-lines.json")
        )
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print("Coverage no-line review manifest is invalid: {}".format(error), file=sys.stderr)
        return 1
    return render_report(coverage, source_directory, reviewed, platform, sys.stdout, sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
