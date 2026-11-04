from pathlib import Path
import argparse,subprocess,xml.etree.ElementTree as ET
parser=argparse.ArgumentParser();parser.add_argument('--test',default='rp108');a=parser.parse_args()
p=Path(__file__).resolve().parents[1];out=p/'results/rp108';out.mkdir(parents=True,exist_ok=True)
files=[p/x.attrib['path'] for x in ET.parse(p/'audio.gprj').findall('.//File') if x.attrib.get('type')=='file.verilog' and '/gowin_' not in x.attrib['path']]
if a.test=='rp108_top':files += [p/'sim/migration_clock_models.v',p/'sim/tb_poweron_audio.sv']
iv=p/'tools/iverilog/bin/iverilog.exe';vvp=iv.with_name('vvp.exe')
r=subprocess.run([str(iv),'-g2012','-s','tb_'+a.test,'-o',str(out/(a.test+'.vvp'))]+list(map(str,files))+[str(p/'sim/rp108_slave_model.sv'),str(p/('sim/tb_'+a.test+'.sv'))],capture_output=True,text=True)
log=r.stdout+r.stderr
if r.returncode==0:
 r=subprocess.run([str(vvp),str(out/(a.test+'.vvp'))],capture_output=True,text=True,timeout=240);log+=r.stdout+r.stderr
(out/(a.test+'.log')).write_text(log,encoding='utf-8');print(log[-4000:])
raise SystemExit(r.returncode or (0 if 'PASS' in log else 1))
