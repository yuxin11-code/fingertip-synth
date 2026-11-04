"""Run the real TTP229 RTL regression with ModelSim; no FPGA bitstream is built."""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vsim", default=shutil.which("vsim") or r"D:\modelsim\win64\vsim.exe")
    args = parser.parse_args()
    sim_dir = Path(__file__).resolve().parent
    source = sim_dir.parent / "src" / "ttp229_serial16.v"
    with tempfile.TemporaryDirectory(prefix="ttp229_rtl_") as temp:
        work = Path(temp)
        shutil.copy2(source, work / "ttp229_serial16.v")
        shutil.copy2(sim_dir / "tb_ttp229_realign.sv", work / "tb_ttp229_realign.sv")
        (work / "run.do").write_text(
            "onerror {quit -code 2 -f}\n"
            "onbreak {quit -code 1 -f}\n"
            "vlib work\n"
            "vlog -sv ttp229_serial16.v tb_ttp229_realign.sv\n"
            "vsim -voptargs=+acc work.tb_ttp229_realign\n"
            "run -all\n"
            "quit -code 0 -f\n", encoding="ascii")
        result = subprocess.run([args.vsim, "-c", "-do", "do run.do"], cwd=work,
                                capture_output=True, text=True, errors="replace")
        transcript = work / "transcript"
        log = transcript.read_text(errors="replace") if transcript.exists() else result.stdout + result.stderr
        (sim_dir / "ttp229_realign_last.log").write_text(log, encoding="utf-8")
        print(log)
        # Some ModelSim versions return 0 even after $fatal: verify the evidence.
        passed = result.returncode == 0 and "ALL TTP229 RTL REGRESSIONS PASSED" in log
        failed = re.search(r"FAIL case=|\*\* Fatal:|\*\* Error:", log)
        return 0 if passed and not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
