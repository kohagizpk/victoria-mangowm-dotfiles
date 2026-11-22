import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bar_backend', Path(__file__).resolve().parents[1] / 'config/quickshell/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

class SamplingTests(unittest.TestCase):
    def setUp(self):
        backend.command_cache.clear()

    def test_cache_expires_and_does_not_repeat_external_commands(self):
        with patch.object(backend.time, 'monotonic', side_effect=[0, 2, 31]), patch.object(backend, 'run', side_effect=['first', 'second']) as run:
            self.assertEqual(backend.cached('pactl', 'get-default-sink', ttl=30), 'first')
            self.assertEqual(backend.cached('pactl', 'get-default-sink', ttl=30), 'first')
            self.assertEqual(backend.cached('pactl', 'get-default-sink', ttl=30), 'second')
            self.assertEqual(run.call_count, 2)

    def test_audio_events_invalidate_only_audio_cache(self):
        from unittest.mock import Mock
        backend.command_cache.update({('pactl', 'list'): (0, 'old'), ('nmcli',): (0, 'network')})
        events = backend.AudioEvents()
        events.child = Mock()
        events.child.poll.return_value = None
        with patch.object(backend.select, 'select', side_effect=[([events.child.stdout], [], []), ([], [], [])]), patch.object(backend.os, 'read', return_value=b"Event 'change' on sink #1\n"):
            events.poll()
        self.assertNotIn(('pactl', 'list'), backend.command_cache)
        self.assertIn(('nmcli',), backend.command_cache)
