<#
  MANUTENCAO COMPLETA - Windows 11
  Reparo de sistema + Windows Update + Drivers + Componentes + Otimizacoes
  IMPORTANTE: Rode como Administrador. Deixe o PC na tomada.
  Duracao estimada: 30-90 minutos dependendo da internet e quantidade de updates pendentes.
#>

$logFile = "$env:USERPROFILE\Desktop\manutencao-windows-$(Get-Date -Format 'yyyy-MM-dd_HHmm').txt"
Start-Transcript -Path $logFile -Append

function Step($n, $total, $msg) {
    Write-Host "`n[$n/$total] $msg" -ForegroundColor Yellow
}

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  MANUTENCAO COMPLETA - WINDOWS" -ForegroundColor Cyan
Write-Host "  Log: $logFile" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

$total = 15

# -----------------------------------------------------
# 1. Ponto de restauracao
# -----------------------------------------------------
Step 1 $total "Criando ponto de restauracao..."
try {
    Enable-ComputerRestore -Drive "C:\"
    Checkpoint-Computer -Description "PreManutencaoCompleta" -RestorePointType "MODIFY_SETTINGS"
    Write-Host "Ponto de restauracao criado." -ForegroundColor Green
} catch {
    Write-Host "Nao foi possivel criar ponto de restauracao (limite diario atingido ou desabilitado). Continuando..." -ForegroundColor DarkYellow
}

# -----------------------------------------------------
# 2. Corrigir servico TrustedInstaller (necessario pro SFC funcionar)
# -----------------------------------------------------
Step 2 $total "Verificando servico TrustedInstaller (Windows Modules Installer)..."
$ti = Get-Service -Name TrustedInstaller -ErrorAction SilentlyContinue
if ($ti) {
    if ($ti.StartType -eq 'Disabled') {
        Set-Service -Name TrustedInstaller -StartupType Manual
        Write-Host "TrustedInstaller estava desabilitado. Corrigido para Manual." -ForegroundColor Green
    } else {
        Write-Host "TrustedInstaller OK (StartType: $($ti.StartType))." -ForegroundColor Green
    }
    Start-Service -Name TrustedInstaller -ErrorAction SilentlyContinue
} else {
    Write-Host "Servico TrustedInstaller nao encontrado (incomum)." -ForegroundColor Red
}

# -----------------------------------------------------
# 3. SFC - Verificacao de arquivos de sistema
# -----------------------------------------------------
Step 3 $total "Rodando SFC (System File Checker)..."
sfc /scannow

# -----------------------------------------------------
# 4. DISM - verificacao e reparo da imagem do Windows
# -----------------------------------------------------
Step 4 $total "Rodando DISM (CheckHealth + ScanHealth + RestoreHealth)..."
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth

# -----------------------------------------------------
# 5. Limpeza de componentes antigos do WinSxS (libera espaco)
# -----------------------------------------------------
Step 5 $total "Limpando componentes antigos (WinSxS cleanup)..."
DISM /Online /Cleanup-Image /StartComponentCleanup

# -----------------------------------------------------
# 6. Resetar componentes do Windows Update (corrige updates travados)
# -----------------------------------------------------
Step 6 $total "Resetando componentes do Windows Update..."
Stop-Service -Name wuauserv, bits, cryptsvc, msiserver -Force -ErrorAction SilentlyContinue

$softwareDist = "$env:WINDIR\SoftwareDistribution"
$catroot2 = "$env:WINDIR\System32\catroot2"
if (Test-Path $softwareDist) {
    Rename-Item -Path $softwareDist -NewName "SoftwareDistribution.bak_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction SilentlyContinue
}
if (Test-Path $catroot2) {
    Rename-Item -Path $catroot2 -NewName "catroot2.bak_$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction SilentlyContinue
}

netsh winsock reset | Out-Null
netsh winhttp reset proxy | Out-Null

Start-Service -Name wuauserv, bits, cryptsvc, msiserver -ErrorAction SilentlyContinue
Write-Host "Componentes do Windows Update resetados." -ForegroundColor Green

# -----------------------------------------------------
# 7. Forcar verificacao e instalacao de Windows Update
# -----------------------------------------------------
Step 7 $total "Verificando e instalando atualizacoes do Windows..."
try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Host "Instalando modulo PSWindowsUpdate..." -ForegroundColor Gray
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction SilentlyContinue | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction SilentlyContinue
    }
    Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
    Write-Host "Buscando atualizacoes disponiveis..." -ForegroundColor Gray
    Get-WindowsUpdate -AcceptAll -Install -AutoReboot:$false -ErrorAction SilentlyContinue
} catch {
    Write-Host "Nao foi possivel usar PSWindowsUpdate. Tentando via USOClient..." -ForegroundColor DarkYellow
    UsoClient StartScan
    Start-Sleep -Seconds 10
    UsoClient StartDownload
    Start-Sleep -Seconds 10
    UsoClient StartInstall
}

# -----------------------------------------------------
# 8. Atualizar apps da Microsoft Store
# -----------------------------------------------------
Step 8 $total "Atualizando apps da Microsoft Store..."
try {
    Get-CimInstance -Namespace "root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName UpdateScanMethod -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Verificacao de updates da Store disparada." -ForegroundColor Green
} catch {
    Write-Host "Nao foi possivel forcar update da Store automaticamente. Abra a Store e clique em 'Obter atualizacoes' manualmente." -ForegroundColor DarkYellow
}

# -----------------------------------------------------
# 9. Reparar .NET Framework
# -----------------------------------------------------
Step 9 $total "Verificando .NET Framework..."
Write-Host "Habilitando .NET Framework 3.5 e 4.8 (caso nao estejam ativos)..." -ForegroundColor Gray
Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart -ErrorAction SilentlyContinue | Out-Null
Enable-WindowsOptionalFeature -Online -FeatureName NetFx4-AdvSrvs -All -NoRestart -ErrorAction SilentlyContinue | Out-Null

# -----------------------------------------------------
# 10. Reset de rede (corrige problemas de conexao/DNS)
# -----------------------------------------------------
Step 10 $total "Resetando componentes de rede..."
ipconfig /flushdns | Out-Null
netsh int ip reset | Out-Null
Write-Host "Cache DNS limpo e stack IP resetado." -ForegroundColor Green

# -----------------------------------------------------
# 11. Verificar e agendar CHKDSK se necessario
# -----------------------------------------------------
Step 11 $total "Verificando integridade do disco (CHKDSK, somente leitura)..."
chkdsk C:

# -----------------------------------------------------
# 12. Verificar drivers desatualizados/com erro
# -----------------------------------------------------
Step 12 $total "Verificando dispositivos com problema de driver..."
$badDevices = Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }
if ($badDevices) {
    $badDevices | Select-Object Name, DeviceID, ConfigManagerErrorCode | Format-Table -AutoSize
    Write-Host "Dispositivos acima tem erro. Va em Gerenciador de Dispositivos e atualize manualmente." -ForegroundColor DarkYellow
} else {
    Write-Host "Nenhum dispositivo com erro de driver." -ForegroundColor Green
}

# -----------------------------------------------------
# 13. Ajuste de energia: desativar PCIe Link State Power Management
#     (reduz erros corrigidos de PCIe / hiccups de ASPM)
# -----------------------------------------------------
Step 13 $total "Ajustando PCIe Link State Power Management (reduz hiccups de GPU)..."
try {
    $activeScheme = (powercfg /getactivescheme) -replace '.*: ([a-f0-9-]+).*', '$1'
    powercfg /setacvalueindex $activeScheme SUB_PCIEXPRESS ASPM 0
    powercfg /setdcvalueindex $activeScheme SUB_PCIEXPRESS ASPM 0
    powercfg /setactive $activeScheme
    Write-Host "PCIe Link State Power Management desativado no plano ativo." -ForegroundColor Green
} catch {
    Write-Host "Nao foi possivel ajustar via powercfg. Faca manualmente: Painel de Controle > Opcoes de Energia > Configuracoes avancadas > PCI Express." -ForegroundColor DarkYellow
}

# -----------------------------------------------------
# 14. Limpeza de arquivos temporarios e cache de update
# -----------------------------------------------------
Step 14 $total "Limpando arquivos temporarios..."
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Temporarios limpos." -ForegroundColor Green

# -----------------------------------------------------
# 15. Resumo final + reinicio do Explorer
# -----------------------------------------------------
Step 15 $total "Finalizando..."
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe

Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host "  MANUTENCAO CONCLUIDA" -ForegroundColor Cyan
Write-Host "  Log completo: $logFile" -ForegroundColor Cyan
Write-Host "" -ForegroundColor Cyan
Write-Host "  RECOMENDADO: reinicie o PC agora para aplicar" -ForegroundColor Cyan
Write-Host "  tudo corretamente (Windows Update, .NET, DISM)." -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

Stop-Transcript
