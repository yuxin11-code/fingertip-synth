"""Compare old controls with transpose input and voice output registers against candidate RTL."""
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

p = Path(__file__).resolve().parents[1]
out = p / 'results/integration'
out.mkdir(parents=True, exist_ok=True)
iv = Path(r'C:\iverilog\bin\iverilog.exe')
sources = [p / x.attrib['path'] for x in ET.parse(p / 'audio.gprj').findall('.//File')
           if x.attrib.get('type') == 'file.verilog' and '/gowin_' not in x.attrib['path']]
binary = out / 'voice_engine_diff.vvp'
args = [str(iv), '-g2012', '-I', str(p / 'src/migration'), '-s', 'tb_voice_engine_diff', '-o', str(binary)]
r = subprocess.run(args + list(map(str, sources)) + [str(p / 'sim/ref/mig_voice_engine_ref.v'),
                   str(p / 'sim/tb_voice_engine_diff.sv')], capture_output=True, text=True, cwd=p)
log = r.stdout + r.stderr
if not r.returncode:
    r = subprocess.run([str(iv.with_name('vvp.exe')), str(binary)],
                       capture_output=True, text=True, cwd=p, timeout=1800)
    log += r.stdout + r.stderr
(out / 'voice_engine_diff.log').write_text(log, encoding='utf-8')
print(log)
sys.exit(r.returncode if r.returncode else (0 if 'PASS voice engine differential' in log else 1))
