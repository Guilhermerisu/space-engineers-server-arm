@echo off
set PATH=C:\windows\system32

rem wineboot does not finish reliably under Box64, so register the core
rem services that the dependency installers expect.
reg add "HKLM\System\CurrentControlSet\Services\RpcSs" /f /v ImagePath /t REG_EXPAND_SZ /d "C:\windows\system32\rpcss.exe"
reg add "HKLM\System\CurrentControlSet\Services\RpcSs" /f /v Type /t REG_DWORD /d 32
reg add "HKLM\System\CurrentControlSet\Services\RpcSs" /f /v Start /t REG_DWORD /d 3
reg add "HKLM\System\CurrentControlSet\Services\RpcSs" /f /v ErrorControl /t REG_DWORD /d 1

reg add "HKLM\System\CurrentControlSet\Services\SamSs" /f /v ImagePath /t REG_EXPAND_SZ /d "C:\windows\system32\lsass.exe"
reg add "HKLM\System\CurrentControlSet\Services\SamSs" /f /v Type /t REG_DWORD /d 32
reg add "HKLM\System\CurrentControlSet\Services\SamSs" /f /v Start /t REG_DWORD /d 3
reg add "HKLM\System\CurrentControlSet\Services\SamSs" /f /v ErrorControl /t REG_DWORD /d 1

reg add "HKLM\System\CurrentControlSet\Services\EventLog" /f /v ImagePath /t REG_EXPAND_SZ /d "C:\windows\system32\svchost.exe -k LocalServiceNetworkRestricted"
reg add "HKLM\System\CurrentControlSet\Services\EventLog" /f /v Type /t REG_DWORD /d 32
reg add "HKLM\System\CurrentControlSet\Services\EventLog" /f /v Start /t REG_DWORD /d 2
reg add "HKLM\System\CurrentControlSet\Services\EventLog" /f /v ErrorControl /t REG_DWORD /d 1
reg add "HKLM\System\CurrentControlSet\Services\EventLog\Parameters" /f /v ServiceDll /t REG_EXPAND_SZ /d "%%SystemRoot%%\system32\wevtsvc.dll"
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Svchost" /f /v LocalServiceNetworkRestricted /t REG_MULTI_SZ /d EventLog

reg add "HKLM\System\CurrentControlSet\Services\MSIServer" /f /v ImagePath /t REG_EXPAND_SZ /d "C:\windows\system32\msiexec.exe /V"
reg add "HKLM\System\CurrentControlSet\Services\MSIServer" /f /v Type /t REG_DWORD /d 32
reg add "HKLM\System\CurrentControlSet\Services\MSIServer" /f /v Start /t REG_DWORD /d 3
reg add "HKLM\System\CurrentControlSet\Services\MSIServer" /f /v ErrorControl /t REG_DWORD /d 1

reg add "HKLM\System\CurrentControlSet\Services\PlugPlay" /f /v ImagePath /t REG_EXPAND_SZ /d "C:\windows\system32\plugplay.exe"
reg add "HKLM\System\CurrentControlSet\Services\PlugPlay" /f /v Type /t REG_DWORD /d 32
reg add "HKLM\System\CurrentControlSet\Services\PlugPlay" /f /v Start /t REG_DWORD /d 2
reg add "HKLM\System\CurrentControlSet\Services\PlugPlay" /f /v ErrorControl /t REG_DWORD /d 1

reg add "HKLM\System\CurrentControlSet\Services\MountMgr" /f /v ImagePath /t REG_EXPAND_SZ /d "C:\windows\system32\drivers\mountmgr.sys"
reg add "HKLM\System\CurrentControlSet\Services\MountMgr" /f /v Type /t REG_DWORD /d 1
reg add "HKLM\System\CurrentControlSet\Services\MountMgr" /f /v Start /t REG_DWORD /d 0
reg add "HKLM\System\CurrentControlSet\Services\MountMgr" /f /v ErrorControl /t REG_DWORD /d 1
reg add "HKLM\System\CurrentControlSet\Services\MountMgr" /f /v Group /t REG_SZ /d "System Bus Extender"

exit /b 0
