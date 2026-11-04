from pathlib import Path
import argparse,subprocess,xml.etree.ElementTree as ET
args=argparse.ArgumentParser();args.add_argument('--bridge',type=Path);args.add_argument('--mode',choices=['cold','cold_right','held','warm','all'],default='all');a=args.parse_args()
p=Path(__file__).resolve().parents[1];out=p/'results/poweron_audio';out.mkdir(parents=True,exist_ok=True)
files=[(a.bridge if a.bridge and x.attrib['path']=='src/migration/mig_audio_bridge.v' else p/x.attrib['path']) for x in ET.parse(p/'audio.gprj').findall('.//File') if x.attrib.get('type')=='file.verilog' and '/gowin_' not in x.attrib['path']]
iv=p/'tools/iverilog/bin/iverilog.exe';vvp=iv.with_name('vvp.exe')
r=subprocess.run([str(iv),'-g2012','-s','tb_poweron_audio','-o',str(out/'test.vvp')]+list(map(str,files))+[str(p/'sim/migration_clock_models.v'),str(p/'sim/tb_poweron_audio.sv')],capture_output=True,text=True)
if r.returncode:print(r.stdout+r.stderr);raise SystemExit(1)
for mode in (['cold','cold_right','held','warm'] if a.mode=='all' else [a.mode]):
 r=subprocess.run([str(vvp),str(out/'test.vvp')]+({'held':['+RESET_HELD'],'warm':['+WARM'],'cold_right':['+RIGHT_FIRST']}.get(mode,[])),capture_output=True,text=True,timeout=240)
 log=r.stdout+r.stderr;(out/((('baseline_' if a.bridge else '')+mode)+'.log')).write_text(log,encoding='utf-8')
 print(log,flush=True)
 if r.returncode or 'PASS poweron audio:' not in log:raise SystemExit(1)
