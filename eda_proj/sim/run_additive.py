"""Rebuild deterministic oracle and compare actual pipelined RTL, including RAM."""
from pathlib import Path
import argparse,json,shutil,subprocess,sys,tempfile
p=Path(__file__).resolve().parents[1];root=p.parent
ap=argparse.ArgumentParser();ap.add_argument('--check-rejects',action='store_true');args=ap.parse_args()
subprocess.run([sys.executable,str(root/'tools/additive_model.py'),'--tables','--vectors'],check=True)
iv=Path('C:/iverilog/bin/iverilog.exe');out=p/'results/additive';out.mkdir(parents=True,exist_ok=True)
binary=out/'additive.vvp'
r=subprocess.run([str(iv),'-g2012','-s','tb_additive_diff','-o',str(binary),str(p/'src/migration/mig_additive_engine.v'),str(p/'sim/tb_additive_diff.sv')],capture_output=True,text=True)
log=r.stdout+r.stderr
if not r.returncode:
 r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=p,capture_output=True,text=True,timeout=600)
 log+=r.stdout+r.stderr
(out/'differential.log').write_text(log,encoding='utf-8');print(log)
if r.returncode or 'PASS additive differential' not in log:raise SystemExit(r.returncode or 1)
edge_binary=out/'edges.vvp'
r=subprocess.run([str(iv),'-g2012','-s','tb_additive_edges','-o',str(edge_binary),str(p/'src/migration/mig_additive_engine.v'),str(p/'sim/tb_additive_edges.sv')],capture_output=True,text=True)
log=r.stdout+r.stderr
if not r.returncode:
 r=subprocess.run([str(iv.with_name('vvp.exe')),str(edge_binary)],cwd=p,capture_output=True,text=True,timeout=30);log+=r.stdout+r.stderr
(out/'edges.log').write_text(log,encoding='utf-8');print(log)
if r.returncode or 'PASS additive edges' not in log:raise SystemExit(r.returncode or 1)
if args.check_rejects:
 checks=[]
 # Isolate corrupted oracle files so the official golden vectors stay intact.
 for name,reason in [('missing_state','cannot open differential'),
                     ('truncated_state','state oracle truncated'),
                     ('duplicated_state','state RAM index missing, duplicated'),
                     ('truncated_samples','oracle truncated')]:
  with tempfile.TemporaryDirectory(prefix='additive_reject_') as tmp:
   wd=Path(tmp);target=wd/'results/additive';target.mkdir(parents=True)
   shutil.copytree(p/'src/migration/additive_rom',wd/'src/migration/additive_rom')
   for filename in ['stimulus.hex','expected.txt','expected_state.txt']:shutil.copy2(out/filename,target/filename)
   if name=='missing_state':(target/'expected_state.txt').unlink()
   elif name=='truncated_state':(target/'expected_state.txt').write_text((out/'expected_state.txt').read_text().splitlines()[0]+'\n',encoding='ascii')
   elif name=='duplicated_state':
    lines=(out/'expected_state.txt').read_text().splitlines();lines[1]=lines[0]
    (target/'expected_state.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
   else:(target/'expected.txt').write_text('',encoding='ascii')
   r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=wd,capture_output=True,text=True,timeout=30)
   rejected=r.returncode!=0 and 'FATAL:' in r.stdout and reason in r.stdout and 'PASS additive differential' not in r.stdout
   checks.append(dict(test=name,rejected=rejected));(out/(name+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
   if not rejected:raise RuntimeError(f'{name} was silently accepted')
 (out/'negative_checks.json').write_text(json.dumps(checks,indent=2),encoding='utf-8');print('PASS negative oracle checks:',len(checks))
