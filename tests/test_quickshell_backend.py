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

    def test_sample_spawns_no_audio_or_notification_processes(self):
        # Audio comes from Quickshell's PipeWire service and DND from a swaync/
        # Quickshell subscription, so a sample may only run the cached network commands.
        sampler = backend.Sampler()
        with patch.object(backend, 'run', return_value='') as run:
            data = sampler.sample()
        self.assertTrue({'cpu', 'memory', 'temperature', 'network', 'battery', 'focus'} <= set(data))
        self.assertFalse(any(call.args[0] in ('pactl', 'swaync-client', 'wpctl') for call in run.call_args_list))
