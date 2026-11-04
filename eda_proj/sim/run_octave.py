from pathlib import Path
import argparse, subprocess, xml.etree.ElementTree as ET
parser=argparse.ArgumentParser()
parser.add_argument('--test',choices=['octave','piano_cycle_regression'],default='octave')
test=parser.parse_args().test
root=Path(__file__).resolve().parents[1]
out=root/'results'/'octave'; out.mkdir(parents=True,exist_ok=True)
files=[root/x.attrib['path'] for x in ET.parse(root/'audio.gprj').findall('.//File')
       if x.attrib.get('type')=='file.verilog' and '/gowin_' not in x.attrib['path']]
iv=root/'tools/iverilog/bin/iverilog.exe'; vvp=iv.with_name('vvp.exe')
cmd=[str(iv),'-g2012','-s','tb_'+test,'-o',str(out/(test+'.vvp'))]+list(map(str,files))+[str(root/('sim/tb_'+test+'.sv'))]
r=subprocess.run(cmd,capture_output=True,text=True)
log=r.stdout+r.stderr
if r.returncode==0:
    r=subprocess.run([str(vvp),str(out/(test+'.vvp'))],capture_output=True,text=True,timeout=120)
    log+=r.stdout+r.stderr
(out/('simulation.log' if test=='octave' else test+'.log')).write_text(log,encoding='utf-8')
print(log[-3000:])
raise SystemExit(r.returncode or (0 if 'PASS '+('octave:' if test=='octave' else 'piano cycle regression') in log else 1))
