@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Install ONLY the four newly exported certificates into LocalMachine stores.
rem No removal, no private-key import, no handling of a previous CA name.
set "ERRORLEVEL="
set "CERTUTIL=%SystemRoot%\System32\certutil.exe"
set "CERTDIR=%~dp0"
if not "%~1"=="" set "CERTDIR=%~f1\"
if not "%~2"=="" (
    echo Usage: %~nx0 [certificate-directory]
    exit /b 2
)
if not exist "%CERTUTIL%" (
    echo ERROR: certutil.exe not found.
    exit /b 1
)
"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if not "%errorlevel%"=="0" (
    echo ERROR: Run CMD as Administrator.
    exit /b 1
)

rem Validate availability / readability of ALL four files before importing any.
call :CheckFile "Restricted-Russian-CA.cer"
if not "%errorlevel%"=="0" exit /b 1
call :CheckFile "Russian-Trusted-Root-cross-signed.cer"
if not "%errorlevel%"=="0" exit /b 1
call :CheckFile "Russian-Trusted-Sub-CA.cer"
if not "%errorlevel%"=="0" exit /b 1
call :CheckFile "Russian-Trusted-Sub-CA-2024.cer"
if not "%errorlevel%"=="0" exit /b 1

echo Certificate directory: "%CERTDIR%"
echo Only Restricted Russian CA will be installed in Root.
echo The cross-signed Russian root and both Sub CAs will be installed in CA.
call :Install CA "Russian-Trusted-Root-cross-signed.cer"
if not "%errorlevel%"=="0" exit /b 1
call :Install CA "Russian-Trusted-Sub-CA.cer"
if not "%errorlevel%"=="0" exit /b 1
call :Install CA "Russian-Trusted-Sub-CA-2024.cer"
if not "%errorlevel%"=="0" exit /b 1
call :Install Root "Restricted-Russian-CA.cer"
if not "%errorlevel%"=="0" exit /b 1

echo.
echo OK: all four certutil import commands succeeded.
echo This does not verify TLS nameConstraints. Test allowed and disallowed sites.
echo Check: certutil -store Root "Restricted Russian CA"
echo        certutil -store CA "Russian Trusted Root CA"
echo        certutil -store CA "Russian Trusted Sub CA"
exit /b 0

:CheckFile
if not exist "%CERTDIR%%~1" (
    echo ERROR: Missing "%CERTDIR%%~1"
    exit /b 1
)
"%CERTUTIL%" -dump "%CERTDIR%%~1" >nul 2>&1
if not "%errorlevel%"=="0" (
    echo ERROR: Cannot read "%CERTDIR%%~1" as a certificate.
    exit /b 1
)
exit /b 0

:Install
echo.
echo [IMPORT] LocalMachine\%~1 : %~2
"%CERTUTIL%" -addstore -f "%~1" "%CERTDIR%%~2"
set "IMPORT_RC=%errorlevel%"
if not "%IMPORT_RC%"=="0" (
    echo ERROR: certutil returned %IMPORT_RC%. Import stopped; no rollback was performed.
    exit /b 1
)
exit /b 0
