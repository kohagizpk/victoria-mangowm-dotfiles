import sys,struct,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from cursor_theme import resize_cursor
from clipboard_history import preview

class HistoryCursorTests(unittest.TestCase):
    def test_cursor_resizes_pixels_hotspot_and_preserves_delay(self):
        source=struct.pack('<4I',0x72756358,16,1,1)+struct.pack('<3I',0xfffd0002,32,28)+struct.pack('<9I',36,0xfffd0002,32,1,32,32,4,8,75)+bytes([0,0,255,255])*1024
        for size in (16,48,64):
            result=resize_cursor(source,size)
            entry=struct.unpack_from('<3I',result,16)
            frame=struct.unpack_from('<9I',result,entry[2])
            self.assertEqual(entry[1],size)
            self.assertEqual(frame[4:9],(size,size,round(size/8),round(size/4),75))
            self.assertEqual(len(result),28+36+size*size*4)
    def test_html_is_not_misrepresented_as_an_image(self):
        self.assertEqual(preview(b'42\t<img src="https://example.com/a.png">')[0],'HTML fragment (not image data)')
        self.assertFalse(preview(b'42\t<img src="x">')[2])
        self.assertTrue(preview(b'43\t[[ binary data 10 KiB png 800x600 ]]')[2])

class ClipboardPositionTests(unittest.TestCase):
    def test_opens_below_input(self):
        from clipboard_position import position
        self.assertEqual(position({'x':100,'y':100,'height':20},{'x':0,'y':0,'width':1920,'height':1080},480,450),(100,130))
    def test_opens_above_low_input_and_stays_on_monitor(self):
        from clipboard_position import position
        self.assertEqual(position({'x':3400,'y':850,'height':20},{'x':1920,'y':0,'width':1600,'height':900},480,450),(3032,390))
    def test_negative_monitor_coordinates(self):
        from clipboard_position import position
        x,y=position({'x':-10,'y':50},{'x':-1920,'y':0,'width':1920,'height':1080},480,450)
        self.assertEqual((x,y),(-488,60))
