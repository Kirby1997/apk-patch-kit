@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem =====================================================================
rem patch-apks.bat - Windows/CMD port of patch-apks.sh.
rem
rem Usage:
rem   patch-apks.bat                          Interactive mode
rem   patch-apks.bat --app ^<name^>             Pick app's patches jar + apks/
rem   patch-apks.bat --apk ^<file^> --patches ^<jar^> [--cli ^<jar^>]
rem   patch-apks.bat --no-ui                  Apply all patches, no prompts
rem
rem Runs natively from Windows (cmd/PowerShell), not WSL. Requires:
rem   - JDK 17+ on PATH or JAVA_HOME set (for jar/keytool/java)
rem   - apksigner.bat on PATH (Android build-tools) for .apks bundles
rem   - PowerShell (for patch-name extraction via regex)
rem =====================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "APP="
set "APK_FILE="
set "PATCHES_JAR="
set "REVANCED_CLI="
set "NO_UI=false"

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--app"     (set "APP=%~2"         & shift & shift & goto parse)
if /I "%~1"=="--apk"     (set "APK_FILE=%~2"    & shift & shift & goto parse)
if /I "%~1"=="--patches" (set "PATCHES_JAR=%~2" & shift & shift & goto parse)
if /I "%~1"=="--cli"     (set "REVANCED_CLI=%~2"& shift & shift & goto parse)
if /I "%~1"=="--no-ui"   (set "NO_UI=true"      & shift & goto parse)
if /I "%~1"=="--help"    goto help
if /I "%~1"=="-h"        goto help
echo [-] Unknown argument: %~1. Use --help for usage. 1>&2
exit /b 1

:help
echo Usage: patch-apks.bat [OPTIONS]
echo.
echo   --app ^<name^>         App subproject name ^(e.g. hidratenow^). Auto-picks APK + patches jar
echo   --apk ^<file^>         APK or APKS file to patch
echo   --patches ^<jar^>      Patches JAR/RVP file
echo   --cli ^<jar^>          Path to revanced-cli jar
echo   --no-ui              Skip interactive UI, apply all patches
echo   -h, --help           Show this help
exit /b 0

:parsed
echo.
echo   ================================================
echo             ReVanced APK Patcher
echo   ================================================
echo.

set "TMP_DIR=%TEMP%\patch-apks-%RANDOM%%RANDOM%"
mkdir "%TMP_DIR%" >nul 2>&1

rem === Resolve JDK tools ===============================================
if defined JAVA_HOME (
    set "JAR=%JAVA_HOME%\bin\jar.exe"
    set "KEYTOOL=%JAVA_HOME%\bin\keytool.exe"
    set "JAVA=%JAVA_HOME%\bin\java.exe"
) else (
    set "JAR=jar"
    set "KEYTOOL=keytool"
    set "JAVA=java"
)

rem === Locate apksigner (needed for .apks signing) =====================
rem Prefer PATH; fall back to scanning the Android SDK build-tools dirs.
rem SDK lookup order: ANDROID_HOME, ANDROID_SDK_ROOT, %LOCALAPPDATA%\Android\Sdk.
set "APKSIGNER="
for /f "delims=" %%A in ('where apksigner.bat 2^>nul') do if not defined APKSIGNER set "APKSIGNER=%%A"
if not defined APKSIGNER for /f "delims=" %%A in ('where apksigner 2^>nul') do if not defined APKSIGNER set "APKSIGNER=%%A"
if not defined APKSIGNER (
    set "_SDK_ROOTS=%ANDROID_HOME%;%ANDROID_SDK_ROOT%;%LOCALAPPDATA%\Android\Sdk"
    for %%R in ("!_SDK_ROOTS:;=" "!") do (
        if not defined APKSIGNER if exist "%%~R\build-tools\" (
            for /f "delims=" %%V in ('dir /b /ad /o-n "%%~R\build-tools" 2^>nul') do (
                if not defined APKSIGNER if exist "%%~R\build-tools\%%V\apksigner.bat" set "APKSIGNER=%%~R\build-tools\%%V\apksigner.bat"
            )
        )
    )
)

rem === Find revanced-cli ===============================================
if not defined REVANCED_CLI (
    for %%F in ("!SCRIPT_DIR!\revanced-cli-*-all.jar") do if not defined REVANCED_CLI set "REVANCED_CLI=%%~fF"
    if not defined REVANCED_CLI for %%F in ("!SCRIPT_DIR!\revanced-cli*.jar") do if not defined REVANCED_CLI set "REVANCED_CLI=%%~fF"
)
if not defined REVANCED_CLI (
    echo [-] revanced-cli jar not found. Pass --cli ^<path^> or place one in the repo root. 1>&2
    goto fail
)
if not exist "!REVANCED_CLI!" (
    echo [-] revanced-cli jar not found: !REVANCED_CLI! 1>&2
    goto fail
)
echo [+] CLI: !REVANCED_CLI!

rem === Pick app ========================================================
if not defined APP if not defined APK_FILE if not defined PATCHES_JAR (
    if not exist "!SCRIPT_DIR!\apps" (
        echo [-] No apps\ directory found. 1>&2
        goto fail
    )
    set /a _ac=0
    for /d %%D in ("!SCRIPT_DIR!\apps\*") do (
        set /a _ac+=1
        set "_app!_ac!=%%~nxD"
    )
    if !_ac! equ 0 (
        echo [-] No app subdirectories under apps\. 1>&2
        goto fail
    )

    echo.
    echo Select app:
    echo.
    for /l %%i in (1,1,!_ac!) do call :print_app %%i
    echo.
    set "_sel="
    set /p "_sel=  Select [1]: "
    if not defined _sel set "_sel=1"
    call set "APP=%%_app!_sel!%%"
)

if defined APP (
    if not exist "!SCRIPT_DIR!\apps\!APP!" (
        echo [-] apps\!APP! does not exist. 1>&2
        goto fail
    )
    echo [+] App: !APP!
)

rem === Find patches jar ================================================
if not defined PATCHES_JAR if defined APP (
    if exist "!SCRIPT_DIR!\patches\!APP!" (
        echo.
        set "_build=Y"
        set /p "_build=  Build :patches:!APP! from source? (Y/n): "
        if /I "!_build!"=="Y" (
            echo [+] Building :patches:!APP! ...
            pushd "!SCRIPT_DIR!"
            call gradlew.bat ":patches:!APP!:build"
            set "_gradle_rc=!errorlevel!"
            popd
            if not "!_gradle_rc!"=="0" (
                echo [-] Gradle build failed ^(exit !_gradle_rc!^). 1>&2
                echo [-] Re-run for full trace: gradlew.bat :patches:!APP!:build --stacktrace 1>&2
                goto fail
            )
        )
        for %%F in ("!SCRIPT_DIR!\patches\!APP!\build\libs\*.jar") do (
            if not defined PATCHES_JAR set "PATCHES_JAR=%%~fF"
        )
    )
)

if not defined PATCHES_JAR (
    set /a _jc=0
    for /r "!SCRIPT_DIR!\patches" %%F in (*patches*.jar) do (
        set /a _jc+=1
        set "_jar!_jc!=%%~fF"
    )
    for /r "!SCRIPT_DIR!" %%F in (*.rvp) do (
        set /a _jc+=1
        set "_jar!_jc!=%%~fF"
    )
    if !_jc! equ 1 (
        set "PATCHES_JAR=!_jar1!"
    ) else if !_jc! gtr 1 (
        echo.
        echo Select patches JAR/RVP:
        echo.
        for /l %%i in (1,1,!_jc!) do call :print_jar %%i
        echo.
        set "_sel="
        set /p "_sel=  Select [1]: "
        if not defined _sel set "_sel=1"
        call set "PATCHES_JAR=%%_jar!_sel!%%"
    )
)

if not defined PATCHES_JAR (
    echo [-] Patches JAR not found. Pass --patches ^<path^>. 1>&2
    goto fail
)
if not exist "!PATCHES_JAR!" (
    echo [-] Patches JAR not found: !PATCHES_JAR! 1>&2
    goto fail
)
echo [+] Patches: !PATCHES_JAR!

rem === Find APK ========================================================
if not defined APK_FILE if defined APP if exist "!SCRIPT_DIR!\apps\!APP!\apks" (
    rem Use a single glob + exact-extension filter. Windows' *.apk glob also
    rem matches *.apks (legacy short-name behaviour), so listing both causes
    rem the .apks bundle to appear twice.
    set /a _fc=0
    for %%F in ("!SCRIPT_DIR!\apps\!APP!\apks\*.apk*") do (
        if exist "%%~F" (
            if /I "%%~xF"==".apk" (
                set /a _fc+=1
                set "_file!_fc!=%%~fF"
            ) else if /I "%%~xF"==".apks" (
                set /a _fc+=1
                set "_file!_fc!=%%~fF"
            )
        )
    )
    if !_fc! equ 1 (
        set "APK_FILE=!_file1!"
    ) else if !_fc! gtr 1 (
        echo.
        echo Select APK or APKS to patch:
        echo.
        for /l %%i in (1,1,!_fc!) do call :print_file %%i
        echo.
        set "_sel="
        set /p "_sel=  Select [1]: "
        if not defined _sel set "_sel=1"
        call set "APK_FILE=%%_file!_sel!%%"
    )
)

if not defined APK_FILE (
    echo [-] APK file not found. Pass --apk ^<path^>. 1>&2
    goto fail
)
if not exist "!APK_FILE!" (
    echo [-] APK file not found: !APK_FILE! 1>&2
    goto fail
)
echo [+] APK: !APK_FILE!

rem === Is .apks bundle? ================================================
set "IS_APKS=false"
if /I "!APK_FILE:~-5!"==".apks" (
    set "IS_APKS=true"
    if not defined APKSIGNER (
        echo [-] apksigner not found. Required for .apks bundles. 1>&2
        echo [-] Install Android build-tools and ensure apksigner.bat is on PATH. 1>&2
        goto fail
    )
)

rem === Discover patch names ============================================
echo [+] Discovering patches...
rem Use revanced-cli's dedicated list-patches subcommand — in patcher 22+ the
rem old "dry-run against the jar itself" trick crashes inside ResourcesDecoder
rem before any patches load. list-patches prints one "Name: <patch>" per patch.
"!JAVA!" -jar "!REVANCED_CLI!" list-patches -p "!PATCHES_JAR!" -b > "!TMP_DIR!\cli.txt" 2>&1

set /a _nc=0
for /f "usebackq tokens=1,* delims=:" %%A in ("!TMP_DIR!\cli.txt") do (
    if /I "%%A"=="Name" (
        set "_raw=%%B"
        if defined _raw (
            rem Strip a single leading space that follows the "Name:" delimiter.
            if "!_raw:~0,1!"==" " set "_raw=!_raw:~1!"
            set /a _nc+=1
            set "_pname!_nc!=!_raw!"
            set "_pstate!_nc!=on"
        )
    )
)

if !_nc! equ 0 (
    echo [-] No patches found in !PATCHES_JAR! 1>&2
    goto fail
)
echo [+] Found !_nc! patch^(es^)

rem === Interactive patch selector ======================================
if /I not "!NO_UI!"=="true" (
    call :selector
    if errorlevel 1 goto fail
)

rem === Print selection summary =========================================
echo.
echo [+] Patch configuration:
for /l %%i in (1,1,!_nc!) do call :print_state %%i
echo.

rem === Build revanced-cli args =========================================
rem Each enabled patch is passed as: -e "Name". --exclusive is always set.
set "CLI_PATCH_ARGS=--exclusive"
for /l %%i in (1,1,!_nc!) do call :append_flag %%i

rem === Prepare work dir ================================================
set "WORK_DIR=!SCRIPT_DIR!\build\patch-work"
if not exist "!WORK_DIR!\extracted"      mkdir "!WORK_DIR!\extracted"
if not exist "!WORK_DIR!\patched-splits" mkdir "!WORK_DIR!\patched-splits"
del /q "!WORK_DIR!\extracted\*"      2>nul
del /q "!WORK_DIR!\patched-splits\*" 2>nul
del /q "!WORK_DIR!\*.apk"            2>nul
del /q "!WORK_DIR!\*.p12"            2>nul

rem === Determine base APK ==============================================
if /I "!IS_APKS!"=="true" (
    echo [+] Extracting .apks bundle...
    pushd "!WORK_DIR!\extracted"
    "!JAR!" xf "!APK_FILE!"
    popd
    set "BASE_APK=!WORK_DIR!\extracted\base.apk"
    if not exist "!BASE_APK!" (
        echo [-] No base.apk found in the bundle. 1>&2
        goto fail
    )
) else (
    set "BASE_APK=!APK_FILE!"
)

rem === Patch ===========================================================
set "PATCHED_APK=!WORK_DIR!\patched-base.apk"
for %%F in ("!BASE_APK!") do echo [+] Patching %%~nxF...

"!JAVA!" -jar "!REVANCED_CLI!" patch -p "!PATCHES_JAR!" -b -o "!PATCHED_APK!" --force !CLI_PATCH_ARGS! "!BASE_APK!"

if not exist "!PATCHED_APK!" (
    echo [-] Patched APK not produced. 1>&2
    goto fail
)
echo [+] Patching complete

rem === Generate signing keystore =======================================
set "KEYSTORE=!WORK_DIR!\sign.p12"
set "KS_PASS=revanced"
set "KS_ALIAS=key"

echo [+] Generating signing keystore...
"!KEYTOOL!" -genkeypair -keystore "!KEYSTORE!" -storetype PKCS12 -storepass !KS_PASS! -keypass !KS_PASS! -alias !KS_ALIAS! -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=ReVanced" >nul 2>&1

rem === Sign + repackage ================================================
if /I "!IS_APKS!"=="true" (
    echo [+] Signing all APKs with consistent keystore...
    copy /y "!PATCHED_APK!" "!WORK_DIR!\patched-splits\base.apk" >nul
    call "!APKSIGNER!" sign --ks "!KEYSTORE!" --ks-pass "pass:!KS_PASS!" --ks-key-alias !KS_ALIAS! --key-pass "pass:!KS_PASS!" "!WORK_DIR!\patched-splits\base.apk"
    echo [+]   Signed: base.apk

    for %%S in ("!WORK_DIR!\extracted\split_*.apk") do (
        if exist "%%~S" (
            copy /y "%%~S" "!WORK_DIR!\patched-splits\%%~nxS" >nul
            call "!APKSIGNER!" sign --ks "!KEYSTORE!" --ks-pass "pass:!KS_PASS!" --ks-key-alias !KS_ALIAS! --key-pass "pass:!KS_PASS!" "!WORK_DIR!\patched-splits\%%~nxS"
            echo [+]   Signed: %%~nxS
        )
    )

    for %%F in ("!APK_FILE!") do set "APK_BASENAME=%%~nF"
    set "OUTPUT_APKS=!SCRIPT_DIR!\build\!APK_BASENAME!-patched.apks"
    if not exist "!SCRIPT_DIR!\build" mkdir "!SCRIPT_DIR!\build"

    echo [+] Assembling patched .apks bundle...
    pushd "!WORK_DIR!\patched-splits"
    if exist "!OUTPUT_APKS!" del "!OUTPUT_APKS!"
    "!JAR!" cMf "!OUTPUT_APKS!" *.apk
    popd

    echo [+] Output: !OUTPUT_APKS!
    echo.
    rem Neither cmd nor PowerShell expands globs inside quoted native-command
    rem args, so enumerate each split explicitly on one line.
    set INSTALL_LINE=    adb install-multiple
    for %%A in ("!WORK_DIR!\patched-splits\*.apk") do set INSTALL_LINE=!INSTALL_LINE! "%%~fA"
    echo [+] Install with:
    echo !INSTALL_LINE!
) else (
    for %%F in ("!APK_FILE!") do set "APK_BASENAME=%%~nF"
    set "OUTPUT_APK=!SCRIPT_DIR!\build\!APK_BASENAME!-patched.apk"
    if not exist "!SCRIPT_DIR!\build" mkdir "!SCRIPT_DIR!\build"

    copy /y "!PATCHED_APK!" "!OUTPUT_APK!" >nul
    if defined APKSIGNER (
        call "!APKSIGNER!" sign --ks "!KEYSTORE!" --ks-pass "pass:!KS_PASS!" --ks-key-alias !KS_ALIAS! --key-pass "pass:!KS_PASS!" "!OUTPUT_APK!" 2>nul
    ) else (
        echo [!] apksigner not found - output APK is unsigned. Install with Android build-tools.
    )

    echo [+] Output: !OUTPUT_APK!
    echo.
    echo [+] Install with:
    echo     adb install "!OUTPUT_APK!"
)

echo.
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%"
endlocal
exit /b 0

:fail
if exist "%TMP_DIR%" rmdir /s /q "%TMP_DIR%"
endlocal
exit /b 1

rem === Subroutines =====================================================
:print_app
echo   %1^) !_app%1!
exit /b 0

:print_jar
set "_j=!_jar%1!"
set "_j=!_j:%SCRIPT_DIR%\=!"
echo   %1^) !_j!
exit /b 0

:print_file
set "_f=!_file%1!"
set "_f=!_f:%SCRIPT_DIR%\=!"
echo   %1^) !_f!
exit /b 0

:print_state
if /I "!_pstate%1!"=="on" (
    echo     [x] !_pname%1!
) else (
    echo     [ ] !_pname%1!
)
exit /b 0

:print_toggle
if /I "!_pstate%1!"=="on" (
    echo     %1^) [x] !_pname%1!
) else (
    echo     %1^) [ ] !_pname%1!
)
exit /b 0

:append_flag
if /I "!_pstate%1!"=="on" set "CLI_PATCH_ARGS=!CLI_PATCH_ARGS! -e "!_pname%1!""
exit /b 0

:selector
:selector_loop
echo.
echo   +--------------------------------------------+
echo   ^|          Patch Selector                    ^|
echo   +--------------------------------------------+
echo.
for /l %%i in (1,1,!_nc!) do call :print_toggle %%i
set /a _on=0
for /l %%i in (1,1,!_nc!) do if /I "!_pstate%%i!"=="on" set /a _on+=1
echo.
echo   !_on!/!_nc! patches enabled
echo.
echo   Enter a number to toggle, or:
echo     a = all on  ^|  n = all off  ^|  Enter = continue  ^|  q = quit
echo.
set "_input="
set /p "_input=  > "
if not defined _input (
    if !_on! equ 0 (
        echo [!] No patches enabled. Select at least one or press q to quit.
        goto selector_loop
    )
    exit /b 0
)
if /I "!_input!"=="q" (
    echo Aborted.
    exit /b 1
)
if /I "!_input!"=="a" (
    for /l %%i in (1,1,!_nc!) do set "_pstate%%i=on"
    goto selector_loop
)
if /I "!_input!"=="n" (
    for /l %%i in (1,1,!_nc!) do set "_pstate%%i=off"
    goto selector_loop
)
echo !_input!|findstr /R /C:"^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo [!] Invalid input.
    goto selector_loop
)
if !_input! geq 1 if !_input! leq !_nc! (
    call set "_cur=%%_pstate!_input!%%"
    if /I "!_cur!"=="on" (
        set "_pstate!_input!=off"
    ) else (
        set "_pstate!_input!=on"
    )
    goto selector_loop
)
echo [!] Out of range.
goto selector_loop
