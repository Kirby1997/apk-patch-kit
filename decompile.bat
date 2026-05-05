@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem =====================================================================
rem decompile.bat - Windows/CMD port of decompile.sh.
rem
rem Usage:
rem   decompile.bat                       Interactive: pick from apps\*
rem   decompile.bat ^<app^>                Decompile apps\^<app^>\apks\base.apk
rem   decompile.bat ^<app^> --force        Overwrite an existing decompiled-apktool\
rem   decompile.bat --apk ^<path^> ^<app^>  Decompile a specific APK (output still under apps\^<app^>\)
rem   decompile.bat --apktool ^<path^>     Override apktool binary (apktool.bat or apktool)
rem
rem Runs natively from Windows (cmd/PowerShell), not WSL. Requires apktool
rem on PATH (chocolatey ships apktool.bat at C:\ProgramData\chocolatey\bin\)
rem or pass --apktool ^<path^>.
rem =====================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "APP_NAME="
set "APK_OVERRIDE="
set "APKTOOL_OVERRIDE="
set "FORCE=false"

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--force"   (set "FORCE=true" & shift & goto parse)
if /I "%~1"=="-f"        (set "FORCE=true" & shift & goto parse)
if /I "%~1"=="--apk"     (set "APK_OVERRIDE=%~2" & shift & shift & goto parse)
if /I "%~1"=="--apktool" (set "APKTOOL_OVERRIDE=%~2" & shift & shift & goto parse)
if /I "%~1"=="--help"    goto help
if /I "%~1"=="-h"        goto help
if not defined APP_NAME (
    set "APP_NAME=%~1"
) else (
    echo [-] Unexpected positional argument: %~1 1>&2
    goto fail
)
shift
goto parse

:help
echo Usage: decompile.bat [app] [--force] [--apk path] [--apktool path]
echo.
echo   ^<app^>                Name of an app under apps\ (interactive picker if omitted)
echo   --force, -f          Overwrite an existing decompiled-apktool\ directory
echo   --apk ^<path^>         Decompile a specific APK instead of apps\^<app^>\apks\base.apk
echo   --apktool ^<path^>     Override apktool binary location
echo   -h, --help           Show this help
goto cleanup_ok

:parsed

rem === Locate apktool ==================================================
set "APKTOOL="
if defined APKTOOL_OVERRIDE (
    set "APKTOOL=!APKTOOL_OVERRIDE!"
) else (
    for /f "delims=" %%A in ('where apktool.bat 2^>nul') do if not defined APKTOOL set "APKTOOL=%%A"
    if not defined APKTOOL (
        for /f "delims=" %%A in ('where apktool 2^>nul')     do if not defined APKTOOL set "APKTOOL=%%A"
    )
    if not defined APKTOOL (
        for %%P in (^
            "C:\ProgramData\chocolatey\bin\apktool.bat"^
            "C:\ProgramData\chocolatey\bin\apktool"^
        ) do if exist "%%~P" if not defined APKTOOL set "APKTOOL=%%~P"
    )
)
if not defined APKTOOL (
    echo [-] apktool not found. Install via 'choco install apktool', put apktool.bat on PATH, 1>&2
    echo [-] or pass --apktool ^<path^>. 1>&2
    goto fail
)
echo [+] Using apktool: !APKTOOL!

rem === Pick app (interactive if not supplied) ==========================
if not defined APP_NAME (
    if not exist "!SCRIPT_DIR!\apps" (
        echo [-] apps\ directory not found - run from the repo root. 1>&2
        goto fail
    )
    set /a _ac=0
    for /f "usebackq delims=" %%D in (`dir /b /ad "!SCRIPT_DIR!\apps" 2^>nul`) do (
        set /a _ac+=1
        set "_app!_ac!=%%D"
    )
    if !_ac! equ 0 (
        echo [-] No apps under apps\ - run add-app.bat first. 1>&2
        goto fail
    )
    echo.
    echo Select an app to decompile:
    for /l %%i in (1,1,!_ac!) do call :print_app %%i
    set "_idx="
    set /p "_idx=  Select [1]: "
    if not defined _idx set "_idx=1"
    echo !_idx!|findstr /R /C:"^[0-9][0-9]*$" >nul
    if errorlevel 1 (
        echo [-] Invalid selection: !_idx! 1>&2
        goto fail
    )
    if !_idx! lss 1 (
        echo [-] Invalid selection: !_idx! 1>&2
        goto fail
    )
    if !_idx! gtr !_ac! (
        echo [-] Invalid selection: !_idx! 1>&2
        goto fail
    )
    call set "APP_NAME=%%_app!_idx!%%"
)

set "APP_DIR=!SCRIPT_DIR!\apps\!APP_NAME!"
if not exist "!APP_DIR!" (
    echo [-] apps\!APP_NAME! not found. Run add-app.bat to scaffold it. 1>&2
    goto fail
)

rem === Resolve source APK ==============================================
if defined APK_OVERRIDE (
    set "SRC_APK=!APK_OVERRIDE!"
) else (
    set "SRC_APK=!APP_DIR!\apks\base.apk"
)
if not exist "!SRC_APK!" (
    echo [-] APK not found: !SRC_APK! 1>&2
    echo [-] Place base.apk under apps\!APP_NAME!\apks\ ^(re-run add-app.bat against the device, or copy the APK in manually^). 1>&2
    goto fail
)

set "OUT_DIR=!APP_DIR!\decompiled-apktool"

if exist "!OUT_DIR!" (
    if /I "!FORCE!"=="true" (
        echo [+] Removing existing !OUT_DIR! ^(--force^)
        rmdir /s /q "!OUT_DIR!"
    ) else (
        echo [-] !OUT_DIR! already exists. Pass --force to overwrite. 1>&2
        goto fail
    )
)

echo [+] Decompiling !SRC_APK! -^> !OUT_DIR!\
call "!APKTOOL!" d "!SRC_APK!" -o "!OUT_DIR!"
if errorlevel 1 (
    echo [-] apktool failed. 1>&2
    goto fail
)

echo.
echo [+] Done.
echo   Smali:     apps\!APP_NAME!\decompiled-apktool\smali_classes*\
echo   Resources: apps\!APP_NAME!\decompiled-apktool\res\
echo   Manifest:  apps\!APP_NAME!\decompiled-apktool\AndroidManifest.xml
echo.
echo   Reverse-engineering recipes are in CLAUDE.md.

:cleanup_ok
endlocal
exit /b 0

:fail
endlocal
exit /b 1

rem === Subroutines =====================================================
:print_app
echo   %1^) !_app%1!
exit /b 0
