@echo off
setlocal EnableExtensions
title BushScript Launcher
color 0B

set "APPDIR=%USERPROFILE%\Documents\BushScript"
set "PKGDIR=%APPDIR%\bushscript"
set "SOURCE=%PKGDIR%\Bushscript.java"
set "CLASSDIR=%APPDIR%\classes"
set "JAVAFILE=%APPDIR%\javapath.txt"
set "SELF=%~f0"
set "LAUNCHER=%APPDIR%\BushScript.bat"
set "MODE=%~1"

rem Run with no window at all by default (headless console). The very first run, or any run that
rem still needs setup, stays visible so progress and errors can be seen.
if /i "%MODE%"=="--hidden" goto :main
if /i "%MODE%"=="--visible" goto :main
set "READY=1"
if not exist "%JAVAFILE%" set "READY="
if not exist "%SOURCE%" set "READY="
if defined READY if exist "%WINDIR%\System32\conhost.exe" start "" "%WINDIR%\System32\conhost.exe" --headless cmd /c ""%~f0" --hidden"
if defined READY if not exist "%WINDIR%\System32\conhost.exe" start "BushScript" /min cmd /c ""%~f0" --hidden"
if not defined READY start "BushScript" cmd /c ""%~f0" --visible"
exit /b 0

:main
if not exist "%PKGDIR%" mkdir "%PKGDIR%"
if not exist "%PKGDIR%" (
    cls
    call :banner
    echo   ERROR: Cannot create the BushScript folder.
    echo.
    pause
    exit /b 1
)

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
 "$cls=Join-Path $app 'classes';" ^
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
 "$cached=''; if (Test-Path $jf) {$tx=Get-Content $jf -Raw -Encoding OEM; if ($tx) {$cached=$tx.Trim()}};" ^
 "if ($cached -ne $java) {" ^
 "  $major=0; $o='';" ^
 "  try { $o=& $java --version | Select-Object -First 1; if ($o -match '(\d+)') {$major=[int]$Matches[1]} } catch {};" ^
 "  if ($major -lt 16) {Say ('        BushScript needs Java 16 or newer. Found: '+$java) 'Red'; exit 4};" ^
 "  Set-Content -Path $jf -Value $java -NoNewline -Encoding OEM;" ^
 "  Say ('        '+$o+'  OK') 'Green'" ^
 "} else {Say '        Java ready  OK' 'Green'};" ^
 "Say '  [2/3] Checking for updates' 'Cyan';" ^
 "try {" ^
 "  $v=(Invoke-WebRequest -Uri 'https://pull.bush.downingtownstem.org/script/version.txt' -UseBasicParsing -TimeoutSec 5).Content.Trim();" ^
 "  if (!$v -or $v -match '[\r\n]' -or $v.Length -gt 100) {throw 'Invalid version file'};" ^
 "  $old=''; if (Test-Path $vf) {$old=(Get-Content $vf -Raw).Trim()};" ^
 "  if (!(Test-Path $src) -or $v -ne $old) {" ^
 "    Say ('        Downloading version '+$v+'...') 'Yellow';" ^
 "    $tmp=$src+'.download';" ^
 "    Invoke-WebRequest -Uri 'https://pull.bush.downingtownstem.org/script/Bushscript.java' -OutFile $tmp -UseBasicParsing -TimeoutSec 45;" ^
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
 "$cf=Join-Path $cls 'bushscript\Bushscript.class';" ^
 "if (!(Test-Path $cf) -or (Get-Item $cf).LastWriteTime -lt (Get-Item $src).LastWriteTime) {" ^
 "  if (Test-Path $cls) {Remove-Item $cls -Recurse -Force};" ^
 "  $javac=Join-Path (Split-Path $java) 'javac.exe';" ^
 "  if (Test-Path $javac) {" ^
 "    Say '        Preparing BushScript (only needed after an update)...' 'Yellow';" ^
 "    & $javac -encoding UTF-8 -d $cls $src;" ^
 "    if ($LASTEXITCODE -ne 0 -and (Test-Path $cls)) {Remove-Item $cls -Recurse -Force}" ^
 "  }" ^
 "};" ^
 "exit 0"

if errorlevel 1 goto :setupfailed

set "JAVA="
if exist "%JAVAFILE%" set /p JAVA=<"%JAVAFILE%"
if not defined JAVA set "JAVA=java"
set "JVMFLAGS=-XX:TieredStopAtLevel=1 -XX:+UseSerialGC"

rem One-time: keep a copy of this launcher in the app folder and add Desktop / Start menu shortcuts.
if /i not "%SELF%"=="%LAUNCHER%" copy /y "%SELF%" "%LAUNCHER%" >nul 2>&1
if exist "%LAUNCHER%" if not exist "%APPDIR%\shortcut3.done" call :makeshortcut

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
if exist "%CLASSDIR%\bushscript\Bushscript.class" (
    "%JAVA%" %JVMFLAGS% -cp "%CLASSDIR%" bushscript.Bushscript
) else (
    "%JAVA%" %JVMFLAGS% "%SOURCE%"
)
set "RESULT=%ERRORLEVEL%"
popd

rem Ctrl+C is a normal way to stop BushScript, not an error.
if "%RESULT%"=="130" set "RESULT=0"
if "%RESULT%"=="-1073741510" set "RESULT=0"

if "%RESULT%"=="0" goto :closed
if /i "%MODE%"=="--hidden" goto :showvisible
echo.
echo   ------------------------------------------
echo   BushScript stopped unexpectedly ^(code %RESULT%^).
echo   ------------------------------------------
echo.
pause
endlocal & exit /b %RESULT%

:closed
echo.
echo   BushScript closed. Goodbye!
if /i not "%MODE%"=="--hidden" timeout /t 2 /nobreak >nul 2>&1
endlocal & exit /b 0

:setupfailed
if /i "%MODE%"=="--hidden" goto :showvisible
echo.
echo   ------------------------------------------
echo   Setup failed. Please check the messages above.
echo   ------------------------------------------
echo.
pause
exit /b 1

:showvisible
rem A minimized run hit a problem: reopen it visibly so the message can be read.
start "BushScript" cmd /c ""%~f0" --visible"
exit /b 1

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

:makeshortcut
echo   Creating the BushScript shortcut...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "$app=$env:APPDIR; $ico=Join-Path $app 'bush.ico'; $q=[string][char]34;" ^
 "$l=@(Get-Content -LiteralPath $env:SELF);" ^
 "$s=[array]::IndexOf($l,'::BUSHICON-BEGIN')+1; $e=[array]::IndexOf($l,'::BUSHICON-END');" ^
 "if ($s -le 0 -or $e -le $s) {exit 1};" ^
 "$b64=(($l[$s..($e-1)] | ForEach-Object {$_.Substring(2)}) -join '');" ^
 "[IO.File]::WriteAllBytes($ico,[Convert]::FromBase64String($b64));" ^
 "$ws=New-Object -ComObject WScript.Shell; $ok=$false;" ^
 "foreach ($dir in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))) {" ^
 "  try {" ^
 "    $lnk=$ws.CreateShortcut((Join-Path $dir 'BushScript.lnk'));" ^
 "    $lnk.TargetPath=Join-Path $env:WINDIR 'System32\conhost.exe';" ^
 "    $lnk.Arguments='--headless cmd /c '+$q+$q+$env:LAUNCHER+$q+$q;" ^
 "    $lnk.WorkingDirectory=$app;" ^
 "    $lnk.WindowStyle=7;" ^
 "    $lnk.IconLocation=$ico+',0';" ^
 "    $lnk.Description='BushScript - Bush Local Browser';" ^
 "    $lnk.Save(); $ok=$true" ^
 "  } catch {}" ^
 "};" ^
 "if ($ok) {Set-Content -Path (Join-Path $app 'shortcut3.done') -Value 1}" >nul 2>&1
if exist "%APPDIR%\shortcut3.done" (
    echo   BushScript was added to your Desktop and Start menu.
    if /i not "%MODE%"=="--hidden" timeout /t 3 /nobreak >nul 2>&1
)
exit /b 0

::BUSHICON-BEGIN
::AAABAAQAAAAAAAEAIACnLwAARgAAADAwAAABACAAOBAAAO0vAAAgIAAAAQAgAI4IAAAlQAAAEBAA
::AAEAIAAHAwAAs0gAAIlQTkcNChoKAAAADUlIRFIAAAEAAAABAAgDAAAAa6xYVAAAAwBQTFRFAAAA
::M3gQb7tH70gjAwUC/b4QcsFJBhYFruaTDyYKTXqxT5cqa7o9RHUpvOXr/MEQFTYMOmgmO3QjuuWm
::xefuichpOoQWldZ0WqUzMmkWNVgnJkcYqtqRLFcZw+awQ2ot70gd+sUubKlMBAMFBAQFt9inMkcr
::N7N5BAMFBAMFBAMFSokqLgYD51IvQokbBAMEKjkoY6o7p8iYzEowUmdLtEUtgsVcGEUMJDgYZ5hQ
::kKiHhrhrcolomLeKnNiCSlhKclYVbMA91VI0ThYOeZVsWYRJy/H1Qw0ITjgOQXUbcSYYQ1c5fLhi
::aXpsscilVnZLZ0oSKxcFkzcmhJp3m+F56roukaitFxgVFyUum8eIKikTVWdthql2ouN9RpEcZHda
::o7yXaIpWt9TYsPGRz6YwDhooNkZQOFRyRrOCqDsqw9u0GVUJgblaSmqOq4csr8nOWEINdYiNeadm
::h5eNERMRIy0qMkxnVHaZVICvZBwSfcRhFzYrRql6ExMUJzpPgygam7W4hGcYmHYpuZUw2LEwEhMT
::SioMQrR9HCtCK2JHM3lVREg2RE1IXJRERppxkDcdvtzjyuTMJSUlNjY2R1pmp7zEott8F0QsLVpF
::PIchN4RcNolkTauBimsmhJuhp4QXvPGjxN7kyfK1CREKCxIIPap2RF2DQG0dRIhnf39/e5GWiC0k
::xJwtzapHydnN57tD////AwwiCywLH2AJJwAAKgAqPWN9O5JqPrmAXnNxXqRGXrA7cFgyf2ERZ3yC
::YIGsn+GBv1I3tpMc0lRB0KccAAAqADMAHDtGGlg7KioAP2CEP38/QT4nSEhIVVVVfS0kbzk1Zkgg
::eGsuaWxdfnEcYps6kUUzhF8fkXAfnoEotU1EoaqYpbeiwZtC2rUc37ZB0LBl5FlA/3//8spW/9At
::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA8xHwgQAAAQB0Uk5TAP////3///7//v////////7+////
::///////+/v/+//////+x0P7+/22RLv/+//9M/v/+//7////+/////v7//v////7//////////v//
::/v7//v//////EP///v/////+/v////////////////////////5x//////////8v/////////1D/
:://////7+//////8HB////////////////////4yu/////wL///////8B/wj/Bgb/////////////
:://////8GBf//Bv8E/wcG/////////////////f///////wL//wAAAAAAAAAAAAAAAAAAAAAAAAAA
::AAAAAAAAAF+QSoAAACtWSURBVHja7X2HfxNXvm8shEazo4lnJKuMKh5bwrawLAnbslwD2ARwC5hm
::MJ2wCZAGpJFN22y2pOwm2Xa33K337d2++255t9932+u99/7+kPf7/c6ZJo1sUWQgT78PCcaW5Tnf
::8yvfXznHDz3Ulra0pS1taUtb2tKWtrSlLW1pS1va0pa2tKUtbWlLW9rSlra0pS1taUtb2tKWtrSl
::LW1py+bKwFBfX39/D5d+kD6QoYGBh459/Nfe19Pb620ovb29Pf0Axcd18f3rrN0JBMAw8LHbemN1
::O3bs2XPgwIHXSQ6Q7AHZsWOHE4WejxEGQ8bqd+w5cGhk5+7dgyBbtgyasnv3zp0jIyOHvkRo7LAw
::+FhsvqH5jx54cieu25RtW2qF0Ng5cujQyxyE3v6Bj8nm7/kSrH5Lk4IoPPmzR9l3PtAQ8OXvODDS
::/OpNFHaOHGB60P+gLr+P6f6eQ07Nb1LQQEb+BUHQ+0D6gqFe5vae3D3oZu4bLR8F1eB1BsHAg6n8
::oPu7cTG3sf8MgW0AATOEB8sOBvpp+S+P7B68ndXbcQAtGNlDMfHBUYJjfWT7sPuD64S85j3Blt2H
::SAkeFE8wQNoPtr/lbghp0ODIgQfGDP4Rbf+OQ7vvdO/t37uNK8ED4Atp+3cc+Mvdd7TwOodoeILe
::ofs99JP2jww22srbt4Itg7sP3P+OoJ+2f/eW1ggzg777Xf2fHNzSKhl88r5GYACp34GdW1on2wZH
::Hr1/ERiy1H9bqwDgrrDvfnV/Ow4NtnL/0R3etwig+3t05A6Jb1MBYSciMHQ/rn/PzsEtLRfQgZ3o
::Bwbuv/W/vNtG3FqpAlvQE95fnBDX/9ndLV66Be/gCETDnvvM/728e8vmySAyov77av17/rq1u1/L
::CV+/j0IBxv89m7n/hMCB+yYUDGD82z24bVM1ABDYc784QuC/O0a2bNu2ySqw5T5xhL/GAED8bxMR
::YEWiQ/eFG0AHwADYVATICF6+D/jQAFU/Xx/cbP3fdr8YAet87WEccDPdABXJ7r0RIAMQ4L+RLZvt
::A8kNoBH03usIkPuC6QQ2XYgS30tCCBFA+PGP0QYGt93eNnKp++yt0KGBe+oBf+OJT4lABHZusg0M
::snbz4F8evJd+EBRA/OL2J+K3xgSMDR4c3L2zaRmpkydRRv7zv7yHjBgV4AtPbP/Dd5rPBbnCw9Kf
::PHRgz55H3WRHM2KMW9FHPfcuBIICbN9ONjDShAYYW7/TnAC6SzJ0LxVgO7OBA4NNspe/fvIur/6e
::qQCGAFSA7U98U2g6H9795B7ruYXjzz9//HHnWoR/us8mz6I8ZpNHHAKf2HfCe48CwTHgAHFUgO1/
::61OvEBdqJm4bu//4yetH33jm/AcfnH/mjaPfeW5GMAA4+Kf/8/9034oceevEvVEBzIK+uZ3kCRXd
::YAMqYIvqO3/Gln/85NHzXXv37u3qergLBD86f/S5SxyEg58+0n1k69bOrSCdnfTXuvJ/37w3KgAu
::8JVPMQC2f9Fwg6ajq2vtYj3/ZVrg8z89D6t++OGH8T9DAIauZ45yDPZd7O7cSkvfcP3w9c7PnLgn
::dNBwgdubc4O8q+cVn/slrp7t/cMP12DwxkmBK4G5/HUxoC92P3IvMoIhwwUSAN+C5350p3OeYdAx
::G0i0HYjjeab4D9dIF9OHrq5nZkgJHjlyxL7G9VXgrXsRCfttFrB9+7e/Ds/ws0GTCQzuHPkSCI6H
::UkNv2yCbcnqOdt9l/V2GSnR1HS3iK//VrzqbAgBfceSz98AN9mIaYAJAkRBUgHm83SOvs4HvHXsO
::7Wbrp77+8aN7zc1H39dFLpDj0WXowd7z7+H3PotW0IQPRBv4zc13g8CChG/9oQnAdoqEh/4XDbIY
::E74kn92J1kD6//xXze3f2/X9NxZPfuUkyJ8ffeb7CIOpC/BnEb/zMfKEG+8/usGDm14Y6QN39m1r
::/ds/tywI3j3//tCXDo0cIqojFHO55wWaFxp5kj5VfKbrA2OFR08Wbdzn+UuLR88bhoF/7X2O/ED3
::Vh4NNwBga/e+TbcBCIJfNyzgcyBf/A3ByE9wSbkzU+VsMjueQ5d+cAeWjfj+439vXKpns8cvHSVH
::wGykixD4dHcTPgC/3v1pePWmuwAeBD/1B99858fvvCLYFjM2mQ2FQn6/P5QdNj+5aBj/+ZPm1jsx
::KF4/38VV4OEufNHB/7ahDjA/0Xnx4CbHAUyEvsV48BdEAQR3fSYHf+AL8Slavd+fTKbL8/BFUYSv
::F98gBPZ+9XnGhT//wlMoP3rhtc8f/9sGBEe7uJPo6sJwuO/IRutnTIHiQP9ms4A/+BxkAV/8urGb
::Z7KXy9n0olcYhu33J6NhlGQouzY7fvbsJCBwkhZ2lLb9+Cef+gSXl176xCee+tFrPCc6+YGpKMfh
::n/+xe2MNQBQwDvRuMgAisoBP/UO+/hOzl0NJfyg071385YfpUDLsIQnD59Jp+HMGthcUvOsogXXp
::RVy2Uz75eXqjS+cNBL6DRgCkuCkAfrHJgbCP0aDPfUtExV2cXCmnSemzOXHx3eJy0m8gMBoFS/D7
::0+OCVxj/cO8bj5O/+8oLL7zwyRdrIfjRcS8LFhyBGRYJNmSC8N+mB0LMhDAKvgMKPZ9Nwyb7/dFo
::OFmm6CZOhPzTuHwf/AmHPaP+EH7h+MziK1QFeJwVA157qgaBFyk6kKYgAEsCqkDn1iYA2Nr97OY6
::AQAg9+3PbX8CACiWyeNFfbDaiWFBePfM7BRYg99POhAgPYj6s/Munv/xT9bZAbrDGUaMWSQgMrCB
::G7wHTgAAEL7+hXfeAac/mU76o2EfWfw5obgC+kDW4I8yI/ChHiRD49bKhbHc/Mw86srjL9QhwDIG
::IsVdzzShAgQA/Hl6U5nAgG03x8p+/yhT94l4DtQhGR4dHQ1HRz0GAAiNP7u2fGaxSCTp3FQyG8ou
::TYpuOvACOgnDCL4C/3i6uykALgqbxgRevXGjF4LdcFFgsvI9P1+rRwXjj/q43rOls7/CwInSl5fA
::reUms6ghQJTSU2MuCLyIwWBxL8uMjlJKsHVjJrB16682qyry+zdo7ycvp8vjk7Pj47MrZVJ2Hwt6
::02GfxylcA2C98/CMM0tpRpIAg/Q46YAzIL70FHrRZ1jadB5I08FfdG5tojjU/dgmAdDvFd8TwPOH
::cBMN/28AcCHpcRVYf3mZDOb58RC6jJs3o9MAwQp87vG/U6MDrzEvYLpBsAGu5+sC8OnW50PHBoaG
::YP3/5ZdFZTU5nfQbcsHvY/vsi4Zd1z8Ka51QikUiDdkQ4IUhI+oPfYg6cLyGEOCiL3EArjMbaAaA
::p1sdBoZ62DnYyfTlqYlVHYNb9NQp+C8aZVpvWL6vDoDDF5AjXc4unRO84qp/NIB4hf3ppeuLmBh8
::5e86vQDwIeGrLBA+8zgmBJ0bJ8UEQCu54LEfgr9/N1dU4mUM8uG6tfKPfa4aEI0mk2T1s/E5/9cQ
::qtFkempY5HTgkkMHXsJA8NxejANd33+NBcKNAej8eWsB+KEgnClnl8pTxHLB0VuL99F/gYYoBLgf
::RKNH8IgfhFeXE+KJYi5XRNfwip0TvvSPUStsOeHFTtPXrwNAazPitwVhEvwdZvmGwvsMCGJSrOSJ
::FSIFqWQu3U0RfFHmMogkT0/rE1PlcrYMsaQItNiOwIug98cpK+za+0foBZsBYOuREy3MBj7q9Q6j
::u09Oh53xzeeJRTpA6H8dEanWIowX+ngwQJdJMcMIhcgHloBAv2a3AqACAgVCVhv7dFMAYFmsZXHw
::be+JqZBB78N2Vx/rcEhE0nHxsPwaX+jzodH4wlHmMsNGBJlGFC7PeIWTLzkD4VHWPcGc+M1uM+dZ
::D4BnWxgH+70zacpvJqJfw+x2Ohy+yVYoddRKQYrFYszufZAKGsTIBkiAUMS3GB0lw8Bk+dJLTjp8
::lNXKj1r50EZx8LHWAfDr3xIms8kkj/zpEFX8UA8CsUJHR1BNaarmAEHriOF+n/JfuHDB/xfRw1Gu
::Ea4xIkrJ8udr8oHrLAxYAGxUHMUGWasA+N8AAJZ1QiFwW5dXMvFhMIgo3/6gqohiRdaYBUjS6cLp
::QkFCFfAdPgwaj0TpsF0NfIGA01FGQ+Wc9/EXnSnhczUAbNggaCUAD/3Qu5xemp2cHVbE3HsYt5S1
::UHLUU8BFy0pldnluIo8fl1xYkMe0gkBg1y56QcCwEP6FZDbnFZ56cV0AtjYDQMuo4A3vu+M5wShm
::FBfnxdlQMlwi36+lJii/0TEIOMhBbVLECQFFBQd5RAC8x1/5By88ZQHwUwJg73XmBDubAODNlgIg
::EGsThhczueVyOrkGeX9UYlof9ofDyIgdy43EWPALOD57VXfg4wvw6Gi0D45/0vQB32EAPMf6I/cY
::gD7jDrThbDqUDEEcwC0nACSPVfqwbbvUEfMxrbcjUFUT8Woyaq2f/X3K718dzuVygLFAyTGWBo8y
::EzDSwSY6pH/WKgAG2PKFRaG4RAsfHUVa65/Wcf2+mtKHsxIQCJgQ+KLRlJITEpANE2K7wCOYDBEy
::6+zS2TMCpYYvAQ8Q3qCikEmFmwCgVU4QeyDFMVFZWSLD93lMUndT6tCdpZ+Az1fjBmH97DM+SAkn
::VrNr16hcGHXCFY5iTyF0edgrYHUA00FWFfugCMnQZzq3NkEEWgUA7D+QgKWpcrq8nAxFbdGbCuE8
::tplZUCAQC9SGfK4CoDjYJ/kekYlTo07SHMZG4ofXBS94gadYQaCLl0X3Hdl6DwH4cg9WAGB3pum5
::wwar51z28CgP60B1MTE4HUG3CJ/Y5ZYQEgWMgscMjxpFBPZF32EsGGQvg89/4SUKAosEwN6f2nsj
::G1PhFuQCA17vfDqZjE7oYZbI0XJx+5NAckb59vOgVjDYsA4v85lKEItETpO/C9SWCpmRMINazSjF
::572oAZ9nTNhwAWZZ+J4kQ/1eYSqUnIAH1aXoBdB4pDLgzw4ftjJfKfYnlBfi2tVUPJXSZEyJdgWM
::iEDRgi3V8hEmbAgVNtDmFC+Vh9ACimxeiBoDR5oak+lEAO5+Ogx58FjWj6VOn6SVoraah2Xjec6B
::OzRZTVCvXFQyoAMcAJYuRQJYQkB1iAWMb93FAAmwqmEyVB6G9b7y4mvcAh5mJcFHupsgAXxMpgUF
::kV7IA/1+H1uIzks/um5AELDlg5qcEjlXFESZ0ZzYaVYvQJZMWgT/KgScyYDhBJPp7CJ8PzbKsRqA
::AFziFtCEDnRebE1JrNd7BltfsJoI02N43HxF0cymFym+LGtaJpPDMYnizPA8MBrxHCOEVpZcKkl5
::9iF+YULPSw5vgAhkCQE+SgAu8A1vsxVBcAFvtQSAY1gKwjKeDxcq4bPelCqqmtdtBREtE4eEkMZA
::citJiBjjEL0TCzXlEgsLJIT4HSnZKKIZNZIQJgXAhliHvOu9jRtDLS+L93iLlyn3x7UEyI/r+sLC
::glHpOo2qnxNNqswqBlOiV6xerasXcUngRI0XfEWFKRWHAHWAWiXCc6wgSsMUbzULQIsaI31e72ya
::5/4Re3qDNS5wZ7Cv+zWBliPgcMwElr2SaaB08oQn4AqAplTiCVEBHUgFO3jOQA4FcoJQ+QS1x6kx
::hh7gs83FgNa1xpAIUvUDvZed1/GHhk/LCTD5uBqPz2Z5S3whOSkI8QWIcBFXBIKyJufzHZrWYVcB
::1AB/9j0+T9bV9eeoAL/Zbc7NW0OTtuJIJx+p7/wfrRoR6fd6x1b9fgsAp8CnM4pXiMsAxLTfiJPT
::q4qggjL43G2ALVuPSVLeVkKIggWkLwP1Ofl9BOCrFFEummu2IVALAP79ltCavsgxHIWY/Z5fN0NZ
::HQAqGLxKqzI7w9P+NblKzKcEBKE6J6tBx/rztYwQ2RX6wPJKDifFcEis6OUu0LZahkFn/Zzg1u7/
::1KJkGA9HC3PJcL7DUlef7X8cgIy5r/SFm6z/w+L9gqyISmq/HYCYa200mZ1UBCMIsqn5uukIuyXY
::1aFVuSDejiAkVJlHMlt+FwMplfJUFAQAZKMzwlLDMGZ7rOAxoeIcpWhHIGLPBYwPkqHsGcErsJHK
::D/+Ipi/HfsXXvOGEBE5KtsAF4CiMGJeDNstlBMjMe1DighjPaGowWLs2VgYSh6eun/CKv83WHilI
::UswTCNSWT8PYHRCGV8aBD1+6/h4Lq/+62zL/ztpNd8yJXWzNmQk8GReXjZp/oUFDSE4IQIOUVNA0
::71Ls9GkDh3w+nU5DVEA3UYiZlSKfz1Et8/lDUzlxFl764aQ1Rrbv592dnd1HUOyaUGsEjAW0hgYZ
::5s19oNHmswMAKQDj/ypX8ELB5jEp1U+fFYU5XYo5e2X2BvqpaDWlVEPJcDI7w/MJjAL7nn76kcee
::fXbfvmcfe+TNpy8e6XY5RoROsFWzwng62nLgkqXd9o5YRmHPK6RkO/MN8DbI4SiWfTMJ3awCu3nA
::KCST+emwR5+I07vFV8bHsVQsHLSdKzjx2FvdLgDAv3/eolNDfWQCJgKnjf53sHLFUoA45L/FXEJJ
::qI4WITVIfawsEjVHZ93a5sgJ8oaFzWE6nYhP/CAdWsrVzdWfePMzjoM0/B/d/6FFQRAPR4oJVbWa
::vzHMBfJXftdaaRBprQybH7TH+ghrEhmKjnqA66zOVfWr9VUhHY2GkWJVrCQyGTmMs/bjYxAWivPL
::kyBnhinjEB7hJdJOs2OOc6KtmpanO3IQAtvaIrX0tqKoslbTJS+Uasrj9MFyApxlYs78wi6jP1Ag
::F0v/qsryfoiYRI2zU5OTK+VsKJTGP+WpZYTgkYudlkPkc7JP320LOPZ2f39P/8AQb4gISg2Ts0sw
::5SQ52B8v1Wo5AaAKzFnOLRifpqIRpZRYMCByLBWMAhIWitNs7jbJZimymGd7H/nv9iO1ZAF3+8jQ
::qz21J3rE9RBwqL5UqjPywC5sgYRlrBfMULFEr+qesGkFp+vfMxLwGVMkvCn/F9PTSX8a3YLwZ0dq
::JsXfutu36dh+G5AwP0ykXFE7NhZyET7ntpOqo67riiBOXga79hJrSMgLvKXgmjLSG9B0GQobSvFF
::/VlE4OB3uy030Mky4bvnAo99+Vi/betzyXQSp5qFVHD9teelmjDvJDqeBXDv50Lg2QyeIyhoCgFK
::mPIFNwCodHZtTs1UddZj84WTobPwMM9+xiKH4AHe2nE3FODYjRt9b9/AXwCG+39icmWWSnuzaH1T
::RXQD6yyfdt5Bbp3/QABUMXUtvJAsoxILWD5jzoAnVVINBKYhyYoiVnSzrUIACv/2Mxe/+92/utiN
::xQKqh9/5pPyrzl+CNTwxMVGeOndugs1yledNnue+/HXnAphoFSwkTsuiMhZfLp+dBCCUc9WqbvQI
::ILfSJadG4ZKr71dlraqjX8XAEAotgUme2HfioPfgvjf/BkPA3fAA/+TtmnssILnpyK9SL9g3CrBn
::40KNr7cXN3zg52rTew+E+wULBl3SNAlnRvN5OSPrAOpZWAg6A5UVDhhncsxcRSLYbohJebIQnD+L
::+ifm4iyWvPvuCWDKf9W99cgdK8BHb98gr09qmRvOUQb82xDZ8+Gvsenn0ah/tVKRG6+/bkJUr8qZ
::eFyV32cb7KFhEpqgQ86Xx95ieoXzO6VqtQj0SGM7K0j6+6pi1F//zdLZyTHvs3+DcxF3pgADPOaN
::TY0vL6/hUUd8KNlZuAmHrima+2NZ6+cUzxdemEuIPOYrKRmUWYoY2XQJd1Znx4jO5XLDw7CPGcNl
::+Fym7pzVxFQqMbwyewbHdcbT6ami8N1fHLzDEMDHH7y5s2lgW/5o2F+G5EbUbPk/tUOn864PV4gZ
::k6ALc5l4IhWPZ5a5lhoUIqVpZpiUDJ3x+GgiII0jggmuJmzqNFjTRaiRvP8HaWohnUln08PeP333
::TkkgxjyxOLySTPu/xkY3wnO8yBdhvTvfLny46GFPKW/XR4kNRBqaX83ZVy0Uz6xMTY2jpzPLRXa6
::ALBFL/ino0l/ecwrkg0ETtOiVVXNS99wECsHGPqpqH/an815Z2HDhr0nhDvNAkABZsp40is8atT6
::dFWkMu9pWxMTHAFmwfxZIjHmus3QtzCHXOH5YrF4Aj8ozmZpCjhN00+uEbTkoZ8XripeReLVRVTy
::iqi8f9MwBYwvztJyJIY/MxqaWi6H8Cwe5I63bQAfvTr06j/DhPescewFTTEQ0yU5JSqwbZLPME2z
::118iCCIOyoNfQ6UZHi8vlctnx2fPTJZpLp66fTMYU4LuhXEy+lQlhS03X4zeOqWk1D9m6QHOHfuM
::6gNV0vAV1J7z+GlMK0m1gxt3QvjRAYg48mYwc8ZHMgnIAFH9SkYnxGfM9wVQ92vHXmEbi+PsNFSI
::hI/VZrN0MEpxBwCg+xOweTkocZxLkpSXKXb6Sgarpp9eKpmzBhF+3IZ+1qQi4O+d+Xt34vwIgKiz
::1ierwNupvhPhIhlHIjw1Y1D0sZ4QZs6mjUNEyVA2a3wEHw67q0CEUkam6rHa8TIcmvC4EssYqzX6
::otEohNLQKrgZ4XYyQfpdWMUZVsybwv4/8A3YcJaYBSuCs74TkYjbBwK1JI8e7KqMXUE8SIPT8NOh
::NGx8eSrJjseF1syoWg+CmfoFatJHX4PKkflXgI9Zww+7XvT+1i3+ut7fuYHbXzx7ma648M5P6CXJ
::/kQpsWK0ApjxBbDG79vl+lyQsCRytP4kPzE/OT+/GBeXV9kxoXSOSuv718kkauZJPQFn/9FwRT7q
::yNobM2gJWTyA+fZtUB8I/EBxcSrFm5D3a/ttwSZVCTrSez4IF3CyPZ9R8ZqorDHSzACYo/skRIju
::4ag/eW2WqKWSCgYbVBM0ybercbnQUH7fgifMJy9tdoglZ8iPhFuKhHgNnDc3iSoanUjOihBKEplM
::Sgs6i1oU6V2muqKHwzb9xy7Q9DW8MMJ0jCm1ek6eY1lOeCHD+UGDqpKmga5JbgcJSA0WFnQdU4qJ
::heqcLM9dWzD9gRmhwA7Oij3//NaoT248m4aHHvXpV6PnYMOEHHi9OONqQG+kmO56AhDn4m76L7CT
::Mz4jMoSNszR8X+B7JyZM80iyOhbmF24AXMGKqia57D6sf6KaSSiQPJ6bXU5gp0wYM6tpVvZ9CgHo
::/fIttbuKZ2nuh/2UvDHaFSeSOmos3efSvgTuRgOTo7bIiJ+OWg/lM02UPeHX/D+YFWjWXHDhQ0EN
::/K2q5d19i6zwOGUMX3nF5WtUSzOIiS+c9ENOIPbcAgBDkO1fzvJWPgLQIWOHH4vfkKWdikKmFj0c
::tXyQUdP10flPLmE+G0o7HvY7AyMSXXSa1BsdPRWWRYVuC0i5aABEXMiy8m42MIHsKoen1Bm5nqEh
::rFw8U7UOrWEcKI8Pe3t+ckvNjjNptom7kORCBpIZ8yLz06QoL0JeOOVjRh6IxexDTPxyHBoT9vH+
::pqRJo44Hl6wuKvmrvFZJLOfI17o6Aa2DThjVrX9CEYbHgVKXJ3NKcXh8Kbs0y3Jhcc5jKV9yFnHp
::vYU42EMARPkRFtxEKagI+HB5yE/Y8k6FjSFXlhF5WPmaTr2NonP3H+ZT/0DUSYEDPiN6FZxcmUi+
::LCfgKccyDeqKks/lxHFYFc9RdAVeOVXG1kAyPZ6jrrmicwcEqnqVDSc2/ftIkQALa6EkD7AMSVkR
::4/s7YvB2SInxMJvVAZTMc7FuNS9anmQdA4IPzMxXYjOhMZbi0NUZqjshihlDszyzJoXTU2vZ1QU0
::SMSAn7NMrq2Mj8fjjifJJ5AQN5kTEwE+k2WdOj1PpBM2MQH5f8F3s2YPJFtNwDbzbYQhmheN8fqG
::Nfvs3NlYgRUy2EM2aC/kdf6mNgoM3i2ZZz89zLxOmAw0iYlG1DqN4PHpclAda3JCCIffT1z/kC56
::8niuaLS5MZxcSxmtKWORRhaar+q6bta8dtFkA00LqoqY0knhC5Iew0xNqhkO7cjHzCKKnIkjBLWl
::1aBJN1nkZecr2GUMUVnjszRRv8E94KEkAMI4bcAe648jOKLQVFkAQ+DSf50t06mNaor8FNH/lNGc
::NY+BB3wShakrlVSwoxCw6Cc3B03JiUpV76gb/WlYy5FT5AesxasqTpabkOSx7GkaWzQcMYzDln9h
::FzHPWLH9/C74cbEpFYAIsLgiCnN4+HUBGYttlK9QY98MgFRFEYEjBpzWfxV7xBPX9And2kWOQKwx
::58dtsoYI5LiC/APSjqA5P6hPWGXVDqthaolRXLUnjuh4NTnXVGkUSaAoxFf9tm69gUDdDyP11dTg
::FY1N/rBW5vtqKpHKVNfWZueWZVlWZTvHj0hSxE7z1VRctZrrGhIbSAwBUE3jFFkQrGLrFaWyfO0q
::12xrLM1+3LDWLTEjKIGFjeFvJR566CcbZwHexBoegreVOaSOmreNgQcvxWy9mtNmWM9fUXDjxOE4
::o4/iWKqBa+9QUzRCraRMBOR5AQcu4sBvGbmDlCllKzbDN8R1owYX4VNpPAn3UZQtdDiGSxETPS+r
::GVXhXLFnvWDwe5QFCqpu3vpAiTcvA5mh2xeLuARqQwer12Yn5x31TyUuu1M8ngVBqqWCMoBkkBAW
::4yaxha/ITshEIXWNt1VjRlk+YPH+GGXsp802BNYxNACTjhzSrYbrGgLW/94TxUzeKOd6+Mm9Egvm
::AZvx1zc/uPVPnOPcdP3euQrrF0QlgQ0CYZ7tuQgKw4efeMG8prOuVyHnkfnKiISUHM0mvjMRuwnk
::NZzRwh8Vj+eoHdG/XgF4+HJODNom3oxjzVSf2sWsTZLVOq02tG5Ct2r+QrHI97K+7BvMVGDn1Yws
::ZxxrNr8XRHH+FCngCYfWREHRTYbFAiSjRgFWNO3Ayopka8LFwJuKyOTBGclM7foaZ0Hi2fQkPW3h
::6tVzmbx17NFUMr2K3llJ1COAL5moKtYNoOOXs+VZugmmXgWCqsirQDhLXrf8sfm4s/4QkSgdSGbj
::wHOvOufQ8GKOmOFcZXDBmlyyxm5AX3FOkW+BRs5woKEFzGRDZfI6cjUDCpk3+RRnsjerKe6d6sYB
::sBp7la8fc+dz5TQeDsHODhsWd0pK0WQDCqYu8zMzRm2kxvQhdQiw0L4aGvaK567pupR3dkmtiSxS
::HTJYIx2XOlJW7zqDQ3s9jUlA2p+kgaYgkBJBed8qwgboVpgq2y7wKfWZGx6WGmOn58fPlrP8SjDq
::VntrVwQh7UrQ5D+gUZNT5Ww2lJ0VmMVotT52F6sfTAMAkP2PjSU02ZU0ayKaU0LtKLE6Kj53Kagp
::FSvSaA0pEQAwnA4l8wQARmRVr01vVMGbmxFmsotiNZyvndrxXM2gup9ZyoZ40kilfxzsFHMQ7xuN
::kIBLyVRXCS16sUBDdTUMkqXffnAC/NhZwnUeQavkICEUVbOQinqTD6o2e0Kb62vEg8XlqWxV2w8U
::BQDIyTyBNSmBDhl4Nru2GipPQPbh7NWXQD/g4U6shLJ4/LskAXHFA7ShSW4UEO8bT9Fo2BEPT9OL
::hWK8xskaHSCW3jPX2mgkRc6AQgWtSjIobt5ORnFws1EgoDbQ8DB6kQxxspJVf6ZSZ1VUyiE6Gv89
::AKDkbMl5JkABxHG8MJH3CPk1caIZ1eV1OtsFevWU6La/uke3DtIny1PjZ4oNEdAgtQSk87b0vCZs
::qw07JcbwE/x8AkBjlajR6Cm86ARSzPfF3FQYL73CA852Vk/3QegKrT/q4c1blqomzUEH9x6gg0xF
::jatFnWDlUxWe4fhGqdmBdys1bKew7EOysoFIHQDuBaI+WxzCjQBFirGqnf8wq+vmFaVqZgl2Kkyx
::eE4QzoT8ZoeYU0dAYC0uskgvrjtLFyMViItiPVh58xwikAG6aTC9jKFovbeT3CoQ7PiC161Gal6D
::IYzlcmO8Th8xTGCU1g0OOyhJpyOFvCOp4TNbcW8uuyrVPQFdFpmJ07LWNQLsiOOQ09kVDBz2iRs9
::PGonfHgBURota923yzuzNks93H3ADYu5ZzLoJ9jYgvPwTl6rpBqNAXnWxrwrZQghmv3gi3Hic1Um
::hijG13tkcKRU3qKOsV1bSrX9IHhPvIh4LJMBUur+ltqVK5KPe3H75EaDKEB54NgYEGZcdzCO55y0
::DksD+GSErGlu/AMfUM8I3pnheKKSMLK7QsBCwK9ncozeb6C1N8NJtjg7APV9kSTdxEwjpQ3SzSta
::MM/ZkHO2SBbd6oOvYimwXGXnejr2awjAfocCsLcq2XRfwqMv+Ugkj69iFImdeWWsQ/LYC+aeDsb4
::xHUcYQFCqa6DyazVFMciJavVxIwg7E/mbOlmsLEJMMsp2aKg69DU2/A+S6G87fiuCHTMfhLSuvmD
::lwdKjoH+hFdgdx/irmhOABCBksaMYL2xamk0mkyuhv3luiYBYhwosR4EIQAAqIJtzirYCAB+IEF3
::nF/pc78KZiptAQBZU1y2n1z22frvUiRSiNU0qYTcWnZpUlGWx8evndNqk9IosibuCBsGr4582D/t
::53NDtQEjQvZmxTa/fy5hHEl316uCncbG7EHQjQmjCcxndZuiiIrRv3C5CDhQ06XVK5XyD7BBsZrF
::e3SJTRvHnq0nkDVSkXjDUQCPv5qaXFpsTJoKtj7kBDBoEDUhNgiwtuZLyYpZKfd8+O8jCcrNyrZj
::DhVcxTcikVjtzYc1KoH8JFiZWwVutED+LnlB73DYAH4LsRFMsUAF9q+jAss0kOpNNGAM5sOE/aeY
::vgZlUqxE/ZtGLCoYsadLWBX6yL0jIrj9XMdGutyDiaeEflfjTGU0Gvb4DntsD4D47IKUjD2tsj4d
::0v0hujXMdhav/mHYFvijhsFS+ZSfu3QZUi05KQs14dwmx9hYSEV1/Zm8B2pU4DyOOzO/QT+hZL9I
::1hm9MJGWTBKyztGCiB5lCWE849YkDQapEcdaE6d85rqoqKQ1IIN1BUwVNcaVC/e7704MQCzYYzGf
::zeOQlCgBMUpCHke5Cif3InmIFwGpw6p+uE9CsOdlJx7cXqFBkgcBBC/VoKb8qLU0rKYLrhSLz946
::JYO78GqDbNAFgAK/50HCZuFp84R8xDgnGbFqdlzj60aaC4WOZgAokXNLL2IeVg8ABCZFzUBawNqq
::PnMssyOY2CjRcgIARtDzUfMAmHPJxIGM+FcyPy7YIlWE6nPOwx3a/v0WfyQ2tI4GIADX3R+DDmAq
::rHHEBmKN8EaeZV2SXVOObFQR6cUgrW30BpL9+iNJytfCVYg4+n2KmIgnFCOHIAAa+YACUSbSAIst
::mZVx8h+Gn5ZsFzQAaalx4OuM3HVQGbq3YUFEjGc2RDJiHN5rAu2UyH/LAldqbT0AOmLhabpC1/LF
::Qa1S4eUs+HAMe04qO4XvswgOc+wWddBScVUONqq/iQ1nBX5NtyEoCbXj9kTO1CVmmqLEUXNzFb5o
::AmCsEcbSRCi9gl4ibm7/FSxwse/dvz+TyYkcSeZzuR9UncMFFTCVuHu5iJGGvvXPA4ra7S0/oQB4
::NQXdlCxnUgnsSvBPkLY26hb+uyRdF2anAVpQu6JZzw/paNA4iREznI0WJDpoOldqBbn7hHX237wR
::xJzW0m4JiGAFUlNRrAQ3sAmh8SnLgl7lI4OubFmzj0zUwo9kyACA/uFKt+jHrzsrg6eBmQIGNSUl
::3woClZSqpmrmSV22QGnEOEHHgyI/MpjI3KL+qeAhhYTxPtj+ca2XBcFb9G58HpwAkCvCOgBoHbJL
::KbKJUMx9ubsfBJehxDFfFW8Ne0wIBNuSMwn3sUsqifdufC1KQlbBrBRhnX2oVOKQiGmpW/cVQXLZ
::ijtWWODCWY51cmb3/aiAG7Sma8gJqHzIRlWNSCpTQr7R4QGKhWoGw2XDlATdrjgGFq/cjrdMkKOV
::GxMVYaP6cX39S6Hxov22lLeY2R9MKXR7YyIOGASDWqqpcbk+quqM5XK2aFQ/ws5qG2LqduJFhhIi
::eV0jYZFIRq/f6IX7ZVxV0MpwTB+g0bRVfD5hXN8IsR3ImLjRfERNe8SuiLUBPgjgAkzN828HADWH
::zYOOMaIOeYwnZaCxYzRCI5PURCUKu4piVERBY/H2PRvZoYtFent7HIeemxoY7bMdEZZRecC51zEr
::NJFc5nYYA1YlDRcFa1dTiQTpqIEG7dvYckY1LuAUlFw8RSMk6CJp32U5bgzYsHucgnJG49NE8KGx
::9T203UP9Bgb9TZ6gHOjDU/I9VGvLqDmFjWsYT8gfFUx53Zsz8JWyKtdRUuLi2HWAL2dUNgonEHVD
::uqTyySFhjA4B9/b3s6cXrK4dPFI8Idp/N10c46/KOHwwwyy9p29owLGi/r5bPj/KvIHxowALHDHR
::Uine5YWFCA2pggrPRCqaSFmbC36IRu+JCcTjplnypcFrE4ptWKaXT3QN9eF29PT39SEYgjHs1AtL
::HBjq4fM0sEXg7w1oeu7OjSn9zrkVJYd1WDo6IXO2gRfIyEGyUOcupxK8HYjJRRyDGwBSQUBE2xQQ
::V9R+w07ZZ3pwYX1DrmsY4Orc2z90zNhc08qNGnHP0O/dvXuSmOkMOa9PEHKZTGqMPb84lkCBpRlZ
::W1Czayjb28SYaJuEst6tl8zymM1Oe/uObWSgfX0OV/aThwZA+nqM77+b1yaC7TBbOlajDaJYN9iF
::2pDBnTaO8PdyR1IrvUO0bSAOp8Q0/fYf//dvz9CbP0mDmtbbA9rgtiijR5UbEx0eGJZqVx5a9Sb/
::GvgW3aJItmv46DpxbOQQ2Dgg1zfw4K/cckWoq7/DPh4izRsyr5W6y1b4QGlGr+HV/r+VgYfa0pa2
::tKUtbWlLW9rSlra0pS1taUtb2tKWtrSlLW1pS1va0pa2tKUtbWlLW9rSlra0pS33kfw/erK/VcjL
::ym0AAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAMAAAADAIBgAAAFcC+YcAAA//SURBVHja
::7Zl5kF1Vncc/59x739Jv69fv9ZZOd5JOk6WzEBKyKjZLIiA4qBjUUgcXBkURqqgatSwlIrjUzBSj
::NWMpOpYWKmrAZRwNWmyGNSGBNA1JOknve79+/bZ+233v3nPmj+6EKKIgavkHv6pf3Vf1fvee7/ec
::3/nd7+9ceN1et9ftdXsFJgCzC0y9B6k1QmuE3oPcuxuja+E/wFiI/YcxuRsMQ7wyVIYAOR9ovJqZ
::+ZvM+G6QPxO4rgagGeSbV4a8F7T6reUedFihla1FKefoXK7iJEZtdaLsVJ4AHpcCPqeRt4Fm3v+u
::BKQUKDU/7LlLA/6b/qkp8PbLGgLRdSGLqCkxhEYDroaygqLSJGzFk2mbX0zmDz8yk/0K8FMpQGkk
::oP5eBAxjftbDMa/1heuXRD923ZKQ1e4zUEq5tta6qrTQWggBWgiNQGBKtCnAlELmlZB3jxX5ysnk
::PaMl+wZDkHP/BAnxNwC/4fLGyA/vWB3r3Bg2KTuuU3S0IYQQ4o/shdP5oTUoNCaoiM9QPXPKvL57
::+tmDqfxbDMH0y5GQfy3wch78xdctq99/7/mNnecGpDNbdigrTEMKIV9mI4sFlwJMIUAImSy55voa
::Ub13c9PG7XWhfa4mqPf88QmXf6Wcd5Xm3H9ZFv/fb6ytC2vXcbOONk0pXjKi0vO5/6LrBefMVQrB
::dEVZTaau3rWhYePiGu93xW2ovbtfilf8Feq7aAbfpDAO/2ZH2+pLa6U762CY4qXApRQELRNDnr5V
::z+eQq0BqEOL3io5SIH2yum+iYn2oZ+yDM/nq95TGANzTMeZrTR3AKYSDNzW+Y9vqfQd6nDdHI6bG
::xdXzOSMArTURr0nJrvLAwAynClUcpRCA5fXhD4XI5V0qVYUw5smerp+uwvAYpnILni8rXf2F1mSF
::4AzT10JACCkdrVSgZl3rjUvf90b98OFTMll0iAZMpAa0wpESj5T8ZijJV/M1xC69ltYN56OUYqi3
::lycfuB976Bif+2CURbUulbKLaSwshhBojfR4beeTI/6mz3y7+iEhKncu4HZeawoZQkpXK3XZipuv
::vH/pRy9VPf+1T370vkf4wLlN/Hi6RBIvV3kqDBarfKdtO7d84y4ilsHJ7sP4fH5aO1bQsHgx99/3
::C576n5u5+5MFahoBW/0+MqldtEfuvL509KFn5zZojRLita2AWLJkiTU0NKS8Ae/W6Kbluu9bv1Wx
::8ax87i1v4l1Hx7joM+/AisC39vVx6NGj3Hr7F+n+7f187Y6vEl+6AeVWENUMy5fG+Ox/fw0Zupdr
::9lzBfV9WSFcjTm8JwHG04alz9K4tnjUPPcsay6RnoQAp8y/LHaGHh4fLQghCsbo1Mw8eFcsLZa7+
::3A4S6QINTzezamOI3sQzrP9EI5273sq/feI6JsdH2XbhdjLVEA1rr0Yi6Tv0AB++/Cp+/PgDHH7o
::Jn5+/+2855oITtpZ2OyAKZBauxesN03wX+Cq0hkCxl9QdQD8kWDkrRdetf3OS/55wxUXbmlj85Vr
::jRHZi23nia01GJg5jl11mElOsbpjHcnjWS5+70YuvWUVztAwv/3+r2hcuYXW1ZsYGxjGzQxy0dXv
::5Tc//C5v69Koqj4t7OZLndTKK0354wftsVzR+VVXF3J4+FWuwN69u+XRo536ufGD//muW674SMad
::ZNoeJOUOcPjIoySn0gSiHmINdQQjNQT9YSK+CMemn+GCf11JpVzg+LFelm5r5/0xL0/u/yXeDR+g
::edVmup9+lEvffwMZ3YyTHcb0WGitX2TgIKIhTWPMbB1Lwscb0Ptf7R7YvXuvuuYaoXfsPH/b4//3
::rFueK6pVW9qtk9kHmDqR55wlq5kVI5iGSWmuSiRo4vcEqZTTHO17Gq+nBssvyXhnaL/sHJpfGGew
::+1dEm1dTLldQroOWFq5SmGe9EsSC5rBMCHpFEGD3XjTiVRDYs2ePFEKojg3tt7ata1lZE7KIbpVW
::uFGzYmoNjS0JgvEwwZRDaiJDvDFG0ckxV5jBNHzErcXUR1qo1s4ykRxiYOgUl3/8AvZ/53meeCbB
::+o4YhUIJn5vEG/DinpVC+vRrT4OrtHM2rldKQNxxx+0KCO58245bVr4v4jt14rguFCSZ43PUtngY
::fX6Y8V/nyA8qfJUIifZJOq9s5OiRYUwDFrVlGZg+jrccRgccQoscMnKSJRva+Pn372HnLXfxzBMH
::WRWfwK2pw0k5eMyzFJ+BLhYgM6cSAPdeM78wr1QL6R/96GoDsPu6x4YGe8YZHOjXHq+J66uQLWXo
::P5Rg4KEU67es4dp/v4zWxhWkp+Yo5Wym+uc4cuAoPQdO0Pf8JBP9aSo2jM0OsmJTnG1vXEPb6nPZ
::980v8LF3hjE84A0aKC1eVKwmjCeFHpxyewG+fu88AePPSoUuDIYx7vvpMceqCaythGc/XQhPy7pY
::rWxZ0sDY8CQDJ0cpJ10qMwYszTBVGCHYApGmAB2xdbj9QWqW2izftIzVb2qhqT2KRBP2xJg4kief
::rPLLu38CmRdYs8ThuSM2pbxDy2ID1wHXATNg8OvHkHsfKd5hSD04qOez6uUICK21uP2OLyg9iAIU
::2nyDqtpvQcpdRCpaBrXIJIqMnprBtgu4ZdDCQXkdKraN5ZVEGqKImipLz2sg/YKmOCQRXvDWSqSE
::Q797BuIlJmcHadtises97+KJwSUkl2zn589GmOqbYMdWgSlchbDEbXdVxnpHy5+SEufsAvWHZkpD
::OspVAF0Bf2SXU620tW2Kv79j3VLO296pH3vwkEjFTuDxGUgBrnLwhQJ0rG/D7/MRCoWwM1Xm0iXi
::7SGmhjLIiSizAzkqOYWMaJo2WVQ9OdKpIompcerq46xZ10l1wgOhPMtXrGHfrS+wloO85221jipg
::XnTT7GerbuWLWv95LeRrbmu88+J3br9h5SUNnDo2wuMPHdC7btygG1ti0k1b9BzpYWJ2gtpoLYGA
::l0XLGqhMmaR7NBjgNwP4RYjn+p7BuyZNIOinXLE5f8MWIsVWHvrZk6y7tpHJ0Ukmjqexwi62XSYS
::DzIzk8UjLdYs2oSnuFyFtZLfu/WuE8ky67WmKs7aGsYfSGMzVFd34xt3bvqBaRm7tlzfSvfkE87g
::dL+2U4YsuSmRzWQg4LBoWYy6eJyW1jj1bTGk7cU72sL5l6+iqbGZumA9l31oO6ceTnLs+WN4GwXF
::rM34xChz3iQlK0d9cxiP10NrWzPNHXEWL2uisbmexqZG6hujRM6RLFlfQ21zRC8+Z53rFov7P/Lh
::5MSePYj9+88i0NXVZY6MjLg1NcHrbr7z3V/ffEND7WR2Ut/3Hw+Lxcsb5fbNm+WSDfXUNtdQ31RH
::jddPc2Q5q1rX4SpFrjyLR4VYvLaWUfc4o4kBJjJDZMwR/CEfB+4ewB+3qGmWVCuQnc1RSkDr6gbq
::GoJow8VjWqS7DaYParLHFJkeyM84VAI5YYRtt2PRivBDP+ieyGTSj4z5OjypvpR7moAcGhpSn//8
::55u2X7Llnouv31BzqPcpbda5slQqs+PKjdQ1RrCCcKy7j9nhEtGmABXXJlecwS66TJ+aYyzRx9j0
::CKZrkZieZio1TilfYbowgLcesr0uNYtMvD6TSkJi+ASegEBUBN6IF1HwYRcrdF7UQue2dlrWRsgm
::i8QWh3FFRfSPntL9vQOdmaHyL1N9qcQCdm3M/7iNY731n6rr9F5Rc05ReyzLsKtVtMemriXMUP8I
::3QeOkp8rkJrMEowHiMYD/O6bJ3j8OydJHrUZPzqLGy6TSExhF0sUE4KB/VkSz1WQHkl+qkLuhCDT
::V6EwoQkuUuScDJlTBmbJh6+tysn+Xjy1mqye5sTwcSYzwzS11uFKR0z3p0mcLAY9IfMqp0DRrbiH
::AWlorfVFF92mN23b8KX2S+It+370iLbcgGw/L05LazPJPpupBw1itU2UrCRVVcYTlOSelzARZePO
::5bz75ssZPZTnVPcA8XPCuK6DUzaJtpm4yqElsJytW7fy2H2HWbozRP02gRGUrFi3gh1v2MLAvjmO
::H+jH9mRJzWSZHkmRHE8z/miFQNyiuT3G7NScmJlNq6U7PbXCNt6aHnTvE0IlpBCCQKB2/ZFne2KP
::/6SbfK8hs3YSQ5mEffWkp3LUbXaInQtOVWNaFlFfPYnnqtRucThpHOTpxAO8/dPb6Iit5eRPcxiW
::gTdSQXuqhFcalDoGaL5Yc+OXryU/YFB1NLIqqLVqmVNT7LixnR3nXcLkw1BOuZRLNsIU1G+WTEwm
::yU2XaGyPUL/KksVSxfU1mhp0XC9ICe31et574bXrO2IXOW5snSUMD8yVyiSyYyzfVocO5Rid6Ofc
::rZ2c94Z1yGSY9o42RKqG6ty8ds9HxrnwM0vRymHqcYXhMVEuCBdyiSKjw5NEm2rRjkIKgSscBoZO
::MTQwTMLup6XLQyBYw/D9FfKDAmEKpClwnRLVqkMwECQcCmkURnaoUgBnRAgw0IjSpws9yYnMNbH1
::Vq037upCqSSqdolivkylAg0t9UQiIVxHMTOVYTIzRsfOKPGOACMjIxRyJRL9aQaH+/HEJTPdFSKd
::xkJbKHHcKivXdjBzyKGv2EN0qR9VkqRn8oweKOEPWJhhTbRTUFBzzBysUrfWQDkgTSgUCnpyKEEi
::kRaWTzjS8frSvapPuc7TJgKJYDo7Xv7u7NPWnsYus6ocZUyMpwQqKbRC+IMepBTYlQpCGTi2Yt9d
::h/A3KkyfZjZd0YOnMsIbN6hpAFXVWuVABBSAMixJaigvJ04UVE3Y0hqXSskQ/lpT61l4/qkBka2k
::iMYi2t8gEKYUuVNaBpqlTnULLTbnDSU0/rCsqoppTT9X7HWc0r3sQRqAZjeGfkE9Yuf0m6Tt73Dn
::hAwvM4XQUngCwsWA9HFcJ2WomsVaSSmV4QHDhzK9UpsBQ4aWSWXVatcbkbqaEbKUUKK+0xJuUUrT
::Z8rUXEoMvjAtTWlKf9SQqqKkNLX01iFDTZYspmw5cTQnfbWWlNqUlgfhb7TExGNlqcqmkx/QWV02
::A6ketzr5bPFmUAfZf6ZlOCMpYsAFkaaaG7xxc43WWkQ7zGbXEQSCHqZ6itRvtTBMjTcuQcFcvyI/
::rqu+uLT89VApKjLHqsqeIx9d4jHSI+WD0i9CkWbvmuyAfUTZHMeQL1Tmqml/s9FeLbg63OLbVZ1T
::s5l++8FIu3ejL2quNAOsLKfVwOyx0rftvL0fmAVjI7ijwPHTTb146YkD6HmpGgCCYJwHrvDV+K4o
::FysnBKJVCryhxb7NCpXOjTr3QPUpMDqlFOco5YwA/cAEYAFjC49uAcZfRQcbmwc9P70LuE53ZuLl
::PnwIwDh9A2f7nzinEPLFmLPvExLYgxRnx3Rh0oUJC9cuTK0Re/YgAXP3bgytmT+KF2e6RnkG2yts
::ws6GbpwWeme71ggWBl146NkxpweUf3ASLl7lEc4/1Ae/1+11e93+Bvb/8PuDFZ/P4/AAAAAASUVO
::RK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAIAAAACAIBgAAAHN6evQAAAhVSURBVHja7Zd/bF1lGcc/
::73vOub9ve9ve3q4/122s7Ta2drZDYLI2KCJZgATo9ocDjZENSUiIkRhMzJgxYAwmGsM/EkUTRdKS
::qRHBDEcY88dkDLZuXbd2a+/6a/252/v7nnvueV//6NBKAKfgX/rkJOf89eTzfN/nec/3gf/1EB9j
::HrEin17x1v/VAvZ3Y5pCIMU/CKQAQ4ApBN1gflih/7ECvWAcFLiu/nuedUD11YozwBIwCcswrkYC
::6mMB0PuR4gAKqOmOlj14R01gV1vQbIuY0lJoMi5kXJWN59zRX81mnj++mPmhFGSVxgDcjwIg9H6E
::OIBqCQW+/Oi68m/fuypYE/NIlNa4WmsBCIGQCISE6YLimXjqzJPD85+XgoH3Qvw7AKKvF7mrH3dn
::bfkzT7ZVPrwlbJFz3FJBaakRQoMAveJBBw3hBizD+t5oavFrZ2a6pWBQrTiOawbo68XY1Y+71e/9
::7sFbGh9r9uDMFZXpkUJowGsa+N5tRClxXYVAoQGBLkmvZT59fmnkqemZrsVHyIgDy4DXCmAIcL1r
::az91XVXo6OEyp+T3WYYpEEWlCQnN2HyC87bEVho7nyNSWU5Re3EcFyXAA05aSevRgcWnEzr72H1g
::9INrXFPH9/XJwb4+mo6++AMeuLU18vsT+qaQNE4v5KmWmt8kXH7Xcz+53fuY334H7zRs5aWp83Tt
::nKbyFo1/i43VUZTRHY6ujRrtr71TeO6cJK018loUkIbHVG6xZDTtu306uK421vzqgN7ot4S8tYXU
::y29B1z1UX9fO8cPHiMSqWL8mSkvXTUwc3Mc37jkJhh+UAh9uYso0tu3L7b04lXu2uxvzWhTQ2lWs
::ua7p3qam2AM9awOiZddqiq11ItiZI/SZtUwdnWXoxCt4Ki2mkxsYGkuSv3yaaOceEm/1sX6diZPR
::iIJWgbAhTg6TOTliH/zpF5Hmh46chubm1eX3fvWzL4Ua5XYjltTjE+Mifm6BmvpK8tMmkXCE1rsq
::+ER1ByIFb/zyNdTqBxkeOcymbTButyDVMFJ60QKBR4mmatYB9DyBKz/w3Ht7pRBoLUu35VP2dq/h
::U0tXbLF0JUu4vJxMIYcvEEAYkox3jlQ+yUL5JDfs8SDmX6ZQcCjYNlp6QOmrUiIQ4PMSArBMtPmB
::M9/Xp4QQ/p0P93wnvCWvFnSCSCTCYk4wezaFTnmwbkgylDxLZSBGSJTIlpLUtRl07AiS+MUCHt/t
::1Fij4POjCgpDaq0Bu0gGwCkh3k8BuXdvp2lYhmY1Oj45GphKXpAlCiI+d4E/Pz9E8pLNxpvW4WYF
::hXEPA8fPMhg/RS5VIp1N46vSbLq+hTdf/BHtsQXcpI3HBwZCi6LQ8RmGAV5/AmNlE4ru/d3mpSOX
::3BMnLiuttJekb1eyOHe/p05poaQYHhillBGosjzF8gVqW6toXd+KlQ4T9JdT2x7CKdhMjs0SnzpD
::rN5klk0cGo0Sys3Q0FLUE3GffPxZ+6lM3hkcWzmGQgi01lRUV9/c1dPyUHx8oqN5W/XmTVtb9V9O
::HxUZMU/A66dmTZQyqxJL+3BSoKMZnIRBNq6pLKvGrUiQ8S0yPXaZ9Rtb0bYfKxgkcyil7t6QlAN/
::vXjq+wcLN2tNXogV/2qtdUXXLR1fr2gMPrL5C5X+zKFJ7OC8LjYHxLb6Nq4s1FIW8+HLVeBZilLK
::aRrXNnHw578lUTtApDZMuALySYe6dbWEzAq0KKBkgcWZSVr3bNQT7naGBs4MCfFKrueJbhOOlIw+
::3Wf0H+hXd+753At3P9X+pbfPnjBmxhfcT/feiPRq6RQc6usa2di6kWQ2gesqAk0lJpMXcKLzFPJF
::Ro8tUrbGZHJ8GmlImjfUUFEfwrNUhXepljK7nlRqSUTbbXza1/LmS4M/G39jfAmQ5m5jt1vbWHtb
::eL2+a9GeLlZf77Wi0ag5P7vAxXOXEMogEi3n2AvnSY0rEt44sQ4fhWSRtw8rpJJ48DJxyMYX9JNu
::S3L6jUs0NtWRVVM0bKknl7HJx9Mikwmqc5cveKJtof78Fb03+5XsGQMNTc0ND6VF4ubx4Sl23Nlh
::JKdKzJ4oUZRpcuIK7kSQ3GXJJ+9qJX8uwMjQKKE6C6EFlCRdnZ3MDWbxtmWJNpfReUMniXckZ0+d
::YyY9QXxkktmRJA0t1SKVyiuzIdcoXdm+9FzhxxIoF1G7N6MWKTq2zOVtQlGL0OY09a1VrG9uI1xa
::RaBZM6ZOctvjLQTsCMlRB381EMtgtqTYsfNGCmkHXMX0/Cibd0epEk1cejWH5bHw1DgsTCV1U1sV
::hh/XdSkC0gAcacqW2HZjm6wqOvPTizpXKGhf0IMWitmpRUR5UVhlWk9dmFNjgxOUfHm9dNFV4bWG
::LuYcVRWKqoXhnMpWzGrlQvz4osrmM6qpx6cnB5ZUMaWUv8JQuXzOWLhyRSqlZGqYVGqi8BMhBGhN
::tG5r2ZvRLb411ioHDBdcSW5GE24WFBIaM6AxLYtiWuMtk8z8sUSs0wBL4TWCzPzJJdBqY3oEQmq0
::1Hg8HuykppjQSAuWLhWd0GpslTX943/I3ZdP5n+97KQFGk1dMBK8J9hgdHnCtFh+oy43q8LeGiUD
::NUZEO9jpCX3MWyFWIZRvabg04g2aacd1z1hB2ZqfL503lHFSmyprhUWlN+TZsHA+ezpS7631RT2d
::2XlneO5UoQ9kEQp+4NyyfXzXGy5DrIwg4Fu+J6wGcDLABZbvDgOwP9IapBHvtWSSXkQv0NeHkgZa
::62VEfRVsv0J+y1g2k/qbyN6ziP45RG8M3T+HIHa1hDlEN3Akhu6eQ9ADR14HjvzTXvAvTal4n2/1
::PuvX/+Mjxd8AZ8/mWLHAdCkAAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAEAAAABAIBgAA
::AB/z/2EAAALOSURBVHjajZPLTxNhFMXPd2c6pVD64FEo4SXVgjxUItEYH62JiTtjQmRjjDEaNxrj
::0o0poPF/cGeMcaG4MmGnATXGCMb4qBFQBEEK7UCnU6YtM9PvcwEaE/Fxlvfek9+9NzkMfxeLRSD1
::IwIAGAEwMjrKBwCOfykGELHNewKgn4Q/+AnrFPlKuKq3w60c4EJIaRvz12eWh9SsORkDaADgbDPy
::NYCfq3S3HW+tuLPf79ztoQ0UkzCRKRhDCeP01YnUAx7Db0syce8Eee7O+AYXFl9drnI0maZlJRxO
::ljE5uLkqKkrdjvG0aZ5/qe1UsToh/eqOxCLymYvDRbNz28nqtsZTJfm8+aSsVhkKHafnoSilt5hS
::KPrWaj5KSn0NnHteFB7KP1ePxQgAb7wQ7FHC/BLVFIrD9SFZ0fzgU18wM+GC3NgLR1lcamhJiu55
::ZR8Aoo3DKdoPGhwc5KUt9s3wwfIubWUOxvQS5awp+LoTaNsTh55QAS4AWzCZUApAWn/PAPhhNmDL
::ItAxlYy3Pxt7yifHvlFRAKlZA9PvVgD/Epj0GG9SijBWHNAy5hQAWwYg9h7au93Xjhvcm4tWh8qd
::WaGi50gn8yIAPT8Jm2yoKRXFrjXcygfF+8/NyH5K3gFeCznoDle1HvM+orpcMF9Q4PQCXr0NyeVv
::SDMNn8cWYUgr2HEojGBdECa3WLLeKT7Gqdfvx0OppsN1lgf0vtCuunx6SYc2lxeiIPPlrxr/OBsX
::TaEG4ci5WXkzsWKyRLx6Mw7ZZQrJt9a+OJ9NSg6fTLws17fKNXeR25IlLDIklXKFAtlZkKuKkWmA
::qekkoNgsu2AzXc0xI7OmG3PiNgMAJzxbPT3mvqKBBldAVBJJKrdZvrhKqgVbN3VL9TS6DV3VXJW1
::FZ50vJDKLOQWACz9LQ//pR9mikQ2EhbdqIwAoz+mAhBoh8CHX2D3wQGI7wdJRhu/ocNLAAAAAElF
::TkSuQmCC
::BUSHICON-END
