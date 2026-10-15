import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

FAKE_COMMAND = '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['MOCK_RELEASE_DIR'])
command = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([command, args]) + '\\n')
if command == 'docker':
    if args[0] == 'run': print('test-container-id')
    elif args[0] == 'port': print('127.0.0.1:49152')
    sys.exit(0)
if command == 'sleep': sys.exit(0)
url = args[-1]
if '/api/health' in url:
    counter = root / 'health-count'
    count = int(counter.read_text()) if counter.exists() else 0
    counter.write_text(str(count + 1))
    sys.exit(22 if os.environ.get('MOCK_HEALTH_FAIL') == 'true' or count == 0 else 0)
if '/api/login' in url:
    print(os.environ.get('MOCK_LOGIN_STATUS', '401'), end='')
    sys.exit(0)
missing = os.environ.get('MOCK_MISSING_ASSET')
sys.exit(22 if missing and url.endswith(missing) else 0)
'''


class ContainerReleaseChecks(unittest.TestCase):
    def run_smoke(self, **settings):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for command in ('docker', 'curl', 'sleep'):
                executable = root / command
                executable.write_text(FAKE_COMMAND)
                executable.chmod(0o755)
            environment = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                               MOCK_RELEASE_DIR=directory, CRM_IMAGE='fixture/image:sha-123', **settings)
            result = subprocess.run(['bash', str(ROOT / 'scripts/test-container.sh')],
                                    env=environment, capture_output=True, text=True, timeout=30)
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            return result, calls

    def assert_cleanup(self, calls):
        run = next(args for command, args in calls if command == 'docker' and args[0] == 'run')
        name = run[run.index('--name') + 1]
        removed = [args for command, args in calls if command == 'docker' and args[0] == 'rm']
        self.assertEqual(removed, [['rm', '-fv', name]])
        self.assertNotIn('-v', run, 'smoke tests must never attach the production volume')

    def test_release_waits_for_health_and_checks_packaged_assets(self):
        result, calls = self.run_smoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cleanup(calls)
        urls = [args[-1] for command, args in calls if command == 'curl']
        self.assertEqual(sum('/api/health' in url for url in urls), 2)
        for asset in ('/elm.js', '/public/account-elm.js', '/public/record-browser-elm.js',
                      '/public/work-dashboard-elm.js', '/public/work-dashboard-elm.css',
                      '/public/management-report-elm.css', '/account/forgot-password'):
            self.assertTrue(any(url.endswith(asset) for url in urls), asset)

    def test_release_rejects_an_image_with_demo_login_enabled(self):
        result, calls = self.run_smoke(MOCK_LOGIN_STATUS='200')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('demo login', result.stderr)
        self.assert_cleanup(calls)

    def test_release_rejects_missing_frontend_assets(self):
        result, calls = self.run_smoke(MOCK_MISSING_ASSET='/public/account-elm.js')
        self.assertNotEqual(result.returncode, 0)
        self.assert_cleanup(calls)

    def test_release_rejects_an_unhealthy_container_and_cleans_up(self):
        result, calls = self.run_smoke(MOCK_HEALTH_FAIL='true')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('health check failed', result.stderr)
        self.assert_cleanup(calls)
        self.assertFalse(any(command == 'curl' and '/api/login' in args[-1] for command, args in calls))
