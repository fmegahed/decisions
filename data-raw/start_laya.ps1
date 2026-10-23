$env:LAYA_DEVICE = "cpu"
$env:LAYA_PORT = "8000"
$p = Start-Process -FilePath "C:\ProgramData\anaconda3\envs\laya\Scripts\laya-serve.exe" -PassThru -WindowStyle Hidden -RedirectStandardOutput "$env:TEMP\laya_out.log" -RedirectStandardError "$env:TEMP\laya_err.log"
$p.Id | Out-File "$env:TEMP\laya_pid.txt" -Encoding ascii
Write-Output $p.Id
