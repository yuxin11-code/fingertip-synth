"""Synthesis only in isolated project copies; never run PNR or generate .fs."""
from pathlib import Path
import argparse,shutil,subprocess,re,json,hashlib
parser=argparse.ArgumentParser(); parser.add_argument('--mode',choices=['0','1','both'],default='both'); args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
output=root/'results/migration_synthesis'; output.mkdir(exist_ok=True)
gw=Path('D:/Gowin/Gowin_V1.9.12_x64/IDE/bin/gw_sh.exe')
passed=True
for mode in (['0','1'] if args.mode=='both' else [args.mode]):
    wd=output/('mode'+mode); wd.mkdir(exist_ok=True)
    shutil.copytree(root/'src',wd/'src',dirs_exist_ok=True)
    shutil.copy2(root/'audio.gprj',wd/'audio.gprj')
    top=wd/'src/top.v'; t=top.read_text(encoding='utf-8-sig')
    t=re.sub(r'ENABLE_DUAL_PANEL\s*=\s*[01]', 'ENABLE_DUAL_PANEL = '+mode,t,count=1)
    top.write_text(t,encoding='utf-8')
    script=wd/'synthesis_only.tcl'
    script.write_text('open_project {'+str(wd/'audio.gprj').replace('\\','/')+'}\nset_option -top_module top\nrun syn\nexit\n',encoding='ascii')
    result=subprocess.run([str(gw),str(script)],cwd=wd,capture_output=True,text=True,errors='replace')
    log=result.stdout+result.stderr; (wd/'synthesis_console.log').write_text(log,encoding='utf-8')
    # gw_sh can return success after a synthesis error; require its completion marker.
    ok=result.returncode==0 and 'GowinSynthesis finish' in log and not re.search(r'ERROR\s*\(',log)
    if list(wd.rglob('*.fs')): raise RuntimeError('Unexpected bitstream generated')
    print('MODE',mode,'PASS' if ok else 'FAIL',flush=True)
    print('\n'.join(log.splitlines()[-24:]),flush=True)
    passed &= ok
raise SystemExit(0 if passed else 1)
