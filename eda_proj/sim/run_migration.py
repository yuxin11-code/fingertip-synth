"""Run isolated ModelSim tests; never compile a bitstream."""
from pathlib import Path
import argparse, re, shutil, subprocess, tempfile, xml.etree.ElementTree as ET
p=argparse.ArgumentParser(); p.add_argument('--baseline',action='store_true'); p.add_argument('--test',default='all'); args=p.parse_args()
root=Path(__file__).resolve().parents[1]; sim=root/'sim'; src=root/'src'
teammate=Path('D:/FPGA_G/instrument_v1/instrument_v1/rtl')
tests=['knobs','stereo','guitar','controls','voice','screen','cdc','audio','legacy','dual','panels'] if args.test=='all' else [args.test]
ok=True
for test in tests:
    with tempfile.TemporaryDirectory(prefix='instrument_merge_') as tmp:
        wd=Path(tmp)
        if args.baseline:
            files=[teammate/(n+'.v') for n in (['input_ctrl'] if test=='controls' else ['voice_engine','wave_rom','note_step'])]
        else:
            files=[root/f.attrib['path'] for f in ET.parse(root/'audio.gprj').findall('.//File')
                   if f.attrib.get('type')=='file.verilog' and f.attrib.get('enable')=='1'
                   and '/gowin_' not in f.attrib['path']]
            if test in ['legacy','dual','panels']:
                files.append(sim/'migration_clock_models.v')
            if test=='legacy':
                backup=root/'backup_before_teammate_merge_20261022_204801/src/top.v'
                reference=wd/'top_reference.v'
                reference.write_text(backup.read_text(encoding='utf-8-sig').replace('module top(', 'module top_reference(',1),encoding='utf-8')
                files.append(reference)
        files.append(sim/f'tb_migration_{test}.sv')
        commands=['onerror {quit -code 2 -f}','onbreak {quit -code 1 -f}','vlib work',
                  'vlog -sv '+('+define+BASELINE ' if args.baseline else '')+' '.join('{'+str(f).replace('\\','/')+'}' for f in files),
                  f'vsim -voptargs=+acc work.tb_migration_{test}','run -all','quit -code 0 -f']
        (wd/'run.do').write_text('\n'.join(commands),encoding='utf-8')
        result=subprocess.run([str(Path('D:/modelsim/win64/vsim.exe')),'-c','-do','do run.do'],cwd=wd,capture_output=True,text=True,errors='replace')
        transcript=wd/'transcript'; log=transcript.read_text(errors='replace') if transcript.exists() else result.stdout+result.stderr
        (sim/f'migration_{test}_{"baseline" if args.baseline else "last"}.log').write_text(log,encoding='utf-8')
        passed=result.returncode==0 and f'PASS migration {test}' in log and not re.search(r'\*\* (?:Fatal|Error):',log)
        print(test, 'PASS' if passed else 'FAIL')
        print('\n'.join(log.splitlines()[-12:])); ok &= passed
raise SystemExit(0 if ok else 1)

