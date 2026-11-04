"""Compile and simulate both engine selections with the all-off FX bypass check."""
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

EDA = Path(__file__).resolve().parents[1]
OUT = EDA / "results/ui512_fx"
OUT.mkdir(parents=True, exist_ok=True)
IV = Path(r"C:\iverilog\bin\iverilog.exe")
sources = [EDA / e.attrib["path"] for e in ET.parse(EDA / "audio.gprj").findall(".//File")
           if e.attrib.get("type") == "file.verilog" and "/gowin_" not in e.attrib["path"]]
sources += [EDA / "sim/migration_clock_models.v", EDA / "sim/tb_fx_top_bypass.sv"]

for mode in (0, 1):
    binary = OUT / f"dual_mode_{mode}.vvp"
    args = [str(IV), "-g2012", "-I", str(EDA / "src/migration"),
            "-s", "tb_fx_top_bypass", f"-Ptb_fx_top_bypass.SYNTH_MODE={mode}",
            "-o", str(binary), *map(str, sources)]
    compile_result = subprocess.run(args, cwd=EDA, capture_output=True, text=True)
    if compile_result.returncode:
        raise RuntimeError(f"mode {mode} compile: {compile_result.stderr[-3000:]}")
    run = subprocess.run([str(IV.with_name("vvp.exe")), str(binary)], cwd=EDA,
                         capture_output=True, text=True, timeout=300)
    log = compile_result.stderr + run.stdout + run.stderr
    (OUT / f"dual_mode_{mode}.log").write_text(log, encoding="utf-8")
    if run.returncode or f"PASS FX top mode={mode} all_off_mismatches=0" not in log:
        raise RuntimeError(f"mode {mode}: {log[-3000:]}")
    print(f"PASS dual mode {mode} all-off bypass mismatches=0")
