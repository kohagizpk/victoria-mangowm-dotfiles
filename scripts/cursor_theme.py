"""Create a size-specific copy of Xcursor themes without changing original assets."""
from pathlib import Path
import re
import struct
import os


def resize_cursor(data,size):
    from PIL import Image
    magic,header,version,n=struct.unpack_from('<4I',data)
    if magic!=0x72756358:raise ValueError('Not an Xcursor file')
    entries=[struct.unpack_from('<3I',data,header+i*12) for i in range(n)]
    images=[e for e in entries if e[0]==0xfffd0002]
    nominal=min({e[1] for e in images},key=lambda v:abs(v-size))
    chunks=[]
    for kind,sub,offset in images:
        if sub!=nominal:continue
        hdr,_,_,ver,w,h,x,y,delay=struct.unpack_from('<9I',data,offset)
        ratio=size/sub;nw=max(1,round(w*ratio));nh=max(1,round(h*ratio))
        image=Image.frombytes('RGBA',(w,h),data[offset+hdr:offset+hdr+w*h*4],'raw','BGRA')
        image=image.resize((nw,nh),Image.Resampling.LANCZOS)
        chunks.append(struct.pack('<9I',36,kind,size,ver,nw,nh,min(nw-1,round(x*ratio)),min(nh-1,round(y*ratio)),delay)+image.tobytes('raw','BGRA'))
    offset=16+12*len(chunks);table=[]
    for chunk in chunks:table.append(struct.pack('<3I',0xfffd0002,size,offset));offset+=len(chunk)
    return struct.pack('<4I',magic,16,version,len(chunks))+b''.join(table)+b''.join(chunks)


def prepare(home,mango,size):
    text='\n'.join(p.read_text() for p in (mango/'config.conf',mango/'local/custom.conf') if p.exists())
    matches=re.findall(r'^cursor_theme\s*=\s*(.+)$',text,re.M)
    if not matches:return 'Adwaita'
    theme=matches[-1].strip()
    roots=[home/'.local/share/icons',home/'.icons',Path('/usr/share/icons')]
    source=next((r/theme for r in roots if (r/theme/'cursors').is_dir()),None)
    if source and (source/'victoria-original-theme').exists():
        theme=(source/'victoria-original-theme').read_text().strip()
        source=next((r/theme for r in roots if (r/theme/'cursors').is_dir()),None)
    if source is None:return theme
    name='VictoriaScaled-'+re.sub(r'[^A-Za-z0-9_-]','_',theme)+'-'+str(size)
    target=roots[0]/name
    if not (target/'complete').exists():
        (target/'cursors').mkdir(parents=True,exist_ok=True)
        for path in (source/'cursors').iterdir():
            if not path.is_file():continue
            data=resize_cursor(path.read_bytes(),size)
            temporary=target/'cursors'/('.'+path.name+'.tmp');temporary.write_bytes(data);os.replace(temporary,target/'cursors'/path.name)
        (target/'index.theme').write_text(f'[Icon Theme]\nName={name}\nInherits={theme}\n')
        (target/'victoria-original-theme').write_text(theme)
        (target/'complete').touch()
    return name
