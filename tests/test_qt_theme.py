import sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import qt_theme

class QtThemeTests(unittest.TestCase):
    def test_private_theme_keeps_alpha_originals_and_preferences(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);base=root/'base';base.mkdir();config=root/'config'
            original='[%General]\nrespect_DE=true\n[GeneralColors]\nwindow.color=#121212\nhighlight.color=#8ab4f83c\n'
            (base/'MateriaDark.kvconfig').write_text(original)
            (base/'MateriaDark.svg').write_text('<svg fill="#8ab4f8"/>')
            def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
            write(config/'Kvantum/kvantum.kvconfig','[General]\ntheme=Old\n[Applications]\nkeep=this\n')
            colors={'background':'#ffffff','foreground':'#111111','color5':'#aa6677','color13':'#bb8899'}
            self.assertTrue(qt_theme.apply(colors,config,write,base))
            generated=(config/'Kvantum'/qt_theme.NAME/(qt_theme.NAME+'.kvconfig')).read_text()
            self.assertIn('highlight.color=#aa66773c',generated)
            self.assertIn('window.color=#303030',generated)
            self.assertEqual((base/'MateriaDark.kvconfig').read_text(),original)
            self.assertIn('keep=this',(config/'Kvantum/kvantum.kvconfig').read_text())
            colors['color5']='#338899';qt_theme.apply(colors,config,write,base)
            self.assertIn('#338899',(config/'Kvantum'/qt_theme.NAME/(qt_theme.NAME+'.svg')).read_text())

    def test_missing_materia_does_not_modify_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertFalse(qt_theme.apply({},Path(folder),lambda *_:self.fail('Unexpected write'),Path(folder)/'missing'))
