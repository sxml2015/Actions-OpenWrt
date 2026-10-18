@echo off
rem ============================================================================
rem  Rebuild plugins.cfg  (aarch64/Lede2512/plugins.cfg)
rem   - Build from: plugin dictionary + base config
rem   - Double-click this file, or run it from a cmd window.
rem   - No Python here? Use GitHub Actions workflow "Rebuild_Plugins" instead.
rem ============================================================================
setlocal
cd /d "%~dp0..\.."
echo ============================================================
echo   Rebuild plugins.cfg
echo   Working dir: %CD%
echo ============================================================
echo.

rem ---------------------------------------------------------------------------
rem  Find a WORKING Python.
rem
rem  IMPORTANT: %LOCALAPPDATA%\Microsoft\WindowsApps\python3.exe is a Microsoft
rem  Store stub (a symlink to AppInstallerPythonRedirector.exe). Running it does
rem  not run Python - it opens the Store or fails, so it must never be used.
rem  Every candidate below is verified with a real run before it is accepted.
rem ---------------------------------------------------------------------------
set "PY="

rem  -- 1) Python shipped with WorkBuddy (most reliable on this machine) --
for /d %%D in ("%USERPROFILE%\.workbuddy\binaries\python\versions\*") do (
    if not defined PY if exist "%%D\python.exe" set "PY=%%D\python.exe"
)
call :verify
if defined PY goto runpython

rem  -- 2) py launcher (only present when installed from python.org) --
for /f "delims=" %%P in ('py -3 -c "import sys;print(sys.executable)" 2^>nul') do (
    if not defined PY set "PY=%%P"
)
call :verify
if defined PY goto runpython

rem  -- 3) python3 / python on PATH, Store stub excluded --
for /f "delims=" %%P in ('where python3.exe 2^>nul ^| findstr /i /v "WindowsApps"') do (
    if not defined PY set "PY=%%P"
)
call :verify
if defined PY goto runpython

for /f "delims=" %%P in ('where python.exe 2^>nul ^| findstr /i /v "WindowsApps"') do (
    if not defined PY set "PY=%%P"
)
call :verify
if defined PY goto runpython

goto nopython

:runpython
echo Using: %PY%
echo.
"%PY%" aarch64\scripts\build_plugins_cfg.py %*
if errorlevel 1 goto failed
echo.
echo [DONE] aarch64\Lede2512\plugins.cfg updated.
goto end

:nopython
echo [ERROR] No working Python 3 found on this computer.
echo.
echo   Option 1: install Python 3 from https://www.python.org/downloads/
echo             (tick "Add python.exe to PATH"), then run this file again.
echo   Option 2: do it on GitHub with no local setup:
echo             Actions -^> "Rebuild_Plugins" -^> Run workflow
echo.
goto end

:failed
echo.
echo [FAILED] See the message above.
echo.
echo   The real error is printed above this line. Usual causes:
echo     - aarch64\Lede2512\插件字典.tsv or Lede2512_FOL.config is missing
echo     - the file was saved as UTF-16 / has a broken encoding
echo     - a syntax error in aarch64\scripts\build_plugins_cfg.py

:end
echo.
pause
goto :eof

rem ---------------------------------------------------------------------------
rem  :verify - clear PY when the candidate does not actually run
rem ---------------------------------------------------------------------------
:verify
if not defined PY goto :eof
"%PY%" -c "import sys" >nul 2>&1
if errorlevel 1 (
    echo [WARN] not a working Python, skipped: %PY%
    set "PY="
)
goto :eof
