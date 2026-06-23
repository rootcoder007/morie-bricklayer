@echo off
REM ==========================================================
REM  morie-bricklayer Reproducibility Bundle - Windows Launcher
REM
REM  Double-click in File Explorer.
REM  Requirement: R from https://cran.r-project.org/bin/windows/base/
REM
REM  Licence: AGPL-3.0-or-later.
REM ==========================================================

cd /d "%~dp0"

cls
echo ==========================================================
echo   morie-bricklayer Reproducibility Bundle - Windows Launcher
echo ==========================================================
echo.

set "RSCRIPT="
where /Q Rscript
if %ERRORLEVEL%==0 (
    for /f "delims=" %%i in ('where Rscript') do (
        if not defined RSCRIPT set "RSCRIPT=%%i"
    )
)
if not defined RSCRIPT (
    if exist "%ProgramFiles%\R" (
        for /f "delims=" %%i in ('dir /B /OD /AD "%ProgramFiles%\R" 2^>nul') do (
            if exist "%ProgramFiles%\R\%%i\bin\Rscript.exe" set "RSCRIPT=%ProgramFiles%\R\%%i\bin\Rscript.exe"
        )
    )
)

if not defined RSCRIPT (
    echo R is NOT installed on this computer.
    echo.
    echo Please install R from:
    echo    https://cran.r-project.org/bin/windows/base/
    echo.
    echo After R is installed, double-click this file again.
    pause
    exit /b 1
)

if not exist "setup_and_run.R" (
    echo ERROR: setup_and_run.R is missing from this folder.
    echo Make sure you extracted the entire zip.
    pause
    exit /b 2
)

echo Found R at:
echo    %RSCRIPT%
echo.
echo Starting analysis...
echo.

"%RSCRIPT%" setup_and_run.R
set "RC=%ERRORLEVEL%"

echo.
echo ==========================================================
if "%RC%"=="0" (
    echo   Finished successfully.
) else (
    echo   Finished with exit code %RC%.
    echo   See run.log in the most recent results_* folder.
)
echo ==========================================================
echo.
echo Press any key to close this window...
pause >nul
exit /b %RC%
