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

set PY=
for /f "delims=" %%P in ('where py.exe 2^>nul') do if not defined PY set "PY=py -3"
for /f "delims=" %%P in ('where python3.exe 2^>nul') do if not defined PY set "PY=%%P"
for /f "delims=" %%P in ('where python.exe 2^>nul') do if not defined PY set "PY=%%P"
if defined PY goto runpython
if exist "%USERPROFILE%\.workbuddy\binaries\python\versions\3.13.12\python.exe" set PY="%USERPROFILE%\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not defined PY goto nopython

:runpython
echo Using: %PY%
echo.
%PY% aarch64\scripts\build_plugins_cfg.py %*
if errorlevel 1 goto failed
echo.
echo [DONE] aarch64\Lede2512\plugins.cfg updated.
goto end

:nopython
echo [ERROR] Python 3 not found on this computer.
echo.
echo   Option 1: install Python 3, then run this file again.
echo   Option 2: do it on GitHub with no local setup:
echo             Actions -^> "Rebuild_Plugins" -^> Run workflow
echo.
goto end

:failed
echo.
echo [FAILED] See the message above.

:end
echo.
pause
