import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('clipboard_picker',Path(__file__).resolve().parents[1]/'scripts/clipboard-picker.py')
picker=importlib.util.module_from_spec(spec);spec.loader.exec_module(picker)
def result(stdout=b'',code=0):return subprocess.CompletedProcess([],code,stdout,b'')

class ClipboardTests(unittest.TestCase):
    def test_cancel_does_not_decode_or_copy(self):
        with patch.object(picker.subprocess,'run',side_effect=[result(b'3\tHello\n'),result(code=1)]) as run:
            picker.pick();self.assertEqual(run.call_count,2)
    def test_empty_history_does_not_copy(self):
        with patch.object(picker.subprocess,'run',return_value=result()) as run,patch.object(picker,'notify'):
            picker.pick();self.assertEqual(run.call_count,1)
    def test_free_text_and_out_of_range_are_ignored(self):
        for value in (b'hello',b'-1',b'20',b''):
            with patch.object(picker.subprocess,'run',side_effect=[result(b'7\tHello\n'),result(value)]) as run:
                picker.pick();self.assertEqual(run.call_count,2)
    def test_decode_failure_does_not_copy(self):
        with patch.object(picker.subprocess,'run',side_effect=[result(b'8\tHello\n'),result(b'0\n'),result(code=1)]) as run:
            with self.assertRaises(RuntimeError):picker.pick()
            self.assertEqual(run.call_count,3)
    def test_binary_and_whitespace_survive_identical_previews(self):
        for payload in ('  Olá\n\tworld\n\n'.encode(),b'\x89PNG\r\n\x1a\n\x00\xff'):
            with patch.object(picker.subprocess,'run',side_effect=[result(b'9\tsame\n8\tsame\n'),result(b'1\n'),result(payload),result()]) as run:
                picker.pick()
                self.assertEqual(run.call_args_list[2].kwargs['input'],b'8\tsame\n')
                self.assertEqual(run.call_args_list[3].kwargs['input'],payload)
