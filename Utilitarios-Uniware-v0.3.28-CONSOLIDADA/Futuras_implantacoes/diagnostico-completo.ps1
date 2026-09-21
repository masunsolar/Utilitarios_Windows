<#
  Diagnostico Completo de Integridade - Windows 11
  IMPORTANTE: Rode como Administrador
  Isso pode demorar 20-40 minutos dependendo do disco/CPU
#>

$logFile = "$env:USERPROFILE\Desktop\diagnostico-windows-$(Get-Date -Format 'yyyy-MM-dd_HHmm').txt"
Start-Transcript -Path $logFile -Append

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTICO COMPLETO DE INTEGRIDADE - WINDOWS" -ForegroundColor Cyan
Write-Host "  Log sendo salvo em: $logFile" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# -----------------------------------------------------
# 1. Informacoes gerais do sistema
# -----------------------------------------------------
Write-Host "`n[1/10] Informacoes do sistema..." -ForegroundColor Yellow
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, OsArchitecture, CsSystemType, BiosFirmwareType | Format-List
systeminfo | Select-String "System Boot Time", "Total Physical Memory", "Available Physical Memory"

# -----------------------------------------------------
# 2. Verificacao de arquivos de sistema (SFC)
# -----------------------------------------------------
Write-Host "`n[2/10] Rodando SFC (System File Checker)..." -ForegroundColor Yellow
sfc /scannow

# -----------------------------------------------------
# 3. Verificacao e reparo da imagem do Windows (DISM)
# -----------------------------------------------------
Write-Host "`n[3/10] Rodando DISM (verificacao + reparo da imagem)..." -ForegroundColor Yellow
Write-Host "-> CheckHealth..." -ForegroundColor Gray
DISM /Online /Cleanup-Image /CheckHealth
Write-Host "-> ScanHealth (mais demorado)..." -ForegroundColor Gray
DISM /Online /Cleanup-Image /ScanHealth
Write-Host "-> RestoreHealth (repara se necessario)..." -ForegroundColor Gray
DISM /Online /Cleanup-Image /RestoreHealth

# -----------------------------------------------------
# 4. Saude do disco (SMART) via PowerShell
# -----------------------------------------------------
Write-Host "`n[4/10] Verificando saude do(s) disco(s) (SMART)..." -ForegroundColor Yellow
Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, MediaType, HealthStatus, OperationalStatus, Size | Format-Table -AutoSize
Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk) -ErrorAction SilentlyContinue |
    Select-Object DeviceId, Temperature, Wear, ReadErrorsTotal, WriteErrorsTotal, PowerOnHours | Format-Table -AutoSize

# -----------------------------------------------------
# 5. Verificacao de erros no sistema de arquivos (CHKDSK - somente leitura)
# -----------------------------------------------------
Write-Host "`n[5/10] Rodando CHKDSK em modo somente leitura (sem reparo automatico)..." -ForegroundColor Yellow
Write-Host "Isso apenas VERIFICA. Se encontrar erros, rode manualmente: chkdsk C: /f /r (pede reinicio)" -ForegroundColor Gray
chkdsk C:

# -----------------------------------------------------
# 6. Teste de memoria RAM (agenda para o proximo boot)
# -----------------------------------------------------
Write-Host "`n[6/10] Memoria RAM..." -ForegroundColor Yellow
Write-Host "O teste completo de memoria exige reiniciar o PC (Windows Memory Diagnostic)." -ForegroundColor Gray
Write-Host "Para rodar depois, execute: mdsched.exe" -ForegroundColor Gray
Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object BankLabel, Capacity, Speed, Manufacturer, PartNumber | Format-Table -AutoSize

# -----------------------------------------------------
# 7. Erros criticos e avisos recentes no Event Viewer (ultimos 3 dias)
# -----------------------------------------------------
Write-Host "`n[7/10] Buscando erros criticos nos ultimos 3 dias (Event Log)..." -ForegroundColor Yellow
$since = (Get-Date).AddDays(-3)
Write-Host "-> System log (Critical/Error):" -ForegroundColor Gray
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$since} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
    Select-Object -First 30 | Format-Table -Wrap -AutoSize

Write-Host "-> Application log (Critical/Error):" -ForegroundColor Gray
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$since} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
    Select-Object -First 30 | Format-Table -Wrap -AutoSize

# -----------------------------------------------------
# 8. Verificar travamentos/crashes recentes (WER - Windows Error Reporting)
# -----------------------------------------------------
Write-Host "`n[8/10] Verificando relatorios de crash recentes..." -ForegroundColor Yellow
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Windows Error Reporting'; StartTime=$since} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message | Select-Object -First 15 | Format-Table -Wrap -AutoSize

Write-Host "-> Verificando Bug Checks (BSOD) recentes:" -ForegroundColor Gray
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$since} -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Message | Format-Table -Wrap -AutoSize

# -----------------------------------------------------
# 9. Temperatura e throttling (se disponivel via WMI)
# -----------------------------------------------------
Write-Host "`n[9/10] Verificando processador e possivel throttling..." -ForegroundColor Yellow
Get-CimInstance -ClassName Win32_Processor | Select-Object Name, LoadPercentage, CurrentClockSpeed, MaxClockSpeed | Format-List

# -----------------------------------------------------
# 10. Verificar drivers com problema / nao assinados
# -----------------------------------------------------
Write-Host "`n[10/10] Verificando drivers com erro..." -ForegroundColor Yellow
Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
    Select-Object Name, DeviceID, ConfigManagerErrorCode | Format-Table -AutoSize
if (-not (Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })) {
    Write-Host "Nenhum dispositivo com erro de driver encontrado." -ForegroundColor Green
}

Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host "  DIAGNOSTICO CONCLUIDO" -ForegroundColor Cyan
Write-Host "  Log completo salvo em: $logFile" -ForegroundColor Cyan
Write-Host "  Me envie o conteudo desse arquivo (ou print das partes" -ForegroundColor Cyan
Write-Host "  com erro/critico) para eu analisar." -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

Stop-Transcript
