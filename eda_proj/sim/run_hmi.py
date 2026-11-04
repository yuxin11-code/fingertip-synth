from pathlib import Path
import subprocess, sys, xml.etree.ElementTree as ET
p=Path(__file__).resolve().parents[1]
out=p/'results/hmi_control'; out.mkdir(parents=True,exist_ok=True)
sources=[p/x.attrib['path'] for x in ET.parse(p/'audio.gprj').findall('.//File')
         if x.attrib.get('type')=='file.verilog' and '/gowin_' not in x.attrib['path']]
sources.append(p/'sim/migration_clock_models.v')
iv=Path(r'C:\iverilog\bin\iverilog.exe')
names=sys.argv[1:] or ['hmi_control']
for name in names:
    args=[str(iv),'-g2012','-I',str(p/'src/migration'),'-s','tb_'+name,'-o',str(out/(name+'.vvp'))]
    r=subprocess.run(args+list(map(str,sources))+[str(p/('sim/tb_'+name+'.sv'))],capture_output=True,text=True)
    log=r.stdout+r.stderr
    if not r.returncode:
        r=subprocess.run([str(iv.with_name('vvp.exe')),str(out/(name+'.vvp'))],capture_output=True,text=True,timeout=1800,cwd=p)
        log+=r.stdout+r.stderr
    (out/(name+'.log')).write_text(log,encoding='utf-8')
    print(log[-8000:])
    if r.returncode or 'PASS' not in log or 'FAIL' in log or 'FATAL' in log: sys.exit(1)
