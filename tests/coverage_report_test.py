import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('coverage_report', ROOT / 'scripts/report-function-coverage.py')
REPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORTER)


class CoverageReportTest(unittest.TestCase):
    SAMPLE = ('ecc-crm/backend/auth.go:10:\tvalidate\t100.0%\n'
              'ecc-crm/backend/auth.go:30:\tsave\t50.0%\n'
              'ecc-crm/backend/files.go:15:\tvalidate\t0.0%\n'
              'total:\t(statements)\t54.5%\n')

    def test_report_keeps_uncovered_functions_and_duplicate_names(self):
        summary, functions, markdown = REPORTER.report(self.SAMPLE)
        self.assertEqual(summary['functions'], 3)
        self.assertEqual(summary['untouched_functions'], 1)
        self.assertEqual(summary['fully_statement_covered_functions'], 1)
        self.assertEqual(summary['partially_statement_covered_functions'], 1)
        self.assertEqual(summary['statement_coverage'], 54.5)
        self.assertEqual(sum(function['name'] == 'validate' for function in functions), 2)
        self.assertIn('ecc-crm/backend/files.go:15', markdown)
        self.assertIn('0%', markdown)

    def test_missing_or_incomplete_reports_are_rejected(self):
        for invalid in ['', 'total:\t(statements)\t100.0%\n', 'ecc-crm/backend/auth.go:10:\tvalidate\t100.0%\n']:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                REPORTER.report(invalid)

    def test_command_writes_matching_markdown_and_machine_readable_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'functions.txt'
            output = Path(directory) / 'report.md'
            source.write_text(self.SAMPLE)
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/report-function-coverage.py'), str(source), str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            document = json.loads(output.with_suffix('.json').read_text())
            self.assertEqual(json.loads(result.stdout), document['summary'])
            self.assertEqual(len(document['functions']), 3)
            self.assertIn('Backend function coverage', output.read_text())


if __name__ == '__main__':
    unittest.main()
