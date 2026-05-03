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
set "SIGN_ONLY=false"
set "PACKAGE="
set "INCLUDE_UNIVERSAL=false"
set "NO_FILTER=false"
set "INSTALL=false"
set "REINSTALL=false"
set "ADB_OVERRIDE="
if not defined MAPS_KEY set "MAPS_KEY=%MAPS_API_KEY%"

:parse
if "%~1"=="" goto parsed
if /I "%~1"=="--app"               (set "APP=%~2"         & shift & shift & goto parse)
if /I "%~1"=="--apk"               (set "APK_FILE=%~2"    & shift & shift & goto parse)
if /I "%~1"=="--patches"           (set "PATCHES_JAR=%~2" & shift & shift & goto parse)
if /I "%~1"=="--cli"               (set "REVANCED_CLI=%~2"& shift & shift & goto parse)
if /I "%~1"=="--no-ui"             (set "NO_UI=true"      & shift & goto parse)
if /I "%~1"=="--sign-only"         (set "SIGN_ONLY=true"  & shift & goto parse)
if /I "%~1"=="--maps-key"          (set "MAPS_KEY=%~2"    & shift & shift & goto parse)
if /I "%~1"=="--package"           (set "PACKAGE=%~2"     & shift & shift & goto parse)
if /I "%~1"=="--include-universal" (set "INCLUDE_UNIVERSAL=true" & shift & goto parse)
if /I "%~1"=="--no-filter"         (set "NO_FILTER=true"  & shift & goto parse)
if /I "%~1"=="--install"           (set "INSTALL=true"    & shift & goto parse)
if /I "%~1"=="--reinstall"         (set "INSTALL=true"    & set "REINSTALL=true" & shift & goto parse)
if /I "%~1"=="--adb"               (set "ADB_OVERRIDE=%~2"& shift & shift & goto parse)
if /I "%~1"=="--help"              goto help
if /I "%~1"=="-h"                  goto help
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
echo   --sign-only          Skip patching entirely, just re-sign and repack
echo   --maps-key ^<key^>     Google Maps API key for 'Inject Google Maps API key' patch
echo.
echo Install:
echo   --install            adb-install the patched APK after building ^(in-place; keeps app data.
echo                        Bails with a hint if the device's installed copy was signed differently^).
echo   --reinstall          As --install, but uninstall first ^(wipes app data — only needed when
echo                        transitioning from the Play Store build to the patched build^).
echo   --adb ^<path^>         Override adb binary location ^(default: PATH, then chocolatey/SDK paths^).
echo.
echo Patch filtering ^(applies when using a large upstream bundle like patches.rvp^):
echo   --package ^<pkg^>      Package name to filter patches by ^(e.g. com.strava^).
echo                        Auto-read from apps\^<app^>\README.md when --app is used.
echo   --include-universal  Also show universal patches ^(compatible with any app^).
echo                        Off by default to keep the selector small.
echo   --no-filter          Disable package filtering entirely.
echo.
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

rem === Find revanced-cli (skipped in --sign-only) ======================
if /I "!SIGN_ONLY!"=="true" (
    echo [+] Sign-only mode: skipping patcher ^(will re-sign the original APK unchanged^)
) else (
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
)

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

rem === Find patches jar (skipped in --sign-only) =======================
if /I not "!SIGN_ONLY!"=="true" (
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
)

rem === Find APK ========================================================
if not defined APK_FILE if defined APP if exist "!SCRIPT_DIR!\apps\!APP!\apks" (
    rem Prefer a .apks bundle if one exists — it contains base + every split,
    rem so the standalone .apk files alongside it are redundant. Fall back to
    rem .apk files only when no bundle is present, and drop split_*.apk in
    rem that case (splits carry no dex, can't be patched on their own).
    set /a _fc=0
    for %%F in ("!SCRIPT_DIR!\apps\!APP!\apks\*.apks") do (
        if exist "%%~F" if /I "%%~xF"==".apks" (
            set /a _fc+=1
            set "_file!_fc!=%%~fF"
        )
    )
    if !_fc! equ 0 for %%F in ("!SCRIPT_DIR!\apps\!APP!\apks\*.apk") do (
        if exist "%%~F" if /I "%%~xF"==".apk" (
            set "_nm=%%~nxF"
            if /I not "!_nm:~0,6!"=="split_" (
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

rem === Resolve package name for filtering =============================
rem Precedence: --package <pkg> > apps\<app>\README.md "Package:" line.
rem If we end up with no package and --no-filter isn't set, the list-patches
rem call is unfiltered — preserves behaviour for ad-hoc --apk runs where
rem we can't derive a package locally.
rem
rem Parse: the README line is `- **Package:** `com.foo.bar``. findstr matches
rem the prefix; `for /f tokens=2 delims=backtick` picks the package between the
rem two backticks (backtick-in-delims is safe — cmd treats it as any other char).
if /I not "!SIGN_ONLY!"=="true" if not defined PACKAGE if defined APP (
    if exist "!SCRIPT_DIR!\apps\!APP!\README.md" (
        for /f "usebackq tokens=2 delims=`" %%L in (`findstr /B /C:"- **Package:** " "!SCRIPT_DIR!\apps\!APP!\README.md" 2^>nul`) do (
            if not defined PACKAGE set "PACKAGE=%%L"
        )
        if defined PACKAGE echo [+] Package ^(from apps\!APP!\README.md^): !PACKAGE!
    )
)

rem === Build list-patches filter flags =================================
set "LIST_FLAGS="
if /I not "!NO_FILTER!"=="true" if defined PACKAGE (
    set "LIST_FLAGS=--filter-package-name=!PACKAGE!"
    if /I not "!INCLUDE_UNIVERSAL!"=="true" (
        set "LIST_FLAGS=!LIST_FLAGS! --universal-patches=false"
    )
)

rem === Discover + select patches (skipped in --sign-only) ==============
set /a _nc=0
set "CLI_PATCH_ARGS="
if /I not "!SIGN_ONLY!"=="true" (
    echo [+] Discovering patches...
    rem Use revanced-cli's dedicated list-patches subcommand — in patcher 22+ the
    rem old "dry-run against the jar itself" trick crashes inside ResourcesDecoder
    rem before any patches load. list-patches prints one "Name: <patch>" per patch.
    "!JAVA!" -jar "!REVANCED_CLI!" list-patches -p "!PATCHES_JAR!" -b !LIST_FLAGS! > "!TMP_DIR!\cli.txt" 2>&1

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

    rem Announce patch count via a subroutine so the three-way branch
    rem (unfiltered / filtered-incl-universal / filtered-excl-universal)
    rem doesn't have to nest if/else inside this already-compound block.
    call :announce_patch_count

    if /I not "!NO_UI!"=="true" (
        call :selector
        if errorlevel 1 goto fail
    )

    echo.
    echo [+] Patch configuration:
    for /l %%i in (1,1,!_nc!) do call :print_state %%i
    echo.

    rem Each enabled patch is passed as: -e "Name". --exclusive is always set.
    set "CLI_PATCH_ARGS=--exclusive"
    for /l %%i in (1,1,!_nc!) do call :append_flag %%i

    rem Maps API key injection piggybacks on the resource patch's stringOption.
    rem Without it, tiles never render on sideloaded builds — Google locks the
    rem bundled key to Meetup's production cert fingerprint.
    if defined MAPS_KEY (
        if not "!MAPS_KEY!"=="" (
            set "CLI_PATCH_ARGS=!CLI_PATCH_ARGS! -O "mapsKey=!MAPS_KEY!""
            echo [+] Maps API key: will be injected via the 'Inject Google Maps API key' patch
        )
    )
    if not defined MAPS_KEY (
        echo [^^!] No Maps API key supplied. Pass --maps-key ^<KEY^> or set MAPS_API_KEY=... or Maps will render blank.
        echo [^^!] Sideloading re-signs the APK with our keystore; Meetup's bundled key is locked to their production cert.
    ) else if "!MAPS_KEY!"=="" (
        echo [^^!] No Maps API key supplied. Pass --maps-key ^<KEY^> or set MAPS_API_KEY=... or Maps will render blank.
    )
)

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

rem === Patch (skipped in --sign-only) =================================
set "PATCHED_APK=!WORK_DIR!\patched-base.apk"
if /I "!SIGN_ONLY!"=="true" (
    copy /y "!BASE_APK!" "!PATCHED_APK!" >nul
    for %%F in ("!BASE_APK!") do echo [+] Sign-only: copied %%~nxF unchanged
) else (
    for %%F in ("!BASE_APK!") do echo [+] Patching %%~nxF...

    "!JAVA!" -jar "!REVANCED_CLI!" patch -p "!PATCHES_JAR!" -b -o "!PATCHED_APK!" --force !CLI_PATCH_ARGS! "!BASE_APK!"

    if not exist "!PATCHED_APK!" (
        echo [-] Patched APK not produced. 1>&2
        goto fail
    )
    echo [+] Patching complete
)

rem === Persistent signing keystore =====================================
rem Lives under %USERPROFILE% so the cert fingerprint stays stable across
rem patched builds: lets the user register the fingerprint against their own
rem Google Maps API key once, and also lets future patched installs upgrade
rem in-place instead of requiring an uninstall.
if defined APK_PATCH_KIT_HOME (
    set "KEYSTORE_DIR=!APK_PATCH_KIT_HOME!"
) else (
    set "KEYSTORE_DIR=%USERPROFILE%\.apk-patch-kit"
)
set "KEYSTORE=!KEYSTORE_DIR!\keystore.p12"
set "KS_PASS=revanced"
set "KS_ALIAS=key"

if not exist "!KEYSTORE_DIR!" mkdir "!KEYSTORE_DIR!"
if not exist "!KEYSTORE!" (
    echo [+] Generating persistent signing keystore at !KEYSTORE! ...
    "!KEYTOOL!" -genkeypair -keystore "!KEYSTORE!" -storetype PKCS12 -storepass !KS_PASS! -keypass !KS_PASS! -alias !KS_ALIAS! -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=ReVanced" >nul 2>&1
) else (
    echo [+] Using existing keystore: !KEYSTORE!
)

rem Emit SHA-1 fingerprint — users need this to register our cert against
rem Google Cloud restrictions on their own Maps API key. Stage the keytool
rem output to a temp file rather than piping inside `for /f`: the latter
rem requires nested-quote gymnastics around a !KEYTOOL! path with spaces
rem that cmd's parser mishandles ("The syntax of the command is incorrect").
set "KS_SHA1="
"!KEYTOOL!" -list -v -keystore "!KEYSTORE!" -storetype PKCS12 -storepass !KS_PASS! -alias !KS_ALIAS! > "!TMP_DIR!\ks.txt" 2>nul
for /f "tokens=2 delims=: " %%A in ('findstr /R /C:"SHA1:" "!TMP_DIR!\ks.txt"') do (
    if not defined KS_SHA1 set "KS_SHA1=%%A"
)
if defined KS_SHA1 (
    echo     Keystore cert SHA-1: !KS_SHA1!
    echo     Register this fingerprint against your Google Cloud Maps API key ^(restriction: Android apps -^> com.^<pkg^> + this SHA-1^).
)

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
    rem Print the install command as separate lines rather than chained with
    rem `&` / `2>nul` — those are cmd-only and PowerShell rejects `&` outright
    rem ("AmpersandNotAllowed"). Separate adb invocations work in cmd,
    rem PowerShell, and bash without modification.
    rem
    rem Neither cmd nor PowerShell expands globs inside quoted native-command
    rem args, so enumerate each split explicitly.
    rem .apks filename is the package name (add-app.bat writes it that way).
    set "PKG_NAME=!APK_BASENAME!"
    set "INSTALL_TAIL=adb install-multiple -r -d"
    for %%A in ("!WORK_DIR!\patched-splits\*.apk") do set INSTALL_TAIL=!INSTALL_TAIL! "%%~fA"
    echo [+] First install ^(uninstall handles cert-mismatch against the Play Store build; ignore "not installed" if there's no prior copy^):
    echo     adb uninstall !PKG_NAME!
    echo     !INSTALL_TAIL!
    echo.
    echo [+] Subsequent updates ^(same keystore -^> same signature -^> in-place upgrade keeps app data^):
    echo     !INSTALL_TAIL!

    if /I "!INSTALL!"=="true" (
        call :locate_adb
        if not defined ADB (
            echo [-] --install requested but adb not found. Pass --adb ^<path^>. 1>&2
            goto fail
        )
        echo.
        echo [+] Auto-install via !ADB!
        if /I "!REINSTALL!"=="true" (
            echo [+]   Uninstalling !PKG_NAME! ^(data will be wiped^) ...
            "!ADB!" uninstall !PKG_NAME!
        )
        echo [+]   Installing splits ...
        rem Re-enumerate split paths so install-multiple gets each as a quoted arg.
        set "ADB_INSTALL_ARGS="
        for %%A in ("!WORK_DIR!\patched-splits\*.apk") do set ADB_INSTALL_ARGS=!ADB_INSTALL_ARGS! "%%~fA"
        "!ADB!" install-multiple -r -d!ADB_INSTALL_ARGS!
        if errorlevel 1 (
            echo [-]   install-multiple failed. 1>&2
            if /I not "!REINSTALL!"=="true" (
                echo [-]   If the failure was INSTALL_FAILED_UPDATE_INCOMPATIBLE / signature mismatch, 1>&2
                echo [-]   re-run with --reinstall ^(wipes app data^) to replace the existing differently-signed copy. 1>&2
            )
            goto fail
        )
        echo [+]   Installed.
    )
) else (
    for %%F in ("!APK_FILE!") do set "APK_BASENAME=%%~nF"
    set "OUTPUT_APK=!SCRIPT_DIR!\build\!APK_BASENAME!-patched.apk"
    if not exist "!SCRIPT_DIR!\build" mkdir "!SCRIPT_DIR!\build"

    copy /y "!PATCHED_APK!" "!OUTPUT_APK!" >nul
    if defined APKSIGNER (
        call "!APKSIGNER!" sign --ks "!KEYSTORE!" --ks-pass "pass:!KS_PASS!" --ks-key-alias !KS_ALIAS! --key-pass "pass:!KS_PASS!" "!OUTPUT_APK!" 2>nul
    ) else (
        echo [^^!] apksigner not found - output APK is unsigned. Install with Android build-tools.
    )

    echo [+] Output: !OUTPUT_APK!
    echo.
    echo [+] Install with ^(-r/-d allow reinstall and downgrade; run 'adb uninstall ^<pkg^>' first if the device has a differently-signed copy^):
    echo     adb install -r -d "!OUTPUT_APK!"

    if /I "!INSTALL!"=="true" (
        call :locate_adb
        if not defined ADB (
            echo [-] --install requested but adb not found. Pass --adb ^<path^>. 1>&2
            goto fail
        )
        echo.
        echo [+] Auto-install via !ADB!
        rem Single-APK path: package name only known when --app/--package was used.
        if /I "!REINSTALL!"=="true" (
            if defined PACKAGE (
                echo [+]   Uninstalling !PACKAGE! ^(data will be wiped^) ...
                "!ADB!" uninstall !PACKAGE!
            ) else (
                echo [^^!]   --reinstall set but no package name known ^(use --app or --package to enable uninstall^).
            )
        )
        echo [+]   Installing !APK_BASENAME!-patched.apk ...
        "!ADB!" install -r -d "!OUTPUT_APK!"
        if errorlevel 1 (
            echo [-]   install failed. 1>&2
            if /I not "!REINSTALL!"=="true" (
                echo [-]   If the failure was INSTALL_FAILED_UPDATE_INCOMPATIBLE / signature mismatch, 1>&2
                echo [-]   re-run with --reinstall ^(wipes app data^) to replace the existing differently-signed copy. 1>&2
            )
            goto fail
        )
        echo [+]   Installed.
    )
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
:locate_adb
rem Resolve adb.exe — preference order: --adb override, PATH, chocolatey,
rem common Android SDK install dirs. Sets ADB; leaves it empty on miss.
set "ADB="
if defined ADB_OVERRIDE (
    set "ADB=!ADB_OVERRIDE!"
    exit /b 0
)
for /f "delims=" %%A in ('where adb.exe 2^>nul') do if not defined ADB set "ADB=%%A"
if not defined ADB for /f "delims=" %%A in ('where adb 2^>nul') do if not defined ADB set "ADB=%%A"
if not defined ADB if exist "C:\ProgramData\chocolatey\bin\adb.exe" set "ADB=C:\ProgramData\chocolatey\bin\adb.exe"
if not defined ADB (
    set "_ADB_ROOTS=%ANDROID_HOME%;%ANDROID_SDK_ROOT%;%LOCALAPPDATA%\Android\Sdk;%ProgramFiles%\Android\Sdk;%ProgramFiles(x86)%\Android\Sdk"
    for %%R in ("!_ADB_ROOTS:;=" "!") do (
        if not defined ADB if exist "%%~R\platform-tools\adb.exe" set "ADB=%%~R\platform-tools\adb.exe"
    )
)
exit /b 0

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

:announce_patch_count
rem Emit the right "Found N patch(es)..." line for the current filter state.
rem Three cases: unfiltered, filtered-incl-universal, filtered-excl-universal.
rem The last case also queries list-patches a second time with a non-existent
rem package to count the universal patches we're hiding, so we can nudge the
rem user to --include-universal if they want them.
if /I "!NO_FILTER!"=="true" goto :ann_unfiltered
if not defined PACKAGE      goto :ann_unfiltered
if /I "!INCLUDE_UNIVERSAL!"=="true" (
    echo [+] Found !_nc! patch^(es^) for !PACKAGE! ^(including universal^)
    exit /b 0
)
set /a _uc=0
"!JAVA!" -jar "!REVANCED_CLI!" list-patches -p "!PATCHES_JAR!" -b --filter-package-name=__nonexistent__ > "!TMP_DIR!\univ.txt" 2>&1
for /f "usebackq tokens=1 delims=:" %%U in ("!TMP_DIR!\univ.txt") do (
    if /I "%%U"=="Name" set /a _uc+=1
)
echo [+] Found !_nc! patch^(es^) for !PACKAGE! ^(!_uc! universal patches hidden -- pass --include-universal to see them^)
exit /b 0

:ann_unfiltered
echo [+] Found !_nc! patch^(es^) ^(unfiltered -- pass --package ^<pkg^> or use --app to scope^)
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
