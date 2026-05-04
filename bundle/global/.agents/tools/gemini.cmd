@echo off
REM PATH-shim for `gemini` -- yolo + workspace expansion + version guard.
REM
REM VERSION GUARD: pins the install to 0.38.x. Auto-rolls back on launch if
REM something (npm, IDE extension, package manager hook) bumps it.
REM
REM Why pinned at 0.38.x:
REM   * 0.39.x -- thinking-loop regression: hours-long Thinking hangs.
REM       Issues #26116, #26126.
REM   * 0.40.x -- agentic delegation effectively non-functional, GEMINI.md
REM       ignored, mid-flight kit lifecycle does not fire. Issues #15037,
REM       #18064, #22093 + local empirical testing (May 2026).
REM   * 0.41.x -- preview only, has some boot-perf fixes but does not
REM       address the agentic regressions yet.
REM
REM Override (rare, opt-in): set GEMINI_KIT_ALLOW_ANY=1 to bypass the guard.

setlocal

REM Read installed version
for /f "delims=" %%v in ('"%APPDATA%\npm\gemini.cmd" --version 2^>nul') do set GEMINI_VER=%%v

if defined GEMINI_KIT_ALLOW_ANY goto run

REM Allow only 0.38.x. Anything else -> auto-rollback.
echo %GEMINI_VER% | findstr /r /c:"^0\.38\." >nul
if errorlevel 1 (
    echo.
    echo ============================================================
    echo  Gemini CLI version %GEMINI_VER% is OFF the kit's pinned line.
    echo  Auto-rolling back to 0.38.2 ^(0.39+ has known regressions^).
    echo  Override with: set GEMINI_KIT_ALLOW_ANY=1
    echo ============================================================
    call npm install -g @google/gemini-cli@0.38.2
    if errorlevel 1 (
        echo.
        echo  Rollback failed ^(usually a file lock^). Close all running
        echo  Gemini sessions, then run manually:
        echo    npm install -g @google/gemini-cli@0.38.2
        echo.
        endlocal
        exit /b 1
    )
    echo.
)

:run
"%APPDATA%\npm\gemini.cmd" --yolo --include-directories "%USERPROFILE%\.agents,%USERPROFILE%\.claude" %*

endlocal
