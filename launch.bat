@echo off
setlocal EnableExtensions
title BushScript Launcher
color 0B

set "APPDIR=%USERPROFILE%\Documents\BushScript"
set "PKGDIR=%APPDIR%\bushscript"
set "SOURCE=%PKGDIR%\Bushscript.java"
set "JAVAFILE=%APPDIR%\javapath.txt"

if not exist "%PKGDIR%" mkdir "%PKGDIR%"
if not exist "%PKGDIR%" (
    cls
    call :banner
    echo   ERROR: Cannot create the BushScript folder.
    echo.
    pause
    exit /b 1
)
if exist "%JAVAFILE%" del "%JAVAFILE%" >nul 2>&1

cls
call :banner
echo   Getting things ready. First-time setup can take
echo   several minutes. Please keep this window open.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
 "function Say($t,$col) {Write-Host $t -ForegroundColor $col};" ^
 "$app=$env:USERPROFILE+'\Documents\BushScript';" ^
 "$pkg=Join-Path $app 'bushscript';" ^
 "$src=Join-Path $pkg 'Bushscript.java';" ^
 "$vf=Join-Path $app 'version.txt';" ^
 "$jf=Join-Path $app 'javapath.txt';" ^
 "$origPath=$env:Path;" ^
 "function Find-Java {" ^
 "  $env:Path=$origPath+';'+[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User');" ^
 "  $c=Get-Command java.exe -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
 "  if ($c) {return $c.Source};" ^
 "  $f=Get-ChildItem -Path (Join-Path $env:ProgramFiles 'Amazon Corretto\*\bin') -Filter java.exe -ErrorAction SilentlyContinue | Select-Object -First 1;" ^
 "  if ($f) {return $f.FullName}" ^
 "};" ^
 "Say '  [1/3] Checking for Java' 'Cyan';" ^
 "$java=Find-Java;" ^
 "if (!$java) {" ^
 "  Say '        Java not found. Checking Software Center...' 'Yellow';" ^
 "  $a=Get-CimInstance -Namespace root\ccm\ClientSDK -ClassName CCM_Application -ErrorAction SilentlyContinue | Where-Object {$_.Name -like 'Amazon Corretto*'} | Select-Object -First 1;" ^
 "  if ($a -and $a.InstallState -ne 'Installed') {" ^
 "    try {" ^
 "      Invoke-CimMethod -InputObject $a -MethodName Install -Arguments @{Id=$a.Id;Revision=$a.Revision;IsMachineTarget=[bool]$a.IsMachineTarget;EnforcePreference=[uint32]0;Priority='Normal';IsRebootIfNeeded=$false} | Out-Null;" ^
 "      Say '        Java installation requested.' 'Yellow';" ^
 "    } catch { Say '        Automatic request failed. Please install Java from Software Center.' 'Yellow' }" ^
 "  }" ^
 "  $sc=$env:WINDIR+'\CCM\ClientUX\SCClient.exe';" ^
 "  if (!$a -and (Test-Path $sc)) {Start-Process $sc}" ^
 "  $t0=Get-Date; $limit=$t0.AddMinutes(20);" ^
 "  while (!$java -and (Get-Date) -lt $limit) {" ^
 "    $el=[int]((Get-Date)-$t0).TotalSeconds;" ^
 "    Write-Host ([string][char]13+'        Waiting for Java to install... '+$el+'s   ') -NoNewline -ForegroundColor Yellow;" ^
 "    Start-Sleep -Seconds 5;" ^
 "    $java=Find-Java;" ^
 "  }" ^
 "  Write-Host '';" ^
 "  if (!$java) {Say '        Java is still unavailable. Finish installing it in Software Center, then rerun BushScript.' 'Red'; exit 2}" ^
 "}" ^
 "$major=0; $o='';" ^
 "try { $o=& $java --version | Select-Object -First 1; if ($o -match '(\d+)') {$major=[int]$Matches[1]} } catch {};" ^
 "if ($major -lt 16) {Say ('        BushScript needs Java 16 or newer. Found: '+$java) 'Red'; exit 4};" ^
 "Say ('        '+$o+'  OK') 'Green';" ^
 "Say '  [2/3] Checking for updates' 'Cyan';" ^
 "try {" ^
 "  $v=(Invoke-WebRequest -Uri 'https://bush.downingtownstem.org/script/version.txt' -UseBasicParsing -TimeoutSec 20).Content.Trim();" ^
 "  if (!$v -or $v -match '[\r\n]' -or $v.Length -gt 100) {throw 'Invalid version file'};" ^
 "  $old=''; if (Test-Path $vf) {$old=(Get-Content $vf -Raw).Trim()};" ^
 "  if (!(Test-Path $src) -or $v -ne $old) {" ^
 "    Say ('        Downloading version '+$v+'...') 'Yellow';" ^
 "    $tmp=$src+'.download';" ^
 "    Invoke-WebRequest -Uri 'https://bush.downingtownstem.org/script/Bushscript.java' -OutFile $tmp -UseBasicParsing -TimeoutSec 45;" ^
 "    $text=Get-Content $tmp -Raw;" ^
 "    if ($text -notmatch '(?m)^\s*package\s+bushscript\s*;') {Remove-Item $tmp -Force; throw 'Downloaded file has an unexpected package declaration'};" ^
 "    Move-Item $tmp $src -Force;" ^
 "    Set-Content -Path $vf -Value $v -NoNewline;" ^
 "    Say '        Update installed.  OK' 'Green'" ^
 "  } else {Say ('        Up to date (version '+$v+')  OK') 'Green'}" ^
 "} catch {" ^
 "  Say ('        Update check failed: '+$_.Exception.Message) 'Yellow';" ^
 "  if (!(Test-Path $src)) {exit 3};" ^
 "  Say '        Using the existing local copy.' 'Yellow'" ^
 "};" ^
 "Say '  [3/3] Starting BushScript' 'Cyan';" ^
 "Set-Content -Path $jf -Value $java -NoNewline -Encoding OEM"

if errorlevel 1 (
    echo.
    echo   ------------------------------------------
    echo   Setup failed. Please check the messages above.
    echo   ------------------------------------------
    echo.
    pause
    exit /b 1
)

set "JAVA="
if exist "%JAVAFILE%" set /p JAVA=<"%JAVAFILE%"
if not defined JAVA set "JAVA=java"

timeout /t 1 /nobreak >nul 2>&1
cls
title BushScript - Running
call :banner
echo   Status:  RUNNING
echo   Keep this window open while you browse.
echo   Close the browser to stop BushScript.
echo.
echo   ------------------------------------------
echo.

pushd "%APPDIR%"
"%JAVA%" "%SOURCE%"
set "RESULT=%ERRORLEVEL%"
popd

rem Ctrl+C is a normal way to stop BushScript, not an error.
if "%RESULT%"=="130" set "RESULT=0"
if "%RESULT%"=="-1073741510" set "RESULT=0"

if not "%RESULT%"=="0" (
    echo.
    echo   ------------------------------------------
    echo   BushScript stopped unexpectedly ^(code %RESULT%^).
    echo   ------------------------------------------
    echo.
    pause
) else (
    echo.
    echo   BushScript closed. Goodbye!
    timeout /t 2 /nobreak >nul 2>&1
)

endlocal & exit /b %RESULT%

:banner
echo.
echo   +------------------------------------------+
echo   ^|                                          ^|
echo   ^|            B U S H S C R I P T           ^|
echo   ^|      Local browser with ad blocking      ^|
echo   ^|                                          ^|
echo   +------------------------------------------+
echo.
exit /b 0
