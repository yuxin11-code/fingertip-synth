from pathlib import Path
import subprocess,sys,xml.etree.ElementTree as ET
p=Path(__file__).resolve().parents[1];out=p/'results/integration';out.mkdir(parents=True,exist_ok=True)
files=[p/x.attrib['path'] for x in ET.parse(p/'audio.gprj').findall('.//File') if x.attrib.get('type')=='file.verilog' and '/gowin_' not in x.attrib['path']]
files.append(p/'sim/migration_clock_models.v')
for name in ['serial_divider','score_guide','viz_capture','spectrum','spectrum_bins','hmi_viz_tx','mig_visualization']:
    f=p/f'src/migration/{name}.v'
    if f not in files:files.append(f)
iv=Path(r'C:\iverilog\bin\iverilog.exe')
for name in sys.argv[1:] or ['score_guide','visualization']:
    binary=out/(name+'.vvp')
    r=subprocess.run([str(iv),'-g2012','-I',str(p/'src/migration'),'-s','tb_'+name,'-o',str(binary),*map(str,files),str(p/f'sim/tb_{name}.sv')],capture_output=True,text=True)
    log=r.stdout+r.stderr
    if not r.returncode:
        r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=p,capture_output=True,text=True,timeout=1800);log+=r.stdout+r.stderr
    (out/(name+'.log')).write_text(log,encoding='utf-8');print(log[-8000:])
    if r.returncode or 'PASS' not in log or 'FAIL' in log or 'FATAL' in log:sys.exit(1)
