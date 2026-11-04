"""Measure logical gate -> PCM -> complete PT8211 word at six frame phases."""
from pathlib import Path
import json,re,subprocess
P=Path(__file__).resolve().parents[1];OUT=P/'results/additive';OUT.mkdir(parents=True,exist_ok=True)
iv=Path('C:/iverilog/bin/iverilog.exe');binary=OUT/'latency.vvp'
names=['mig_additive_engine','mig_stereo_mixer','mig_audio_bridge','mig_cdc_snapshot']
files=[P/'src/migration'/(n+'.v') for n in names]+[P/'src/audio_drive.v',P/'sim/tb_additive_latency.sv']
r=subprocess.run([str(iv),'-g2012','-s','tb_additive_latency','-o',str(binary),*map(str,files)],cwd=P,capture_output=True,text=True)
log=r.stdout+r.stderr
if not r.returncode:
    r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=P,capture_output=True,text=True,timeout=30)
    log+=r.stdout+r.stderr
(OUT/'latency.log').write_text(log,encoding='utf-8');print(log)
assert r.returncode==0 and 'PASS digital-path latency' in log and 'FATAL' not in log
rows=[]
for line in log.splitlines():
    if line.startswith('LATENCY '):rows.append({k:float(v) for k,v in re.findall(r'(\w+)=([0-9.]+)',line)})
assert len(rows)==6
result=dict(kind='RTL simulation, not oscilloscope measurement',stimulus='Piano MIDI60, one logical voice gate, default envelope, centre full-master mixer',
    excludes=['TTP229 internal touch detection','touch serial scan','gesture I2C and sequencing','analog DAC/filter/amplifier delay'],
    rows=rows,minimum_us={key:min(row[key] for row in rows) for key in rows[0] if key!='offset'},
    maximum_us={key:max(row[key] for row in rows) for key in rows[0] if key!='offset'})
(OUT/'latency.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
