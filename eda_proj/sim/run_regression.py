"""Maintained dual-five-timbre Icarus regression (archival ModelSim benches excluded)."""
from pathlib import Path
import argparse,json,subprocess,time,xml.etree.ElementTree as ET
p=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('tests',nargs='*');ap.add_argument('--compile-only',action='store_true');ap.add_argument('--retry-failed',action='store_true');ap.add_argument('--output',type=Path);a=ap.parse_args()
out=a.output.resolve() if a.output else p/'results/integration/regression';out.mkdir(parents=True,exist_ok=True)
names=a.tests or ['dual_five_timbre','dual_five_pcm','all_timbres_strum','pluck_mode','octave','piano_cycle_regression','action_recorder','recorder_rgb','recorder_guitar','recorder_top','rp108','knob_normalize','six_knobs','rp108_top','poweron_audio']
prior=json.loads((out/'summary.json').read_text(encoding='utf-8')) if a.retry_failed else []
if a.retry_failed:names=[row['test'] for row in prior if not row['passed']]
files=[p/x.attrib['path'] for x in ET.parse(p/'audio.gprj').findall('.//File') if x.attrib.get('type')=='file.verilog' and '/gowin_' not in x.attrib['path']]
support=[p/'sim/migration_clock_models.v',p/'sim/rp108_slave_model.sv',p/'sim/tb_poweron_audio.sv']
iv=Path(r'C:\iverilog\bin\iverilog.exe');results=[]
for name in names:
    start=time.monotonic();binary=out/(name+'.vvp');bench=p/f'sim/tb_{name}.sv'
    deps=files+support+([] if bench in support else [bench])
    r=subprocess.run([str(iv),'-g2012','-I',str(p/'src/migration'),'-s','tb_'+name,'-o',str(binary),*map(str,deps)],capture_output=True,text=True)
    log=r.stdout+r.stderr
    modes=['cold','cold_right','held','warm'] if name=='poweron_audio' else ['default']
    if a.compile_only:modes=[]
    passed=not r.returncode
    if passed:
        for mode in modes:
            arg={'held':['+RESET_HELD'],'warm':['+WARM'],'cold_right':['+RIGHT_FIRST']}.get(mode,[])
            try:
                r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary),*arg],cwd=p,capture_output=True,text=True,timeout=1800)
                output=r.stdout+r.stderr;log+='\nMODE '+mode+'\n'+output
                passed=not r.returncode and 'PASS' in output and 'FATAL' not in output and 'FAIL' not in output
            except subprocess.TimeoutExpired:
                log+='\nTIMEOUT 1800 seconds\n';passed=False
            if not passed:break
    (out/(name+'.log')).write_text(log,encoding='utf-8')
    row=dict(test=name,passed=passed,compile_only=a.compile_only,seconds=round(time.monotonic()-start,2));results.append(row)
    print(json.dumps(row),flush=True)
    if not passed:print(log[-6000:],flush=True)
if a.retry_failed:
    updated={row['test']:row for row in results};results=[updated.get(row['test'],row) for row in prior]
(out/('compile_summary.json' if a.compile_only else 'summary.json')).write_text(json.dumps(results,indent=2),encoding='utf-8')
raise SystemExit(0 if all(x['passed'] for x in results) else 1)
