@echo off
setlocal
set "BITSTREAM=%~dp0..\release\spectrum_65_1k.fs"
set "PROGRAMMER=D:\Gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer.exe"
if not exist "%BITSTREAM%" (
  echo ERROR: Current bitstream is missing.
  pause
  exit /b 1
)
if not exist "%PROGRAMMER%" (
  echo ERROR: Gowin Programmer is missing at the configured path.
  pause
  exit /b 1
)
start "" "%PROGRAMMER%" -family GW5AST -device GW5AST-138B -fs "%BITSTREAM%" -theme Classic
exit /b 0
