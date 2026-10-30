@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Remove-Certificates-All.cmd -- Restricted Russian CA
rem No retry loop; every certutil nonzero return code is an error.
rem /check is read-only. No PowerShell, .cer files or private keys required.
rem Targets: all matching versions, INCLUDING the official Russian root.
rem Scope: LocalMachine and the executing account's CurrentUser, Root and CA.
rem Other user accounts and explicit Group Policy stores are not processed.

set "ERRORLEVEL="
set "MODE=remove"
if /I "%~1"=="/check" set "MODE=check"
if /I "%~1"=="/?" goto Help
if /I "%~1"=="/help" goto Help
if not "%~2"=="" goto BadArguments
if not "%~1"=="" if /I not "%~1"=="/check" goto BadArguments

set "CERTUTIL=%SystemRoot%\System32\certutil.exe"
set "FINDSTR=%SystemRoot%\System32\findstr.exe"
if not exist "%CERTUTIL%" (
    echo ERROR: certutil.exe is not available.
    exit /b 1
)
if not exist "%FINDSTR%" (
    echo ERROR: findstr.exe is not available.
    exit /b 1
)

if /I "%MODE%"=="check" goto Prepare
"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if not "%errorlevel%"=="0" (
    echo ERROR: Open CMD as Administrator and run this file again.
    exit /b 1
)

echo ===============================================================
echo DELETE all matching versions of:
echo   Restricted Russian CA
echo   Russian Trusted Root CA, including ORIGINAL and cross-signed
echo   Russian Trusted Sub CA, including the 2024 version
echo Stores: LocalMachine and CurrentUser; Root and CA.
echo This may stop other applications from trusting this PKI.
echo ===============================================================
"%SystemRoot%\System32\choice.exe" /C YN /N /M "Continue? [Y/N]: "
if not "%errorlevel%"=="1" exit /b 2

:Prepare
if not defined TEMP (
    echo ERROR: TEMP is not set.
    exit /b 1
)
set "WORK=%TEMP%\ru-ca-cleanup-%RANDOM%-%RANDOM%"
if exist "%WORK%" (
    echo ERROR: Log directory already exists. Run the script again.
    exit /b 1
)
md "%WORK%"
if not "%errorlevel%"=="0" (
    echo ERROR: Cannot create log directory.
    exit /b 1
)
echo.
echo Mode: %MODE%
echo Logs: "%WORK%"
set "FAILED=0"

call :ProcessStore machine Root
if not "%errorlevel%"=="0" set "FAILED=1"
call :ProcessStore machine CA
if not "%errorlevel%"=="0" set "FAILED=1"
call :ProcessStore user Root
if not "%errorlevel%"=="0" set "FAILED=1"
call :ProcessStore user CA
if not "%errorlevel%"=="0" set "FAILED=1"

echo.
if "%FAILED%"=="0" (
    echo OK: No target names found in the four inspected store listings.
) else (
    echo WARNING: Matches remain or a command failed. Review the logs.
    echo Do not interpret this result as successful cleanup.
)
echo Group Policy or device management may reinstall managed certificates.
echo Logs: "%WORK%"
exit /b %FAILED%

:ProcessStore
setlocal
set "SCOPE=%~1"
set "STORE=%~2"
set "SCOPEARG="
if /I "%SCOPE%"=="user" set "SCOPEARG=-user"
set "STORE_FAILED=0"
set "SNAPSHOT=%WORK%\%SCOPE%-%STORE%-before.txt"
echo.
echo === %SCOPE%\%STORE% ===

rem Enumerate the WHOLE store: do not infer presence from a name query RC.
"%CERTUTIL%" %SCOPEARG% -store "%STORE%" >"%SNAPSHOT%" 2>&1
set "READ_RC=%errorlevel%"
if not "%READ_RC%"=="0" goto StoreReadError

if /I "%MODE%"=="check" goto VerifyStore
call :DeleteName "Restricted Russian CA"
if not "%errorlevel%"=="0" set "STORE_FAILED=1"
call :DeleteName "Russian Trusted Root CA"
if not "%errorlevel%"=="0" set "STORE_FAILED=1"
call :DeleteName "Russian Trusted Sub CA"
if not "%errorlevel%"=="0" set "STORE_FAILED=1"

set "SNAPSHOT=%WORK%\%SCOPE%-%STORE%-after.txt"
"%CERTUTIL%" %SCOPEARG% -store "%STORE%" >"%SNAPSHOT%" 2>&1
set "READ_RC=%errorlevel%"
if not "%READ_RC%"=="0" goto StoreReadError

:VerifyStore
rem ASCII names are unchanged in Russian/English certutil output.
rem This conservative check also notices target names in issuer fields.
"%FINDSTR%" /I /L /C:"Restricted Russian CA" /C:"Russian Trusted Root CA" /C:"Russian Trusted Sub CA" "%SNAPSHOT%" >nul
set "MATCH_RC=%errorlevel%"
if "%MATCH_RC%"=="1" (
    echo [OK] No target names in %SCOPE%\%STORE%.
    endlocal & exit /b %STORE_FAILED%
)
if "%MATCH_RC%"=="0" (
    echo [FOUND] Target names still occur in %SCOPE%\%STORE%.
    echo Inspect: "%SNAPSHOT%"
    endlocal & exit /b 1
)
echo ERROR: Could not search the store listing. findstr returned %MATCH_RC%.
endlocal & exit /b 1

:StoreReadError
echo ERROR: Cannot enumerate %SCOPE%\%STORE%. certutil returned %READ_RC%.
type "%SNAPSHOT%"
endlocal & exit /b 1

:DeleteName
setlocal
set "CERTNAME=%~1"
"%FINDSTR%" /I /L /C:"%CERTNAME%" "%SNAPSHOT%" >nul
set "MATCH_RC=%errorlevel%"
if "%MATCH_RC%"=="1" (
    echo [SKIP] %CERTNAME%: no name match in the store listing.
    endlocal & exit /b 0
)
if not "%MATCH_RC%"=="0" (
    echo ERROR: Cannot search the store listing for %CERTNAME%.
    endlocal & exit /b 1
)

echo [DELETE] %CERTNAME%
set "DELETE_LOG=%WORK%\%SCOPE%-%STORE%-delete-%CERTNAME%.txt"
rem One delstore call per name/store. No retry based on the exit code.
"%CERTUTIL%" -f -silent %SCOPEARG% -delstore "%STORE%" "%CERTNAME%" >"%DELETE_LOG%" 2>&1
set "DELETE_RC=%errorlevel%"
type "%DELETE_LOG%"
if not "%DELETE_RC%"=="0" (
    echo ERROR: certutil returned %DELETE_RC% for %CERTNAME%.
    endlocal & exit /b 1
)
endlocal & exit /b 0

:BadArguments
echo ERROR: Unknown arguments.
echo Usage: %~nx0 [/check]
exit /b 2

:Help
echo Usage: %~nx0 [/check]
echo.
echo No arguments: request confirmation, then remove matches as Administrator.
echo /check: read-only scan. Does not install or remove certificates.
echo Exit 0: no target names in the inspected stores; no command errors.
echo Exit 1: matches remain, a store could not be read, or another error.
echo Exit 2: cancelled or invalid arguments.
echo CurrentUser is the account running this script, not every Windows user.
exit /b 0
