param([switch]$SemInternet,[switch]$NaoPausar)

$ErrorActionPreference = 'Continue'
$LogDir = Join-Path $PSScriptRoot 'LOGS\VALIDACAO'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir ("Validacao_{0}_{1}.log" -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd_HHmmss'))
$Results = New-Object System.Collections.Generic.List[object]

function Add-ValidationResult {
    param([string]$Area,[string]$Item,[string]$Status,[string]$Details)
    $Results.Add([pscustomobject]@{Area=$Area;Item=$Item;Status=$Status;Detalhes=$Details})
    $Color = switch ($Status) { 'OK' {'Green'} 'ATENCAO' {'Yellow'} 'ERRO' {'Red'} default {'Gray'} }
    Write-Host ("[{0}] {1} - {2}: {3}" -f $Status,$Area,$Item,$Details) -ForegroundColor $Color
}

function Test-WebEndpoint {
    param([string]$Name,[string]$Url)
    $Request = $null
    $Response = $null
    try {
        $Request = [Net.HttpWebRequest]::Create($Url)
        $Request.Method = 'HEAD'
        $Request.AllowAutoRedirect = $true
        $Request.Timeout = 15000
        $Request.ReadWriteTimeout = 15000
        $Request.UserAgent = 'Uniware-Validator/0.3.28'
        $Response = $Request.GetResponse()
        $Code = [int]$Response.StatusCode
        $Length = $Response.ContentLength
        Add-ValidationResult 'Internet' $Name 'OK' ("HTTP {0}; tamanho informado: {1}" -f $Code,$Length)
    } catch {
        $HttpResponse = $_.Exception.Response
        if ($null -ne $HttpResponse -and [int]$HttpResponse.StatusCode -eq 405) {
            Add-ValidationResult 'Internet' $Name 'ATENCAO' 'Servidor acessivel, mas nao aceita teste HEAD; validar pelo download.'
        } else {
            Add-ValidationResult 'Internet' $Name 'ERRO' $_.Exception.Message
        }
    } finally {
        if ($null -ne $Response) { $Response.Close() }
        if ($null -ne $Request) { try { $Request.Abort() } catch {} }
    }
}

Clear-Host
Write-Host '===============================================================' -ForegroundColor DarkCyan
Write-Host '        VALIDACAO DO AMBIENTE UNIWARE v0.3.28                  ' -ForegroundColor White -BackgroundColor DarkCyan
Write-Host '===============================================================' -ForegroundColor DarkCyan
Write-Host 'Este diagnostico somente consulta configuracoes e conectividade.' -ForegroundColor Gray
Write-Host ''

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
$IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Add-ValidationResult 'Windows' 'Administrador' $(if($IsAdmin){'OK'}else{'ATENCAO'}) $(if($IsAdmin){'Console elevado.'}else{'Execute o BAT como administrador para testar todas as funcoes.'})
try {
    $OperatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $OperatingSystemText = '{0} {1}' -f $OperatingSystem.Caption,$OperatingSystem.Version
} catch {
    $OperatingSystemText = [Environment]::OSVersion.VersionString
}
Add-ValidationResult 'Windows' 'Sistema' 'INFO' $OperatingSystemText
Add-ValidationResult 'Windows' 'PowerShell' $(if($PSVersionTable.PSVersion.Major -ge 5){'OK'}else{'ERRO'}) $PSVersionTable.PSVersion.ToString()

$Spooler = Get-Service Spooler -ErrorAction SilentlyContinue
if ($null -eq $Spooler) {
    Add-ValidationResult 'Impressao' 'Spooler' 'ERRO' 'Servico nao encontrado.'
} else {
    Add-ValidationResult 'Impressao' 'Spooler' $(if($Spooler.Status -eq 'Running'){'OK'}else{'ERRO'}) ("Estado: {0}; inicio: {1}" -f $Spooler.Status,$Spooler.StartType)
}

foreach ($ModuleName in @('PrintManagement','NetSecurity')) {
    $Available = $null -ne (Get-Module -ListAvailable -Name $ModuleName | Select-Object -First 1)
    Add-ValidationResult 'PowerShell' $ModuleName $(if($Available){'OK'}else{'ATENCAO'}) $(if($Available){'Modulo disponivel.'}else{'Modulo nao encontrado nesta edicao do Windows.'})
}

$Winget = Get-Command winget.exe -ErrorAction SilentlyContinue
Add-ValidationResult 'Windows' 'Winget' $(if($Winget){'OK'}else{'ATENCAO'}) $(if($Winget){$Winget.Source}else{'Nao instalado; use a opcao Winget do utilitario.'})

try {
    $Printers = @(Get-Printer -ErrorAction Stop | Sort-Object Name)
    Add-ValidationResult 'Impressao' 'Filas instaladas' $(if($Printers.Count){'OK'}else{'ATENCAO'}) ("Quantidade: {0}" -f $Printers.Count)
    foreach ($Printer in $Printers) {
        $Kind = 'Local/indefinida'
        $ConnectionTest = 'Nao aplicavel'
        if ($Printer.Name -like '\\*' -or $Printer.PortName -like '\\*') {
            $Kind = 'Compartilhada'
        } elseif ($Printer.PortName -match '^USB\d+' -or $Printer.PortName -match '^COM\d+') {
            $Kind = 'USB/COM'
        } else {
            $Port = Get-PrinterPort -Name $Printer.PortName -ErrorAction SilentlyContinue
            if ($Port.PrinterHostAddress) {
                $Kind = 'Rede TCP/IP'
                $Open9100 = Test-NetConnection -ComputerName $Port.PrinterHostAddress -Port 9100 -InformationLevel Quiet -WarningAction SilentlyContinue
                $ConnectionTest = if ($Open9100) { 'TCP 9100 acessivel' } else { 'TCP 9100 indisponivel ou bloqueado' }
            }
        }
        $Status = if ($Printer.PrinterStatus -match 'Error|Offline|Paused') { 'ATENCAO' } else { 'OK' }
        Add-ValidationResult 'Fila' $Printer.Name $Status ("Tipo={0}; Driver={1}; Porta={2}; Estado={3}; Teste={4}" -f $Kind,$Printer.DriverName,$Printer.PortName,$Printer.PrinterStatus,$ConnectionTest)
    }
} catch {
    Add-ValidationResult 'Impressao' 'Consulta de filas' 'ERRO' $_.Exception.Message
}

if (-not $SemInternet) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Endpoints = @(
        @{Name='Unilab RustDesk';Url='https://uniware.com.br/updates/rustdesk/Unilab%20Rustdesk%20Windows.exe'},
        @{Name='Unilab Nuvem';Url='https://uniware.com.br/updates/cloud/Unilab-0.1.55-win.exe'},
        @{Name='Painel Lancador';Url='https://github.com/user-attachments/files/32448015/painel-lancador.zip'},
        @{Name='UniSenhas';Url='https://github.com/user-attachments/files/32447994/UniSenha_6.0.4.0.zip'},
        @{Name='UniCheckin';Url='https://github.com/user-attachments/files/32447996/UniCheckin_2.0.0.2.zip'},
        @{Name='TesteBotoeira';Url='https://github.com/user-attachments/files/32448016/TesteBotoeira.zip'},
        @{Name='Driver TOMATE MDK-20744';Url='https://github.com/user-attachments/files/32449230/TOMATE_MDK_20744BARCODE.driver.2024.01.05.1.zip'},
        @{Name='Driver Xprinter';Url='https://github.com/brandoncarmo94/Etiquetadoras/releases/download/Xprinters/Xprinter-ExpressDelivery_2023.2_M-4.zip'},
        @{Name='Zebra Setup Utilities';Url='https://www.zebra.com/content/dam/support-dam/en/driver/unrestricted/0002/zsu-1191327.zip'},
        @{Name='Winget';Url='https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'}
    )
    foreach ($Endpoint in $Endpoints) { Test-WebEndpoint -Name $Endpoint.Name -Url $Endpoint.Url }
} else {
    Add-ValidationResult 'Internet' 'Downloads' 'INFO' 'Testes ignorados pelo parametro -SemInternet.'
}

$Ok = @($Results | Where-Object Status -eq 'OK').Count
$Warnings = @($Results | Where-Object Status -eq 'ATENCAO').Count
$Errors = @($Results | Where-Object Status -eq 'ERRO').Count
$Results | Format-Table -AutoSize | Out-String -Width 260 | Set-Content -LiteralPath $LogFile -Encoding UTF8
Add-Content -LiteralPath $LogFile -Value ("Resumo: OK={0}; ATENCAO={1}; ERRO={2}" -f $Ok,$Warnings,$Errors) -Encoding UTF8

Write-Host ''
Write-Host ("Resumo: {0} OK, {1} atencoes, {2} erros." -f $Ok,$Warnings,$Errors) -ForegroundColor Cyan
Write-Host ("Relatorio: {0}" -f $LogFile) -ForegroundColor Cyan
if (-not $NaoPausar) { Read-Host 'Pressione ENTER para fechar' }
