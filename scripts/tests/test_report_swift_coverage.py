#!/usr/bin/env python3

import hashlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path


sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "report-swift-coverage.py"
SPEC = importlib.util.spec_from_file_location("report_swift_coverage", SCRIPT)
REPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORTER)


class CoverageReportFixtureTests(unittest.TestCase):
    def test_scopes_reviewed_missing_source_and_below_threshold(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_directory = root / "Sources" / "OpenCoreGraphics"
            relative_paths = [
                Path("Core.swift"),
                Path("Rendering/GL/GLRenderer.swift"),
                Path("Nested/Rendering/GL/Embedded.swift"),
                Path("Services/Window Services/CGWindow.swift"),
                Path("Other/CGWindow.swift"),
                Path("Services/Window Services/CGWindowError.swift"),
                Path("Missing.swift"),
            ]
            for relative_path in relative_paths:
                source_path = source_directory / relative_path
                source_path.parent.mkdir(parents=True, exist_ok=True)
                source_path.touch()
            non_swift_path = source_directory / "Notes/NotASource.txt"
            non_swift_path.parent.mkdir(parents=True)
            non_swift_path.touch()
            external_swift = root / "OutsideTarget.swift"

            llvm_files = [
                self.llvm_file(source_directory / "Core.swift", 79, 100),
                self.llvm_file(source_directory / "Rendering/GL/GLRenderer.swift", 1, 5),
                self.llvm_file(source_directory / "Nested/Rendering/GL/Embedded.swift", 2, 20),
                self.llvm_file(
                    source_directory / "Services/Window Services/CGWindow.swift", 0, 10
                ),
                self.llvm_file(source_directory / "Other/CGWindow.swift", 2, 2),
                self.llvm_file(
                    source_directory / "Services/Window Services/CGWindowError.swift", 1, 1
                ),
                self.llvm_file(non_swift_path, 100, 100),
                self.llvm_file(external_swift, 100, 100),
            ]
            coverage = REPORTER.collect_coverage(
                source_directory,
                source_directory.rglob("*"),
                llvm_files,
            )
            reviewed = {
                Path("Missing.swift"): self.review_entry(source_directory / "Missing.swift")
            }
            output = io.StringIO()
            errors = io.StringIO()

            result = REPORTER.render_report(
                coverage, source_directory, reviewed, "fixture platform", output, errors
            )

            self.assertEqual(result, 1)
            self.assertEqual(len(coverage), len(relative_paths))
            self.assertNotIn(Path("Notes/NotASource.txt"), coverage)
            eligible = [path for path in coverage if REPORTER.is_eligible_core(path)]
            self.assertNotIn(Path("Rendering/GL/GLRenderer.swift"), eligible)
            self.assertNotIn(Path("Nested/Rendering/GL/Embedded.swift"), eligible)
            self.assertNotIn(Path("Services/Window Services/CGWindow.swift"), eligible)
            self.assertIn(Path("Other/CGWindow.swift"), eligible)
            self.assertIn("Eligible core: 82/103 instrumentable lines (79.61%)", output.getvalue())
            self.assertIn("below the 80% target", errors.getvalue())
            self.assertIn("Verified eligible sources with no instrumentable lines: 1 files", output.getvalue())
            self.assertIn("Missing.swift", output.getvalue())
            self.assertIn("Target Swift source inventory: 7 files", output.getvalue())
            self.assertNotIn("not reviewed", errors.getvalue())

    def test_unreviewed_eligible_missing_source_blocks_gate(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_directory = Path(temporary_directory) / "Sources" / "OpenCoreGraphics"
            files = self.create_mappable_inventory(source_directory)
            coverage = REPORTER.collect_coverage(
                source_directory,
                [source_directory / path for path in files],
                [
                    self.llvm_file(source_directory / "Core.swift", 79, 100),
                    self.llvm_file(source_directory / "Rendering/GL/GLRenderer.swift", 1, 1),
                    self.llvm_file(
                        source_directory / "Services/Window Services/CGWindow.swift", 1, 1
                    ),
                ],
            )
            output = io.StringIO()
            errors = io.StringIO()

            result = REPORTER.render_report(
                coverage, source_directory, {}, "fixture platform", output, errors
            )

            self.assertEqual(result, 1)
            self.assertIn("Unmapped eligible source is not reviewed: Missing.swift", errors.getvalue())
            self.assertNotIn("Eligible core:", output.getvalue())
            self.assertNotIn("below the 80% target", errors.getvalue())

    def test_changed_reviewed_source_blocks_gate(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_directory = Path(temporary_directory) / "Sources" / "OpenCoreGraphics"
            self.create_mappable_inventory(source_directory)
            coverage = REPORTER.collect_coverage(
                source_directory,
                source_directory.rglob("*.swift"),
                [
                    self.llvm_file(source_directory / "Core.swift", 90, 100),
                    self.llvm_file(source_directory / "Rendering/GL/GLRenderer.swift", 1, 1),
                    self.llvm_file(
                        source_directory / "Services/Window Services/CGWindow.swift", 1, 1
                    ),
                ],
            )
            missing_path = source_directory / "Missing.swift"
            missing_path.write_text("// New code invalidates the no-line review.\n", encoding="utf-8")
            reviewed = {Path("Missing.swift"): self.review_entry(missing_path, original_empty=True)}
            errors = io.StringIO()

            result = REPORTER.render_report(
                coverage, source_directory, reviewed, "fixture platform", io.StringIO(), errors
            )

            self.assertEqual(result, 1)
            self.assertIn("contents changed; review its no-line status again: Missing.swift", errors.getvalue())

    def test_empty_llvm_denominator_fails_explicitly(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            source_directory = Path(temporary_directory) / "Sources" / "OpenCoreGraphics"
            for relative_path in (
                Path("Core.swift"),
                Path("Rendering/GL/GLRenderer.swift"),
                Path("Services/Window Services/CGWindow.swift"),
            ):
                source_path = source_directory / relative_path
                source_path.parent.mkdir(parents=True, exist_ok=True)
                source_path.touch()
            coverage = REPORTER.collect_coverage(
                source_directory,
                source_directory.rglob("*.swift"),
                [
                    self.llvm_file(source_directory / "Core.swift", 0, 0),
                    self.llvm_file(source_directory / "Rendering/GL/GLRenderer.swift", 1, 1),
                    self.llvm_file(
                        source_directory / "Services/Window Services/CGWindow.swift", 1, 1
                    ),
                ],
            )
            errors = io.StringIO()

            result = REPORTER.render_report(
                coverage,
                source_directory,
                {Path("Core.swift"): self.review_entry(source_directory / "Core.swift")},
                "fixture platform",
                io.StringIO(),
                errors,
            )

            self.assertEqual(result, 1)
            self.assertIn("Eligible core has no LLVM-mapped instrumentable lines", errors.getvalue())

    @staticmethod
    def create_mappable_inventory(source_directory):
        relative_paths = [
            Path("Core.swift"),
            Path("Rendering/GL/GLRenderer.swift"),
            Path("Services/Window Services/CGWindow.swift"),
            Path("Missing.swift"),
        ]
        for relative_path in relative_paths:
            source_path = source_directory / relative_path
            source_path.parent.mkdir(parents=True, exist_ok=True)
            source_path.touch()
        return relative_paths

    @staticmethod
    def review_entry(path, original_empty=False):
        contents = b"" if original_empty else path.read_bytes()
        return {
            "sha256": hashlib.sha256(contents).hexdigest(),
            "classification": "fixture-no-lines",
            "reason": "Fixture-only reviewed source with no executable statements.",
        }

    @staticmethod
    def llvm_file(path, covered, total):
        return {
            "filename": str(path),
            "summary": {"lines": {"covered": covered, "count": total}},
        }


if __name__ == "__main__":
    unittest.main()
