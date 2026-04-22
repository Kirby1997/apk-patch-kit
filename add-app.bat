@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem =====================================================================
rem add-app.bat - Windows/CMD port of add-app.sh.
rem
rem Usage:
rem   add-app.bat                                    Interactive device+package, name auto-derived
rem   add-app.bat ^<package^>                          Package arg, name auto-derived
rem   add-app.bat --name ^<shortname^> [package]       Force shortname, skip aapt derivation
rem   add-app.bat --scaffold-only --name ^<n^> ^<pkg^>  Skip adb/aapt, create files only
rem   add-app.bat --adb ^<path^>                       Override adb.exe location
rem   add-app.bat --aapt ^<path^>                      Override aapt.exe location
rem
rem Name is derived from the APK's Application label via aapt dump badging so
rem the same app always lands in apps\^<name^>\ regardless of who runs the
rem script. This prevents duplicate subprojects for the same package.
rem
rem Runs natively from Windows (cmd/PowerShell), not WSL. Requires:
rem   - JDK 17+ on PATH or JAVA_HOME set (for jar.exe)
rem   - adb.exe on PATH or at a standard Android SDK location (auto-detected)
rem   - aapt.exe (Android SDK build-tools) - auto-detected unless --name given
rem   - PowerShell (for SHA-256 + label extraction)
rem =====================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "SCAFFOLD_ONLY=false"
set "ADB_OVERRIDE="
set "AAPT_OVERRIDE="
set "APP_NAME="
set "APP_PACKAGE="
set "APP_VERSION="
set "TMP_DIR=%TEMP%\add-app-%RANDOM%%RANDOM%"
mkdir "%TMP_DIR%" >nul 2>&1

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--scaffold-only" (set "SCAFFOLD_ONLY=true" & shift & goto parse)
if /I "%~1"=="--adb"           (set "ADB_OVERRIDE=%~2" & shift & shift & goto parse)
if /I "%~1"=="--aapt"          (set "AAPT_OVERRIDE=%~2" & shift & shift & goto parse)
if /I "%~1"=="--name"          (set "APP_NAME=%~2" & shift & shift & goto parse)
if /I "%~1"=="--help"          goto help
if /I "%~1"=="-h"              goto help
if not defined APP_PACKAGE (
    set "APP_PACKAGE=%~1"
) else (
    echo [-] Unexpected positional argument: %~1 1>&2
    goto fail
)
shift
goto parse

:help
echo Usage: add-app.bat [package]
echo.
echo   --name ^<shortname^>    Override the auto-derived app shortname
echo   --scaffold-only       Skip adb/aapt, create files only (requires --name and package)
echo   --adb ^<path^>          Override adb.exe binary location
echo   --aapt ^<path^>         Override aapt.exe binary location
echo   -h, --help            Show this help
goto cleanup_ok

:parsed
rem Validate any user-supplied --name upfront (outside compound blocks so the
rem ^-anchor in the findstr regex survives cmd's parser).
if not defined APP_NAME goto after_name_validate
echo !APP_NAME!|findstr /R /C:"^[a-z][a-z0-9]*$" >nul
if errorlevel 1 (
    echo [-] --name must match [a-z][a-z0-9]* ^(lowercase letters/digits, leading letter^). Got: !APP_NAME! 1>&2
    goto fail
)
:after_name_validate

if /I "!SCAFFOLD_ONLY!"=="true" (
    if not defined APP_NAME (
        echo [-] --scaffold-only requires --name ^<shortname^>. 1>&2
        goto fail
    )
    if not defined APP_PACKAGE (
        echo [-] --scaffold-only requires a ^<package^> argument. 1>&2
        goto fail
    )
)

set "SETTINGS_FILE=!SCRIPT_DIR!\settings.gradle.kts"
if not exist "!SETTINGS_FILE!" (
    echo [-] Root settings.gradle.kts not found - run from the repo root. 1>&2
    goto fail
)

rem === Resolve JDK tools ==============================================
if defined JAVA_HOME (
    set "JAR=%JAVA_HOME%\bin\jar.exe"
) else (
    set "JAR=jar"
)

rem === Locate adb.exe ==================================================
set "ADB="
if /I "!SCAFFOLD_ONLY!"=="false" (
    if defined ADB_OVERRIDE (
        set "ADB=!ADB_OVERRIDE!"
    ) else (
        for /f "delims=" %%A in ('where adb.exe 2^>nul') do if not defined ADB set "ADB=%%A"
        if not defined ADB (
            for %%P in (^
                "C:\ProgramData\chocolatey\bin\adb.exe"^
                "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"^
                "C:\Program Files\Android\Sdk\platform-tools\adb.exe"^
                "C:\Program Files (x86)\Android\Sdk\platform-tools\adb.exe"^
            ) do if exist "%%~P" if not defined ADB set "ADB=%%~P"
        )
    )
    if not defined ADB (
        echo [-] adb.exe not found. Install Android Platform Tools or pass --adb ^<path^>. 1>&2
        echo [-] For file-only scaffolding, pass --scaffold-only --name ^<n^> ^<package^>. 1>&2
        goto fail
    )
    echo [+] Using adb: !ADB!
    "!ADB!" start-server >nul 2>&1
)

rem === Locate aapt.exe (only if we need to derive the name) ============
set "AAPT="
if /I "!SCAFFOLD_ONLY!"=="false" if not defined APP_NAME (
    if defined AAPT_OVERRIDE (
        set "AAPT=!AAPT_OVERRIDE!"
    ) else (
        for /f "delims=" %%A in ('where aapt.exe 2^>nul') do if not defined AAPT set "AAPT=%%A"
        if not defined AAPT (
            rem Scan standard SDK build-tools locations; dir /b lists versioned
            rem subdirs in ascending order, so the last match is the newest.
            for %%B in (^
                "%LOCALAPPDATA%\Android\Sdk\build-tools"^
                "C:\Program Files\Android\Sdk\build-tools"^
                "C:\Program Files (x86)\Android\Sdk\build-tools"^
            ) do (
                if exist "%%~B" (
                    for /f "delims=" %%D in ('dir /b /ad "%%~B" 2^>nul') do (
                        if exist "%%~B\%%D\aapt.exe" set "AAPT=%%~B\%%D\aapt.exe"
                    )
                )
            )
        )
    )
    if not defined AAPT (
        echo [-] aapt.exe not found. Install Android SDK build-tools, pass --aapt ^<path^>, 1>&2
        echo [-] or pass --name ^<shortname^> to skip auto-derivation. 1>&2
        goto fail
    )
    echo [+] Using aapt: !AAPT!
)

rem === Device selection ================================================
set "DEVICE_SERIAL="
if /I "!SCAFFOLD_ONLY!"=="false" (
    "!ADB!" devices > "!TMP_DIR!\devices.txt" 2>nul
    set /a _dc=0
    for /f "usebackq skip=1 tokens=1,2" %%D in ("!TMP_DIR!\devices.txt") do (
        if /I "%%E"=="device" (
            set /a _dc+=1
            set "_dev!_dc!=%%D"
        )
    )

    if !_dc! equ 0 (
        echo [-] No authorised devices connected. 1>&2
        echo [-] Unlock the device, authorise USB debugging, or use --scaffold-only. 1>&2
        goto fail
    ) else if !_dc! equ 1 (
        set "DEVICE_SERIAL=!_dev1!"
        echo [+] Device: !DEVICE_SERIAL!
    ) else (
        echo.
        echo Multiple devices connected - select one:
        for /l %%i in (1,1,!_dc!) do call :print_dev %%i
        set "_idx="
        set /p "_idx=  Select [1]: "
        if not defined _idx set "_idx=1"
        call set "DEVICE_SERIAL=%%_dev!_idx!%%"
        echo [+] Device: !DEVICE_SERIAL!
    )
)

rem === Package selection ===============================================
rem Runs in a subroutine so its prompt-retry labels live at top level of the
rem script (labels inside compound if-blocks are flaky across CMD versions).
if /I "!SCAFFOLD_ONLY!"=="false" if not defined APP_PACKAGE (
    call :pick_package
    if errorlevel 1 goto fail
)

if defined APP_PACKAGE (
    echo !APP_PACKAGE!|findstr /R /C:"^[a-zA-Z][a-zA-Z0-9_]*\.[a-zA-Z]" >nul
    if errorlevel 1 (
        echo [-] Package name looks invalid: !APP_PACKAGE! 1>&2
        goto fail
    )
)

rem === Pull APKs to staging TMP ========================================
rem We don't know the final apps\^<name^>\ directory yet - the name is derived
rem from aapt after we have base.apk locally. Pull into a tmpdir first, then
rem move into place once the name is known.
set /a _ac=0
set "BASE_APK="

if /I "!SCAFFOLD_ONLY!"=="false" (
    echo [+] Resolving APK paths for !APP_PACKAGE!...
    "!ADB!" -s !DEVICE_SERIAL! shell pm path !APP_PACKAGE! > "!TMP_DIR!\paths.txt" 2>nul
    for /f "usebackq tokens=* delims=" %%L in ("!TMP_DIR!\paths.txt") do (
        set "_line=%%L"
        set "_line=!_line:package:=!"
        if defined _line (
            set /a _ac+=1
            set "_apk!_ac!=!_line!"
        )
    )
    if !_ac! equ 0 (
        echo [-] Package !APP_PACKAGE! not installed on device. 1>&2
        goto fail
    )
    echo [+] Found !_ac! APK^(s^) on device

    "!ADB!" -s !DEVICE_SERIAL! shell dumpsys package !APP_PACKAGE! > "!TMP_DIR!\dumpsys.txt" 2>nul
    for /f "tokens=2 delims==" %%V in ('findstr /C:"versionName" "!TMP_DIR!\dumpsys.txt"') do (
        if not defined APP_VERSION for /f "tokens=1" %%W in ("%%V") do set "APP_VERSION=%%W"
    )
    if defined APP_VERSION echo [+] Version: !APP_VERSION!

    mkdir "!TMP_DIR!\apks" >nul 2>&1
    for /l %%i in (1,1,!_ac!) do call :pull_apk_tmp %%i
)

rem === Derive APP_NAME from Application label ==========================
if /I "!SCAFFOLD_ONLY!"=="false" if not defined APP_NAME (
    if not defined BASE_APK (
        echo [-] Could not identify base.apk for aapt inspection. 1>&2
        goto fail
    )
    "!AAPT!" dump badging "!BASE_APK!" > "!TMP_DIR!\badging.txt" 2>nul
    if errorlevel 1 (
        echo [-] aapt dump badging failed for !BASE_APK!. 1>&2
        goto fail
    )
    call :derive_name
    if errorlevel 1 goto fail
    echo [+] Derived shortname: !APP_NAME!
)

if not defined APP_NAME (
    echo [-] APP_NAME is unset - internal error. 1>&2
    goto fail
)

rem Final name validation (covers both user-supplied and derived names).
echo !APP_NAME!|findstr /R /C:"^[a-z][a-z0-9]*$" >nul
if errorlevel 1 (
    echo [-] Shortname '!APP_NAME!' is invalid. Pass --name ^<shortname^> to override. 1>&2
    goto fail
)

set "APP_DIR=!SCRIPT_DIR!\apps\!APP_NAME!"
set "PATCHES_DIR=!SCRIPT_DIR!\patches\!APP_NAME!"

if exist "!APP_DIR!" (
    echo [-] apps\!APP_NAME! already exists - this app has been scaffolded before. 1>&2
    echo [-] Remove it first, or pass --name ^<other^> for a variant. 1>&2
    goto fail
)
if exist "!PATCHES_DIR!" (
    echo [-] patches\!APP_NAME! already exists. Remove it first. 1>&2
    goto fail
)

rem === Move staged APKs into place ======================================
if not exist "!APP_DIR!\apks" mkdir "!APP_DIR!\apks"

if /I "!SCAFFOLD_ONLY!"=="false" (
    for %%F in ("!TMP_DIR!\apks\*.apk") do (
        move "%%~F" "!APP_DIR!\apks\%%~nxF" >nul
    )

    if !_ac! gtr 1 (
        set "_bundle=!APP_DIR!\apks\!APP_PACKAGE!.apks"
        echo [+] Assembling .apks bundle: !APP_PACKAGE!.apks
        if exist "!_bundle!" del "!_bundle!"
        pushd "!APP_DIR!\apks"
        "!JAR!" cMf "!APP_PACKAGE!.apks" *.apk
        popd
    )
)

rem === SHA-256 table ===================================================
set "SHA_TMP=!TMP_DIR!\sha.txt"
if exist "!SHA_TMP!" del "!SHA_TMP!"
for %%F in ("!APP_DIR!\apks\*.apk" "!APP_DIR!\apks\*.apks") do (
    if exist "%%~F" (
        for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath '%%~F' -Algorithm SHA256).Hash.ToLower()"`) do (
            >>"!SHA_TMP!" echo ^| `%%~nxF` ^| `%%H` ^|
        )
    )
)

rem === Scaffold patches subproject =====================================
echo [+] Scaffolding patches\!APP_NAME!...
set "KT_DIR=!PATCHES_DIR!\src\main\kotlin\app\revanced\patches\!APP_NAME!"
mkdir "!KT_DIR!" 2>nul
type nul > "!KT_DIR!\.gitkeep"

(
    echo plugins {
    echo     alias^(libs.plugins.kotlin.jvm^)
    echo }
    echo.
    echo dependencies {
    echo     implementation^(libs.revanced.patcher^)
    echo     implementation^(libs.smali^)
    echo }
    echo.
    echo kotlin {
    echo     jvmToolchain^(17^)
    echo     compilerOptions {
    echo         freeCompilerArgs.addAll^("-Xcontext-receivers", "-Xskip-prerelease-check"^)
    echo     }
    echo }
    echo.
    echo tasks.jar {
    echo     archiveBaseName.set^("!APP_NAME!-patches"^)
    echo }
) > "!PATCHES_DIR!\build.gradle.kts"

rem === README ==========================================================
if not defined APP_PACKAGE set "APP_PACKAGE=TODO-fill-in"
if not defined APP_VERSION set "APP_VERSION=TODO-fill-in"

(
    echo # !APP_NAME!
    echo.
    echo - **Package:** `!APP_PACKAGE!`
    echo - **Target version:** `!APP_VERSION!`
    echo - **Patches module:** `:patches:!APP_NAME!`
    echo.
    echo ^> Scaffolded by `add-app.sh` / `add-app.bat`, which pulled the APK ^(and any splits^) from a connected device via `adb pull`. Re-running the script on a different device with the same package produces the same `apps/^<name^>/` layout.
    echo.
    echo ## APKs
    echo.
    echo The `apks/` directory is git-ignored - APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror ^(or re-run `add-app.sh` against a device that has the app installed^) and place them in `apks/`.
    echo.
    echo Expected files and checksums ^(SHA-256^):
    echo.
    echo ^| File ^| SHA-256 ^|
    echo ^|------^|---------^|
) > "!APP_DIR!\README.md"

if exist "!SHA_TMP!" (
    type "!SHA_TMP!" >> "!APP_DIR!\README.md"
) else (
    >>"!APP_DIR!\README.md" echo ^| TODO ^| TODO ^|
)

(
    echo.
    echo ## Applying patches
    echo.
    echo From the repo root:
    echo.
    echo ```cmd
    echo patch-apks.bat --app !APP_NAME!
    echo ```
    echo.
    echo ## Writing patches
    echo.
    echo Place Kotlin patch files under `patches\!APP_NAME!\src\main\kotlin\app\revanced\patches\!APP_NAME!\`. Each patch should:
    echo.
    echo - Use the `bytecodePatch { ... }` DSL
    echo - Declare `compatibleWith^("!APP_PACKAGE!"^("!APP_VERSION!"^)^)`
    echo - Anchor fingerprints on fully-qualified class types rather than opcode patterns
) >> "!APP_DIR!\README.md"

rem === Wire into settings.gradle.kts ===================================
findstr /C:":patches:!APP_NAME!" "!SETTINGS_FILE!" >nul
if errorlevel 1 (
    echo [+] Adding :patches:!APP_NAME! to settings.gradle.kts
    >>"!SETTINGS_FILE!" echo include^(":patches:!APP_NAME!"^)
) else (
    echo [+] settings.gradle.kts already includes :patches:!APP_NAME!
)

rem === Summary =========================================================
echo.
echo [+] Done.
echo.
echo   App:      !APP_NAME!
echo   Package:  !APP_PACKAGE!
echo   Version:  !APP_VERSION!
echo   Patches:  patches\!APP_NAME!\
echo   APKs:     apps\!APP_NAME!\apks\
echo.
echo   Next:
echo     1. Drop .kt patch files under patches\!APP_NAME!\src\main\kotlin\app\revanced\patches\!APP_NAME!\
echo     2. Run: gradlew.bat :patches:!APP_NAME!:build
echo     3. Run: patch-apks.bat --app !APP_NAME!
echo.

:cleanup_ok
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%"
endlocal
exit /b 0

:fail
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%"
endlocal
exit /b 1

rem === Subroutines =====================================================
:print_dev
echo   %1^) !_dev%1!
exit /b 0

:print_pkg
echo   %1^) !_pkg%1!
exit /b 0

:pull_apk_tmp
call set "_remote=%%_apk%1%%"
for %%F in ("!_remote!") do set "_name=%%~nxF"
echo [+]   Pulling !_name!...
"!ADB!" -s !DEVICE_SERIAL! pull "!_remote!" "!TMP_DIR!\apks\!_name!" >nul
rem Prefer a file literally named base.apk; fall back to the first pulled APK.
if /I "!_name!"=="base.apk" (
    set "BASE_APK=!TMP_DIR!\apks\!_name!"
) else if not defined BASE_APK (
    set "BASE_APK=!TMP_DIR!\apks\!_name!"
)
exit /b 0

:pick_package
echo [+] Listing user-installed packages on device...
"!ADB!" -s !DEVICE_SERIAL! shell pm list packages -3 > "!TMP_DIR!\pkgs.txt" 2>nul
set /a _pc=0
for /f "usebackq tokens=* delims=" %%L in ("!TMP_DIR!\pkgs.txt") do (
    set "_line=%%L"
    set "_line=!_line:package:=!"
    if defined _line (
        set /a _pc+=1
        set "_pkg!_pc!=!_line!"
    )
)
if !_pc! equ 0 (
    echo [-] No third-party packages found on device. 1>&2
    exit /b 1
)
echo.
echo Installed packages:
echo.
for /l %%i in (1,1,!_pc!) do call :print_pkg %%i
echo.

:pkg_prompt
set "_sel="
set /p "_sel=  Package or index: "
if not defined _sel goto pkg_prompt
echo !_sel!|findstr /R /C:"^[0-9][0-9]*$" >nul
if not errorlevel 1 (
    if !_sel! geq 1 if !_sel! leq !_pc! (
        call set "APP_PACKAGE=%%_pkg!_sel!%%"
        exit /b 0
    )
    echo   Out of range. Try again.
    goto pkg_prompt
)
for /l %%i in (1,1,!_pc!) do (
    call set "_p=%%_pkg%%i%%"
    if /I "!_p!"=="!_sel!" (
        set "APP_PACKAGE=!_sel!"
        exit /b 0
    )
)
echo   Not found: !_sel!. Try again.
goto pkg_prompt

:derive_name
rem Parse application-label from aapt badging output and sanitize.
rem Writes a helper .ps1, runs it, captures the single-line result.
(
    echo $out = Get-Content -LiteralPath $env:PS_BADGING
    echo $label = $null
    echo foreach ^($line in $out^) {
    echo     if ^($line -match "^^application-label:'^(.+?^)'"^) {
    echo         $label = $Matches[1]
    echo         break
    echo     }
    echo }
    echo if ^(-not $label^) { exit 1 }
    echo $s = ^($label.ToLower^(^) -replace '[^^a-z0-9]',''^)
    echo if ^(-not $s^) { exit 1 }
    echo if ^($s -notmatch '^^[a-z]'^) { $s = "a$s" }
    echo $s
) > "!TMP_DIR!\derive.ps1"

set "PS_BADGING=!TMP_DIR!\badging.txt"
set "APP_NAME="
for /f "usebackq delims=" %%N in (`powershell -NoProfile -ExecutionPolicy Bypass -File "!TMP_DIR!\derive.ps1"`) do set "APP_NAME=%%N"

if not defined APP_NAME (
    echo [-] Could not derive shortname from APK label. 1>&2
    echo [-] Pass --name ^<shortname^> to override. 1>&2
    exit /b 1
)
exit /b 0
