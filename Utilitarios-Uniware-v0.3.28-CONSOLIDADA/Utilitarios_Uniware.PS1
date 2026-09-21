# =====================================================================
# UTILITARIOS UNIPRINT - SCRIPT COMPLETO DE CONFIGURACAO
# VERSAO INTEGRADA v0.3.29 TESTE - CONFIGURACAO E CALIBRACAO DE ETIQUETAS
# =====================================================================

param(
    [ValidateSet("Menu","ScanGraficas","ScanCupom","ScanLocais","Winget","Etiquetadoras","CalibrarEtiqueta","DriversCupom","DriversGraficas","UsuarioSpooler","RemoveUsers","Otimizacao","RemoverImpressora","RemoverDriver","RustDesk","DisableUAC","Firewall","UnilabNuvem","PainelSenhas","Rede")]
    [string]$Action = "Menu"
)

$ErrorActionPreference = "Continue"
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

# Mantem o console aberto se houver erro inesperado.
$Global:ErroFatal = $null

# Modulo de rede seguro: diagnostico, DNS e IP fixo com rollback automatico.
$NetworkModule = Join-Path $PSScriptRoot "Rede-Uniware.ps1"
if (Test-Path -LiteralPath $NetworkModule) {
    . $NetworkModule
}

Function Baixar-ArquivoComProgresso {
    param (
        [string]$Url,
        [string]$Destino
    )

    $Response = $null
    $Stream = $null
    $FileStream = $null
    $Failure = $null
    $Completed = $false

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $Request = [System.Net.HttpWebRequest]::Create($Url)
        $Request.UserAgent = $UserAgent
        $Request.Timeout = 60000
        $Request.ReadWriteTimeout = 60000
        $Request.AllowAutoRedirect = $true
        $Request.KeepAlive = $true
        $Request.Pipelined = $true
        $Request.ServicePoint.ConnectionLimit = 8
        $Request.ServicePoint.UseNagleAlgorithm = $false
        $Request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

        $Response = $Request.GetResponse()
        [int64]$TotalBytes = $Response.ContentLength
        $FileName = [System.IO.Path]::GetFileName($Destino)
        if ([string]::IsNullOrWhiteSpace($FileName)) { $FileName = "arquivo" }
        $DestinationDirectory = Split-Path -Parent $Destino
        if ($DestinationDirectory -and -not (Test-Path -LiteralPath $DestinationDirectory)) {
            New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
        }

        $FormatSize = {
            param([double]$Bytes)
            if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
            if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
            if ($Bytes -ge 1KB) { return ("{0:N1} KB" -f ($Bytes / 1KB)) }
            return ("{0:N0} B" -f $Bytes)
        }

        $DisplayName = $FileName
        if ($DisplayName.Length -gt 18) {
            $DisplayName = $DisplayName.Substring(0,15) + "..."
        }

        $WriteProgressLine = {
            param(
                [string]$Text,
                [System.ConsoleColor]$Color,
                [bool]$FinishLine
            )

            try {
                $LineWidth = [Math]::Max(40,[Math]::Min(115,[Console]::WindowWidth - 1))
            } catch {
                $LineWidth = 100
            }
            if ($Text.Length -gt $LineWidth) {
                $Text = $Text.Substring(0,$LineWidth)
            }
            $Text = $Text.PadRight($LineWidth)

            $PreviousColor = [Console]::ForegroundColor
            try {
                [Console]::ForegroundColor = $Color
                if ($FinishLine) {
                    [Console]::WriteLine("`r" + $Text)
                } else {
                    [Console]::Write("`r" + $Text)
                }
            } finally {
                [Console]::ForegroundColor = $PreviousColor
            }
        }

        $Stream = $Response.GetResponseStream()
        $BufferSize = 1MB
        $FileStream = [System.IO.FileStream]::new(
            $Destino,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            $BufferSize,
            [System.IO.FileOptions]::SequentialScan
        )

        $Buffer = New-Object byte[] $BufferSize
        $BytesRead = 0
        [int64]$TotalBytesRead = 0
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $LastUpdateMs = -1000
        $Spinner = @('|','/','-','\')
        $SpinnerIndex = 0
        $BarWidth = 24

        while (($BytesRead = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            $FileStream.Write($Buffer, 0, $BytesRead)
            $TotalBytesRead += $BytesRead

            if (($Stopwatch.ElapsedMilliseconds - $LastUpdateMs) -ge 250) {
                $LastUpdateMs = $Stopwatch.ElapsedMilliseconds
                $ElapsedSeconds = [Math]::Max(0.001,$Stopwatch.Elapsed.TotalSeconds)
                $Speed = $TotalBytesRead / $ElapsedSeconds
                if ($TotalBytes -gt 0) {
                    $Percent = [Math]::Min(100,[Math]::Floor(($TotalBytesRead / $TotalBytes) * 100))
                    $Filled = [Math]::Min($BarWidth,[Math]::Floor(($Percent / 100) * $BarWidth))
                    $Bar = ('#' * $Filled) + ('-' * ($BarWidth - $Filled))
                    $Line = "{0} [{1}] {2,3}% | {3} / {4} | {5}/s" -f $DisplayName,$Bar,$Percent,(& $FormatSize $TotalBytesRead),(& $FormatSize $TotalBytes),(& $FormatSize $Speed)
                } else {
                    $Line = "{0} [{1}] | {2} baixados | {3}/s" -f $DisplayName,$Spinner[$SpinnerIndex % $Spinner.Count],(& $FormatSize $TotalBytesRead),(& $FormatSize $Speed)
                    $SpinnerIndex++
                }
                & $WriteProgressLine $Line ([ConsoleColor]::Yellow) $false
            }
        }
        $Stopwatch.Stop()
        $ElapsedSeconds = [Math]::Max(0.001,$Stopwatch.Elapsed.TotalSeconds)
        $AverageSpeed = $TotalBytesRead / $ElapsedSeconds
        if ($TotalBytes -gt 0) {
            $FinalBar = '#' * $BarWidth
            $FinalLine = "{0} [{1}] 100% | {2} / {3} | {4}/s | {5:N1}s" -f $DisplayName,$FinalBar,(& $FormatSize $TotalBytesRead),(& $FormatSize $TotalBytes),(& $FormatSize $AverageSpeed),$Stopwatch.Elapsed.TotalSeconds
        } else {
            $FinalLine = "{0} [OK] | {1} baixados | {2}/s | {3:N1}s" -f $DisplayName,(& $FormatSize $TotalBytesRead),(& $FormatSize $AverageSpeed),$Stopwatch.Elapsed.TotalSeconds
        }
        & $WriteProgressLine $FinalLine ([ConsoleColor]::Green) $true
        $Completed = $true
    } catch {
        $Failure = $_
        if ($WriteProgressLine) {
            & $WriteProgressLine ("[ERRO] Falha no download: " + $_.Exception.Message) ([ConsoleColor]::Red) $true
        } else {
            Write-Host ("[ERRO] Falha no download: " + $_.Exception.Message) -ForegroundColor Red
        }
    } finally {
        if ($FileStream) { $FileStream.Close(); $FileStream.Dispose() }
        if ($Stream) { $Stream.Close(); $Stream.Dispose() }
        if ($Response) { $Response.Close(); $Response.Dispose() }
        if (-not $Completed -and (Test-Path -LiteralPath $Destino)) {
            Remove-Item -LiteralPath $Destino -Force -ErrorAction SilentlyContinue
        }
    }
    if ($Failure) {
        throw $Failure
    }
}

# ---------------------------------------------------------------------
# FUNCAO AUXILIAR: DOWNLOAD E EXECUCAO DE DRIVERS (.EXE OU .ZIP)
# ---------------------------------------------------------------------
Function Baixar-E-Executar {
    param (
        [string]$NomeMarca,
        [string]$UrlDownload,
        [string]$Extensao = ".exe"
    )

    if (-not $UrlDownload -or $UrlDownload -like "*seu-link*") {
        Write-Host "[-] URL de download para $NomeMarca ainda nao foi configurada no script." -ForegroundColor Yellow
        return
    }

    Write-Host "`nIniciando download do driver $NomeMarca..." -ForegroundColor Cyan
    
    if ($UrlDownload -like "*.zip*") {
        $Extensao = ".zip"
    }

    $ArquivoDestino = "$env:TEMP\Driver_$NomeMarca$Extensao"

    try {
        Baixar-ArquivoComProgresso -Url $UrlDownload -Destino $ArquivoDestino
        
        if ($Extensao -eq ".zip") {
            Write-Host "Extraindo conteudo do ZIP..." -ForegroundColor Green
            $PastaExtracao = "$env:TEMP\Extraido_$NomeMarca"
            if (Test-Path $PastaExtracao) { Remove-Item $PastaExtracao -Recurse -Force }
            Expand-Archive -Path $ArquivoDestino -DestinationPath $PastaExtracao -Force
            
            $Instalador = Get-ChildItem -Path $PastaExtracao -Recurse -Include *.exe, *.msi | Select-Object -First 1
            if ($Instalador) {
                Write-Host "Iniciando instalador: $($Instalador.Name)..." -ForegroundColor Yellow
                Start-Process -FilePath $Instalador.FullName
            } else {
                Write-Host "[-] Nenhum executavel (.exe/.msi) encontrado dentro do arquivo ZIP." -ForegroundColor Red
            }
        } else {
            Write-Host "Iniciando instalador..." -ForegroundColor Yellow
            Start-Process -FilePath $ArquivoDestino
        }
    } catch {
        Write-Host "[-] Erro ao processar driver ${NomeMarca}" -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------
# OPCOES 01/02: SCANNER DE REDE (GRAFICAS x CUPOM) E ADICAO DE IMPRESSORA
# ---------------------------------------------------------------------
Function Buscar-ImpressorasNaRede {
    param (
        [string]$TipoBusca,
        [array]$PortasTeste
    )

    $LocalIPInfo = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.InterfaceAlias -notmatch 'Loopback|vEthernet' -and $_.IPAddress -notlike '169.254.*' 
    } | Select-Object -First 1

    $RedesParaEscanear = @("10.1.0", "192.168.0", "192.168.1", "10.0.0")
    
    if ($LocalIPInfo) {
        $AutoSubnet = ($LocalIPInfo.IPAddress -split '\.')[0..2] -join '.'
        Write-Host "`n[+] IP Local identificado: $($LocalIPInfo.IPAddress)" -ForegroundColor Cyan
        
        if ($AutoSubnet -notin $RedesParaEscanear) {$RedesParaEscanear = @($AutoSubnet) + $RedesParaEscanear
        }
    }

    Write-Host "`n[Redes Padrao configuradas: $($RedesParaEscanear -join ', ')]" -ForegroundColor Gray
    Write-Host "-> Aperte ENTER para escanear TODAS as redes padrao acima." -ForegroundColor White
    Write-Host "-> OU digite apenas os 3 blocos de uma rede especifica (ex: 172.16.2):" -ForegroundColor White
    
    $InputSubnet = Read-Host "Sua escolha"
    
    if (-not [string]::IsNullOrWhiteSpace($InputSubnet)) {
        $RedesParaEscanear = @($InputSubnet)
    }

    $Encontradas = New-Object System.Collections.Generic.List[PSCustomObject]

    foreach ($Subnet in $RedesParaEscanear) {
        Write-Host "`n[+] Varrendo rede $Subnet.1 ate 254 ($TipoBusca)..." -ForegroundColor Cyan

        for ($i = 1; $i -le 254; $i++) {$TargetIP = "$Subnet.$i"

            $Percentual = [math]::Round(($i / 254) * 100)
            Write-Progress -Activity "Buscando Impressoras ($TipoBusca)" -Status "Rede: $Subnet.X | Testando: $TargetIP" -PercentComplete $Percentual

            foreach ($P in $PortasTeste) {
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $connect = $tcp.BeginConnect($TargetIP,$P.Porta, $null,$null)
                    $success = $connect.AsyncWaitHandle.WaitOne([timespan]::FromMilliseconds(75)) 
                    
                    if ($success) {
                        $tcp.EndConnect($connect)
                        $NomeExibicao = $P.Nome
                        $ModeloIdentificado = ""

                        if ($P.Porta -eq 80) {
                            try {
                                $Web = Invoke-WebRequest -Uri "http://$TargetIP" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
                                if ($Web.Content -match '(?i)<title>(.*?)</title>') {
                                    $NomeReal = $matches[1].Trim()
                                    if ($NomeReal -match "Zebra|Epson|Elgin|Printer|Print|ZDesigner|TM-") {
                                        $ModeloIdentificado = $NomeReal
                                    }
                                }
                            } catch { }
                        }

                        $TextoModelo = if ($ModeloIdentificado) { " -> Modelo: [$ModeloIdentificado]" } else { "" }
                        Write-Host "[!] Possivel impressora no IP: $TargetIP - Via $NomeExibicao$TextoModelo" -ForegroundColor Green

                        $Encontradas.Add([PSCustomObject]@{
                            IP     = $TargetIP
                            Porta  = $NomeExibicao
                            Modelo = $ModeloIdentificado
                        })

                        $tcp.Close()
                        break 
                    }
                    $tcp.Close()
                } catch { }
            }
        }
        Write-Progress -Activity "Buscando Impressoras ($TipoBusca)" -Completed
    }
    
    Write-Host "`nVarredura concluida! $($Encontradas.Count) dispositivo(s) localizado(s)." -ForegroundColor Yellow
    return $Encontradas
}

Function Selecionar-EInstalar {
    param ($Dispositivos)

    if (-not $Dispositivos -or $Dispositivos.Count -eq 0) {
        Write-Host "`nNenhuma impressora encontrada nesta varredura." -ForegroundColor Yellow
        return
    }

    Write-Host "`n-------------------------------------------------" -ForegroundColor Cyan
    Write-Host " IMPRESSORAS ENCONTRADAS NA VARREDURA" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    for ($idx = 0; $idx -lt $Dispositivos.Count; $idx++) {
        $D = $Dispositivos[$idx]
        $Extra = if ($D.Modelo) { " -> Modelo: [$($D.Modelo)]" } else { "" }
        Write-Host " [$($idx + 1)] $($D.IP) - $($D.Porta)$Extra"
    }
    Write-Host " [0] Nao instalar nenhuma / Voltar" -ForegroundColor Gray
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan

    $Escolha = Read-Host "Digite o numero da impressora para instalar (varias: 1,3,4) ou 0 para voltar"

    if ([string]::IsNullOrWhiteSpace($Escolha) -or $Escolha.Trim() -eq "0") {
        return
    }

    $Numeros = $Escolha -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }

    foreach ($NumStr in $Numeros) {
        $Num = [int]$NumStr
        if ($Num -ge 1 -and $Num -le $Dispositivos.Count) {
            $Alvo = $Dispositivos[$Num - 1]
            $ModeloParaBusca = if ($Alvo.Modelo) { $Alvo.Modelo } else { $Alvo.Porta }
            Instalar-ImpressoraTCP -IP $Alvo.IP -Modelo $ModeloParaBusca
        } else {
            Write-Host "[-] Numero invalido: $NumStr" -ForegroundColor Red
        }
    }
}

# ---------------------------------------------------------------------
# OPCAO 01: SCANNER DE REDE E INSTALACAO AUTOMATICA (Graficas)
# ---------------------------------------------------------------------
Function Scan-Rede-Graficas {
    Write-Host "`n[+] Iniciando varredura de impressoras graficas na rede..." -ForegroundColor Cyan
    
    $PortasTeste = @(80, 443, 9100, 631, 515)
    $LocalIPInfo = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.InterfaceAlias -notmatch 'Loopback|vEthernet' -and $_.IPAddress -notlike '169.254.*' 
    } | Select-Object -First 1

    $Subnet = "192.168.0"
    if ($LocalIPInfo) {
        $Subnet = ($LocalIPInfo.IPAddress -split '\.')[0..2] -join '.'
    }

    $InputSubnet = Read-Host "Digite a rede para varrer (Ex: 10.1.0 ou Enter para usar a atual [$Subnet])"
    if (-not [string]::IsNullOrWhiteSpace($InputSubnet)) {
        $Subnet = $InputSubnet
    }

    Write-Host "`n[+] Varrendo a rede $Subnet.1 ate 254..." -ForegroundColor Cyan
    $Encontradas = @()

    for ($i = 1; $i -le 254; $i++) {
        $TargetIP = "$Subnet.$i"
        $Percentual = [math]::Round(($i / 254) * 100)
        Write-Progress -Activity "Buscando Impressoras Graficas" -Status "Testando IP: $TargetIP" -PercentComplete $Percentual

        foreach ($Porta in $PortasTeste) {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connect = $tcp.BeginConnect($TargetIP, $Porta, $null, $null)
                $success = $connect.AsyncWaitHandle.WaitOne([timespan]::FromMilliseconds(50))
                
                if ($success) {
                    $tcp.EndConnect($connect)
                    $tcp.Close()
                    
                    if ($TargetIP -notin $Encontradas) {
                        Write-Host "[!] Impressora encontrada no IP: $TargetIP (Porta $Porta aberta)" -ForegroundColor Green
                        $Encontradas += $TargetIP
                    }
                    break
                }
                $tcp.Close()
            } catch { }
        }
    }
    Write-Progress -Activity "Buscando Impressoras Graficas" -Completed

    if ($Encontradas.Count -eq 0) {
        Write-Host "`n[-] Nenhuma impressora encontrada nesta faixa de rede." -ForegroundColor Yellow
        return
    }

    Write-Host "`n-------------------------------------------------" -ForegroundColor Cyan
    Write-Host " DISPOSITIVOS ENCONTRADOS:" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    for ($idx = 0; $idx -lt $Encontradas.Count; $idx++) {
        Write-Host " [$($idx + 1)] IP: $($Encontradas[$idx])" -ForegroundColor White
    }
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan

    $Escolha = Read-Host "Digite o numero do IP que deseja instalar (ou 0 para cancelar)"
    if ($Escolha -match '^\d+$' -and [int]$Escolha -gt 0 -and [int]$Escolha -le $Encontradas.Count) {
        $IPAlvo = $Encontradas[[int]$Escolha - 1]
        
        $DriversDisponiveis = Get-PrinterDriver | Select-Object -ExpandProperty Name | Sort-Object
        
        Write-Host "`n-------------------------------------------------" -ForegroundColor Cyan
        Write-Host " SELECIONE O DRIVER PARA O IP ${IPAlvo}:" -ForegroundColor Cyan
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
        for ($d = 0; $d -lt $DriversDisponiveis.Count; $d++) {
            Write-Host " [$($d + 1)]$($DriversDisponiveis[$d])" -ForegroundColor White
        }
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan

        $DriverEscolha = Read-Host "Digite o numero do driver desejado"
        if ($DriverEscolha -match '^\d+$' -and [int]$DriverEscolha -le $DriversDisponiveis.Count) {
            $DriverSelecionado = $DriversDisponiveis[[int]$DriverEscolha - 1]
            $NomeFila = Read-Host "Digite o nome para a impressora de rede (ex: Epson L4260)"
            if ([string]::IsNullOrWhiteSpace($NomeFila)) { $NomeFila = "Impressora_$IPAlvo" }

            try {
                $NomePorta = "IP_$IPAlvo"
                if (-not (Get-PrinterPort -Name $NomePorta -ErrorAction SilentlyContinue)) {
                    Add-PrinterPort -Name $NomePorta -PrinterHostAddress $IPAlvo -PortNumber 9100
                }
                Add-Printer -Name $NomeFila -DriverName $DriverSelecionado -PortName $NomePorta
                Write-Host "`n[SUCESSO] Impressora '$NomeFila' instalada com sucesso na rede!" -ForegroundColor Green
            } catch {
                Write-Host "[-] Erro ao instalar a impressora: $_" -ForegroundColor Red
            }
        }
    }
}

# ---------------------------------------------------------------------
# OPCAO 02: SCANNER DE REDE E INSTALACAO AUTOMATICA (Cupom)
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
# DETECTOR EPSON TM - RAW 9100 / ESC-POS
# Retorna objeto somente quando ha evidencia util.
# ---------------------------------------------------------------------
Function Test-TMRaw9100 {
    param(
        [Parameter(Mandatory=$true)][string]$IP,
        [int]$Tentativas = 3
    )

    $resultado = [ordered]@{
        IP         = $IP
        Porta9100  = $false
        Fabricante = ""
        Modelo     = ""
        Origem     = ""
        Evidencia  = ""
        Confianca  = "BAIXA"
    }

    for ($tentativa = 1; $tentativa -le $Tentativas; $tentativa++) {
        $client = $null
        $stream = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $waitMs = 350 + (($tentativa - 1) * 250)
            $ar = $client.BeginConnect($IP, 9100, $null, $null)
            if (-not $ar.AsyncWaitHandle.WaitOne($waitMs)) {
                try { $client.Close() } catch {}
                Start-Sleep -Milliseconds 80
                continue
            }
            $client.EndConnect($ar)
            $resultado.Porta9100 = $true

            $stream = $client.GetStream()
            $stream.ReadTimeout = 900
            $stream.WriteTimeout = 900

            # ESC/POS GS I 67 - printer model ID. Foi o comando que
            # identificou "_TM-T20" nos testes anteriores.
            $cmd = [byte[]](0x1D,0x49,0x43)
            $stream.Write($cmd,0,$cmd.Length)
            $stream.Flush()
            Start-Sleep -Milliseconds 180

            $buffer = New-Object byte[] 128
            $count = 0
            try { $count = $stream.Read($buffer,0,$buffer.Length) } catch {}

            if ($count -gt 0) {
                $ascii = [Text.Encoding]::ASCII.GetString($buffer,0,$count)
                $clean = ($ascii -replace '[^\x20-\x7E]','').Trim([char]0).Trim()
                $clean = $clean.TrimStart('_').Trim()

                if ($clean -match '(?i)(TM-[A-Z0-9\-]+)') {
                    $resultado.Fabricante = "EPSON"
                    $resultado.Modelo = $matches[1].ToUpper()
                    $resultado.Origem = "ESC/POS GS I 67"
                    $resultado.Evidencia = $ascii.Trim()
                    $resultado.Confianca = "ALTA"
                    return [PSCustomObject]$resultado
                }
            }

            # Porta RAW respondeu, mas sem modelo. Ainda e evidencia de servico RAW.
            $resultado.Origem = "RAW 9100"
            $resultado.Evidencia = "Porta 9100 respondeu; GS I 67 sem identificacao de modelo."
            $resultado.Confianca = "MEDIA"
            return [PSCustomObject]$resultado
        } catch {
            Start-Sleep -Milliseconds 80
        } finally {
            if ($stream) { try { $stream.Dispose() } catch {} }
            if ($client) { try { $client.Close() } catch {} }
        }
    }

    return [PSCustomObject]$resultado
}

Function Get-TMWebEvidence {
    param([Parameter(Mandatory=$true)][string]$IP)
    try {
        $web = Invoke-WebRequest -Uri "http://$IP" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        $title = ""
        if ($web.Content -match '(?is)<title[^>]*>(.*?)</title>') {
            $title = (($matches[1] -replace '\s+',' ').Trim())
        }
        $sample = (($title + " " + $web.Content.Substring(0,[Math]::Min(2500,$web.Content.Length))) -replace '\s+',' ')
        if ($sample -match '(?i)EPSON|TMNet|TM-[A-Z0-9\-]+') {
            $model = ""
            if ($sample -match '(?i)(TM-[A-Z0-9\-]+)') { $model = $matches[1].ToUpper() }
            return [PSCustomObject]@{
                Confirmado = $true
                Fabricante = "EPSON"
                Modelo = $model
                Evidencia = $(if($title){$title}else{"Painel web Epson/TMNet"})
            }
        }
    } catch {}
    return [PSCustomObject]@{Confirmado=$false;Fabricante="";Modelo="";Evidencia=""}
}



Function Get-EpsonTMDriver {
    param([string]$Modelo)

    $drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue)

    # Primeiro tenta casar Epson + familia TM/modelo detectado.
    $modeloBase = ($Modelo -replace '(?i)^EPSON\s*','').Trim()
    $tokens = @($modeloBase, ($modeloBase -replace '-',' '), 'EPSON TM', 'EPSON Advanced Printer Driver')

    foreach($token in $tokens) {
        if([string]::IsNullOrWhiteSpace($token)){continue}
        $match = $drivers | Where-Object {
            $_.Name -match '(?i)EPSON' -and $_.Name -like "*$token*"
        } | Select-Object -First 1
        if($match){ return $match }
    }

    # APD pode registrar nomes variados; aceita Epson TM instalado,
    # mas nunca retorna drivers genericos Microsoft/HP/etc.
    return ($drivers | Where-Object {
        $_.Name -match '(?i)EPSON' -and $_.Name -match '(?i)TM|Advanced Printer'
    } | Select-Object -First 1)
}

Function Ensure-EpsonTMDriver {
    param([Parameter(Mandatory=$true)][PSCustomObject]$Dispositivo)

    $drv = Get-EpsonTMDriver -Modelo $Dispositivo.Modelo
    if($drv){
        Write-Host "[+] Driver Epson encontrado: $($drv.Name)" -ForegroundColor Green
        return $true
    }

    Write-Host ""
    Write-Host "[!] Driver Epson TM nao encontrado neste computador." -ForegroundColor Yellow
    Write-Host "    Modelo detectado: $($Dispositivo.Modelo)" -ForegroundColor White
    Write-Host "    O Utilitario nao exibira drivers genericos do Windows." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Abrindo o Epson Download Center - Advanced Printer Driver (APD)..." -ForegroundColor Cyan

    # Pagina oficial Epson Brasil da TM-T20 detectada.
    $url = "https://download-center.epson.com/download/?module_id=daebc581-b625-43b1-a459-aac2c557bbf1%3A5.13E&device_id=TM-T20&os=WIN1164&region=BR&language=pt"
    try { Start-Process $url } catch {
        Write-Host "[!] Nao foi possivel abrir o navegador automaticamente." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Instale o EPSON Advanced Printer Driver (APD) pelo navegador." -ForegroundColor White
    Write-Host "Quando terminar a instalacao, volte para esta janela." -ForegroundColor White

    while($true){
        $acao = Read-Host "[ENTER] verificar novamente | [C] cancelar"
        if($acao -match '^(?i)c'){ return $false }

        Start-Sleep -Milliseconds 500
        $drv = Get-EpsonTMDriver -Modelo $Dispositivo.Modelo
        if($drv){
            Write-Host "[+] Driver Epson detectado: $($drv.Name)" -ForegroundColor Green
            return $true
        }

        Write-Host "[!] Driver Epson TM ainda nao foi localizado." -ForegroundColor Yellow
        $abrir = Read-Host "Abrir novamente o suporte Epson? [S/N]"
        if($abrir -match '^(?i)s'){ try { Start-Process $url } catch {} }
    }
}

Function Confirmar-InstalacaoImediataCupom {
    param([Parameter(Mandatory=$true)][PSCustomObject]$Dispositivo)

    Write-Host ""
    Write-Host "-------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " IMPRESSORA IDENTIFICADA COM ALTA CONFIABILIDADE" -ForegroundColor Green
    Write-Host " IP          : $($Dispositivo.IP)" -ForegroundColor White
    Write-Host " Fabricante  : $($Dispositivo.Fabricante)" -ForegroundColor White
    Write-Host " Modelo      : $($Dispositivo.Modelo)" -ForegroundColor White
    Write-Host " Origem      : $($Dispositivo.Origem)" -ForegroundColor Gray
    Write-Host "-------------------------------------------------------------" -ForegroundColor Cyan

    $instalar = Read-Host "Deseja instalar esta impressora agora? [S/N]"
    if($instalar -match '^(?i)s') {
        $ehEpsonTM = ($Dispositivo.Fabricante -match '^(?i)EPSON$' -and $Dispositivo.Modelo -match '^(?i)TM-')

        if($ehEpsonTM) {
            if(Ensure-EpsonTMDriver -Dispositivo $Dispositivo) {
                # Agora ha driver Epson instalado. O instalador existente pode
                # prosseguir sem oferecer Microsoft/HP/PDF como alternativa.
                Selecionar-EInstalar -Dispositivos @($Dispositivo)
            } else {
                Write-Host "[!] Instalacao da $($Dispositivo.Modelo) cancelada." -ForegroundColor Yellow
            }
        } else {
            Selecionar-EInstalar -Dispositivos @($Dispositivo)
        }

        $continuar = Read-Host "Deseja continuar procurando outras impressoras? [S/N]"
        if($continuar -notmatch '^(?i)s') { return $false }
    }
    return $true
}

Function Scan-Rede-CupomCorrigido {
    $LocalIPInfo = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceAlias -notmatch 'Loopback|vEthernet' -and $_.IPAddress -notlike '169.254.*'
    } | Select-Object -First 1

    $Redes = @("10.1.2","10.1.0","192.168.0","192.168.1","10.0.0")
    if ($LocalIPInfo) {
        $auto = ($LocalIPInfo.IPAddress -split '\.')[0..2] -join '.'
        if ($auto -notin $Redes) { $Redes = @($auto) + $Redes }
        Write-Host "`n[+] IP Local identificado: $($LocalIPInfo.IPAddress)" -ForegroundColor Cyan
    }

    Write-Host "`n[Redes Padrao configuradas: $($Redes -join ', ')]" -ForegroundColor Gray
    Write-Host "-> ENTER = escanear todas; ou informe somente a rede (ex: 10.1.0)." -ForegroundColor White
    $entrada = Read-Host "Sua escolha"
    if (-not [string]::IsNullOrWhiteSpace($entrada)) { $Redes = @($entrada.Trim().TrimEnd('.')) }

    $achadas = [System.Collections.Generic.List[PSCustomObject]]::new()

    # v0.3.4: o lote inteiro compartilha UMA janela de espera.
    $Throttle = 25
    $JanelaLoteMs = 300
    $IntervaloPollingMs = 10

    foreach ($subnet in $Redes) {
        $relogioRede=[Diagnostics.Stopwatch]::StartNew()
        Write-Host "`n[+] Varrendo rede $subnet.1 ate 254 (Cupom/TM)..." -ForegroundColor Cyan
        Write-Host "    Scanner: 25 IPs simultaneos | janela maxima por lote: ${JanelaLoteMs}ms" -ForegroundColor DarkGray

        $prioritarios=@()
        try {
            $prioritarios=Get-PrinterPort -ErrorAction SilentlyContinue |
                Where-Object { $_.PrinterHostAddress -like "$subnet.*" } |
                Select-Object -ExpandProperty PrinterHostAddress -Unique
        } catch {}

        $todos=1..254 | ForEach-Object { "$subnet.$_" }
        $fila=@($prioritarios)+@($todos | Where-Object { $_ -notin $prioritarios })
        $candidatos=[System.Collections.Generic.List[string]]::new()
        $processados=0
        $totalLotes=[Math]::Ceiling($fila.Count / $Throttle)
        $loteNumero=0

        for($offset=0; $offset -lt $fila.Count; $offset += $Throttle) {
            $loteNumero++
            $fim=[Math]::Min($offset+$Throttle-1,$fila.Count-1)
            $lote=@($fila[$offset..$fim])
            $pendentes=[System.Collections.Generic.List[object]]::new()

            # Dispara todas as conexoes primeiro.
            foreach($ip in $lote) {
                $tcp=New-Object Net.Sockets.TcpClient
                try {
                    $ar=$tcp.BeginConnect($ip,9100,$null,$null)
                    $pendentes.Add([PSCustomObject]@{IP=$ip;Tcp=$tcp;AR=$ar;Finalizado=$false})
                } catch {
                    try{$tcp.Close()}catch{}
                }
            }

            # Uma unica janela de tempo para TODO o lote.
            $sw=[Diagnostics.Stopwatch]::StartNew()
            while($sw.ElapsedMilliseconds -lt $JanelaLoteMs) {
                $faltam=0
                foreach($t in $pendentes) {
                    if($t.Finalizado){continue}
                    if($t.AR.IsCompleted) {
                        try {
                            $t.Tcp.EndConnect($t.AR)
                            if($t.Tcp.Connected -and -not $candidatos.Contains($t.IP)) {
                                $candidatos.Add($t.IP)
                                Write-Host "[+] RAW 9100 encontrado: $($t.IP)" -ForegroundColor Green
                            }
                        } catch {}
                        $t.Finalizado=$true
                    } else {
                        $faltam++
                    }
                }
                if($faltam -eq 0){break}
                Start-Sleep -Milliseconds $IntervaloPollingMs
            }
            $sw.Stop()

            # Fecha tudo que terminou ou excedeu a janela.
            foreach($t in $pendentes) {
                try{$t.Tcp.Close()}catch{}
                try{$t.AR.AsyncWaitHandle.Close()}catch{}
            }

            $processados += $lote.Count
            Write-Progress -Activity "Buscando Impressoras de Cupom / Termicas" `
                -Status "Rede: $subnet.X | Lote $loteNumero/$totalLotes | $processados/$($fila.Count) | candidatos: $($candidatos.Count)" `
                -PercentComplete ([math]::Round(($processados/$fila.Count)*100))
        }
        Write-Progress -Activity "Buscando Impressoras de Cupom / Termicas" -Completed

        # Identificacao detalhada somente para os IPs que responderam RAW.
        foreach($ip in $candidatos) {
            Write-Host "    [>] Identificando $ip..." -ForegroundColor Cyan
            $raw=Test-TMRaw9100 -IP $ip -Tentativas 3
            $web=Get-TMWebEvidence -IP $ip

            $fab=$raw.Fabricante
            $modelo=$raw.Modelo
            $origem=$raw.Origem
            $evid=$raw.Evidencia
            $conf=$raw.Confianca

            if($modelo -match '^TM-') {
                $conf="ALTA"
            } elseif($web.Confirmado -and $raw.Porta9100) {
                if(-not $fab){$fab=$web.Fabricante}
                if(-not $modelo){$modelo=$web.Modelo}
                $origem="RAW 9100 + Painel Web"
                $evid=$web.Evidencia
                $conf="ALTA"
            } else {
                $conf="MEDIA"
            }

            $tipo=if($modelo -match '^TM-'){"EPSON $modelo"}elseif($fab){$fab}else{"Dispositivo RAW"}
            Write-Host "[+] $ip - $tipo | $origem | Confianca: $conf" -ForegroundColor Green

            $DispositivoEncontrado = [PSCustomObject]@{
                IP=$ip; Porta="RAW / Cupom"; Modelo=$(if($modelo){$modelo}else{$tipo})
                Fabricante=$fab; Origem=$origem; Evidencia=$evid; Confianca=$conf
            }
            $achadas.Add($DispositivoEncontrado)

            # Somente ALTA interrompe para perguntar. MEDIA continua automaticamente.
            if($conf -eq "ALTA") {
                $seguir = Confirmar-InstalacaoImediataCupom -Dispositivo $DispositivoEncontrado
                if(-not $seguir) {
                    $relogioRede.Stop()
                    $tr=$relogioRede.Elapsed
                    $tempoRede="{0:00}:{1:00}.{2:000}" -f [int]$tr.TotalMinutes,$tr.Seconds,$tr.Milliseconds
                    Write-Host "    Tempo da rede $subnet.X ate a interrupcao: $tempoRede" -ForegroundColor DarkCyan
                    Write-Host "`n[+] Pesquisa encerrada pelo usuario apos a instalacao." -ForegroundColor Yellow
                    return $achadas
                }
            }
        }

        $relogioRede.Stop()
        $tr=$relogioRede.Elapsed
        $tempoRede="{0:00}:{1:00}.{2:000}" -f [int]$tr.TotalMinutes,$tr.Seconds,$tr.Milliseconds
        Write-Host "    Tempo da rede $subnet.X: $tempoRede | candidatos: $($candidatos.Count)" -ForegroundColor DarkCyan

        if($candidatos.Count -eq 0) {
            Write-Host "[-] Nenhum equipamento RAW 9100 respondeu em $subnet.X." -ForegroundColor Yellow
        }
    }

    Write-Host "`nVarredura concluida! $($achadas.Count) candidato(s) RAW/Cupom localizado(s)." -ForegroundColor Yellow
    return $achadas
}

Function Scan-Rede-Cupom {
    $CronometroConsulta = [System.Diagnostics.Stopwatch]::StartNew()
    $Encontradas = Scan-Rede-CupomCorrigido
    $CronometroConsulta.Stop()

    $Tempo = $CronometroConsulta.Elapsed
    $TempoFormatado = "{0:00}:{1:00}.{2:000}" -f [int]$Tempo.TotalMinutes,$Tempo.Seconds,$Tempo.Milliseconds

    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host " TEMPO TOTAL DA CONSULTA DE REDE: $TempoFormatado" -ForegroundColor Cyan
    Write-Host " CANDIDATOS LOCALIZADOS: $(@($Encontradas).Count)" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Impressoras de confianca ALTA foram oferecidas durante a pesquisa." -ForegroundColor Gray
    Write-Host "Candidatos de confianca MEDIA foram apenas registrados." -ForegroundColor Gray
}

Function Install-Winget {
    Write-Host "`n[1/3] Encerrando processos da Microsoft Store e AppInstaller..." -ForegroundColor Cyan
    Get-Process -Name "AppInstaller", "WinStore.App", "winget" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "[2/3] Baixando a versao mais recente do Winget..." -ForegroundColor Cyan
    $Url = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $Destino = "$env:TEMP\winget.msixbundle"
    
    try {
        Baixar-ArquivoComProgresso -Url $Url -Destino $Destino
        Write-Host "[3/3] Instalando o pacote..." -ForegroundColor Cyan
        Add-AppxPackage -Path $Destino -ForceApplicationShutdown -ErrorAction Stop
        Write-Host "Winget instalado/atualizado com sucesso!" -ForegroundColor Green
    } catch {
        Write-Host "[-] Erro ao instalar o Winget: ${_}" -ForegroundColor Red
    }
}

Function Get-UniwareSuggestedPassword {
    # Ofuscacao simples para evitar que a senha padrao fique legivel no codigo.
    # Base64 nao deve ser tratado como criptografia.
    $EncodedPassword = "VW5pbGFiQDIwMjY="
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EncodedPassword))
}

Function Test-UniwareSecureStringEqual {
    param(
        [System.Security.SecureString]$First,
        [System.Security.SecureString]$Second
    )
    if (-not $First -or -not $Second -or $First.Length -ne $Second.Length) { return $false }
    $FirstPointer = [IntPtr]::Zero
    $SecondPointer = [IntPtr]::Zero
    $FirstText = $null
    $SecondText = $null
    try {
        $FirstPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($First)
        $SecondPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Second)
        $FirstText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($FirstPointer)
        $SecondText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($SecondPointer)
        return [string]::Equals($FirstText,$SecondText,[StringComparison]::Ordinal)
    } finally {
        if ($FirstPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($FirstPointer) }
        if ($SecondPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($SecondPointer) }
        $FirstText = $null
        $SecondText = $null
    }
}

Function Read-UniwareCustomPassword {
    Write-Host "A senha digitada nao sera exibida. Pressione ENTER sem digitar para cancelar." -ForegroundColor Gray
    for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
        $First = Read-Host "Digite a senha desejada" -AsSecureString
        if (-not $First -or $First.Length -eq 0) { return $null }
        $Second = Read-Host "Confirme a senha desejada" -AsSecureString
        if (-not $Second -or $Second.Length -eq 0) { return $null }
        if (Test-UniwareSecureStringEqual -First $First -Second $Second) {
            $Second.Dispose()
            return $First
        }
        Write-Host "As senhas nao conferem. Tentativa $Attempt de 3." -ForegroundColor Yellow
        $First.Dispose()
        $Second.Dispose()
    }
    Write-Host "Limite de tentativas atingido. Nenhuma alteracao foi realizada." -ForegroundColor Red
    return $null
}

Function Set-SpoolPrintersFullControl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Security.Principal.SecurityIdentifier]$UserSid,
        [string]$Path = (Join-Path $env:SystemRoot "System32\spool\PRINTERS")
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "A pasta do spooler nao foi encontrada: $Path"
    }

    $EveryoneSid = [System.Security.Principal.SecurityIdentifier]::new("S-1-1-0")
    $Inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $Propagation = [System.Security.AccessControl.PropagationFlags]::None
    $FullControl = [System.Security.AccessControl.FileSystemRights]::FullControl
    $Allow = [System.Security.AccessControl.AccessControlType]::Allow
    $Identities = @($UserSid,$EveryoneSid)

    $Acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    foreach ($IdentitySid in $Identities) {
        $Rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $IdentitySid,
            $FullControl,
            $Inheritance,
            $Propagation,
            $Allow
        )
        $Acl.SetAccessRule($Rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $Acl -ErrorAction Stop

    $ValidatedAcl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $Rules = @($ValidatedAcl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier]))
    $Results = foreach ($IdentitySid in $Identities) {
        $SidText = $IdentitySid.Value
        $MatchingRules = @($Rules | Where-Object {
            $_.IdentityReference.Value -eq $SidText -and
            $_.AccessControlType -eq $Allow -and
            ($_.FileSystemRights -band $FullControl) -eq $FullControl -and
            ($_.InheritanceFlags -band [System.Security.AccessControl.InheritanceFlags]::ContainerInherit) -ne 0 -and
            ($_.InheritanceFlags -band [System.Security.AccessControl.InheritanceFlags]::ObjectInherit) -ne 0
        })
        $DisplayName = $SidText
        try { $DisplayName = $IdentitySid.Translate([System.Security.Principal.NTAccount]).Value } catch {}
        [pscustomobject]@{
            Sid = $SidText
            Name = $DisplayName
            FullControlValidated = ($MatchingRules.Count -gt 0)
        }
    }

    $Failures = @($Results | Where-Object { -not $_.FullControlValidated })
    if ($Failures.Count -gt 0) {
        throw ("A validacao falhou para: " + (($Failures | ForEach-Object { $_.Name }) -join ', '))
    }
    return [pscustomobject]@{ Path=$Path; Identities=@($Results) }
}

Function Config-UsuarioSpool {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " USUARIO UNILABIMP / SPOOLER" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    try {
        $ExistingUser = Get-LocalUser -Name "Unilabimp" -ErrorAction SilentlyContinue
        $PasswordAction = $null
        $SecurePassword = $null
        $ShowSuggestedPassword = $false

        if ($ExistingUser) {
            Write-Host "O usuario 'Unilabimp' ja existe." -ForegroundColor Yellow
            Write-Host " 1 - Manter a senha atual"
            Write-Host " 2 - Redefinir usando a senha sugerida"
            Write-Host " 3 - Redefinir informando uma senha desejada"
            Write-Host " 0 - Cancelar"
            $Choice = (Read-Host "Selecione uma opcao").Trim()
            switch ($Choice) {
                "1" { $PasswordAction = "Keep" }
                "2" { $PasswordAction = "Suggested" }
                "3" { $PasswordAction = "Custom" }
                "0" { Write-Host "Operacao cancelada. Nenhuma alteracao foi realizada." -ForegroundColor Yellow; return }
                default { Write-Host "Opcao invalida. Nenhuma alteracao foi realizada." -ForegroundColor Red; return }
            }
        } else {
            Write-Host "O usuario 'Unilabimp' sera criado." -ForegroundColor Cyan
            Write-Host " 1 - Usar a senha sugerida"
            Write-Host " 2 - Informar uma senha desejada"
            Write-Host " 0 - Cancelar"
            $Choice = (Read-Host "Selecione uma opcao").Trim()
            switch ($Choice) {
                "1" { $PasswordAction = "Suggested" }
                "2" { $PasswordAction = "Custom" }
                "0" { Write-Host "Operacao cancelada. O usuario nao foi criado." -ForegroundColor Yellow; return }
                default { Write-Host "Opcao invalida. O usuario nao foi criado." -ForegroundColor Red; return }
            }
        }

        if ($PasswordAction -eq "Suggested") {
            $SuggestedPassword = Get-UniwareSuggestedPassword
            $SecurePassword = ConvertTo-SecureString $SuggestedPassword -AsPlainText -Force
            $SuggestedPassword = $null
            $ShowSuggestedPassword = $true
        } elseif ($PasswordAction -eq "Custom") {
            $SecurePassword = Read-UniwareCustomPassword
            if (-not $SecurePassword) {
                Write-Host "Operacao cancelada. Nenhuma senha foi alterada." -ForegroundColor Yellow
                return
            }
        }

        if (-not $ExistingUser) {
            New-LocalUser -Name "Unilabimp" -Password $SecurePassword -FullName "Usuario Servico Impressao" -Description "Usuario para gerenciar impressao" -ErrorAction Stop | Out-Null
            Write-Host "Usuario 'Unilabimp' criado com sucesso!" -ForegroundColor Green
        } elseif ($PasswordAction -ne "Keep") {
            Set-LocalUser -Name "Unilabimp" -Password $SecurePassword -ErrorAction Stop
            Write-Host "Senha do usuario 'Unilabimp' atualizada com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "A senha atual do usuario foi mantida." -ForegroundColor Green
        }

        $ConfiguredUser = Get-LocalUser -Name "Unilabimp" -ErrorAction Stop
        if (-not $ConfiguredUser.Enabled) {
            Enable-LocalUser -Name "Unilabimp" -ErrorAction Stop
            Write-Host "Usuario 'Unilabimp' habilitado." -ForegroundColor Green
        }
        $StandardUsersGroup = Get-LocalGroup -SID "S-1-5-32-545" -ErrorAction Stop
        $MemberSids = @(Get-LocalGroupMember -Group $StandardUsersGroup.Name -ErrorAction Stop | ForEach-Object { $_.SID.Value })
        if ($ConfiguredUser.SID.Value -notin $MemberSids) {
            Add-LocalGroupMember -Group $StandardUsersGroup.Name -Member "Unilabimp" -ErrorAction Stop
            Write-Host ("Usuario adicionado ao grupo local '" + $StandardUsersGroup.Name + "'.") -ForegroundColor Green
        } else {
            Write-Host ("Usuario ja pertence ao grupo local '" + $StandardUsersGroup.Name + "'.") -ForegroundColor Green
        }

        $PermissionResult = Set-SpoolPrintersFullControl -UserSid $ConfiguredUser.SID
        Write-Host ("Permissoes validadas em: " + $PermissionResult.Path) -ForegroundColor Green
        foreach ($Identity in $PermissionResult.Identities) {
            Write-Host ("[OK] Controle total: {0} ({1})" -f $Identity.Name,$Identity.Sid) -ForegroundColor Green
        }

        if ($ShowSuggestedPassword) {
            Write-Host ("Senha sugerida aplicada: " + (Get-UniwareSuggestedPassword)) -ForegroundColor Cyan
            Write-Host "Anote esta senha para uso no computador configurado." -ForegroundColor Yellow
        }

        if ($SecurePassword) { $SecurePassword.Dispose(); $SecurePassword = $null }
        Restart-Service -Name "Spooler" -Force -ErrorAction Stop
        Write-Host "Servico de Spooler de Impressao reiniciado." -ForegroundColor Green
    } catch {
        if ($SecurePassword) { $SecurePassword.Dispose() }
        Write-Host ("[-] Erro ao configurar usuario/spool: " + $_.Exception.Message) -ForegroundColor Red
        if ($_.Exception.Message -match '(?i)password|senha') {
            Write-Host "Verifique os requisitos da politica de senhas configurada neste Windows." -ForegroundColor Yellow
        }
    }
}

Function Initialize-UniwareCredentialApi {
    if ("UniwareCredentialNative" -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
internal struct UNIWARE_CREDENTIAL {
    public UInt32 Flags;
    public UInt32 Type;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
    [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public UInt32 CredentialBlobSize;
    public IntPtr CredentialBlob;
    public UInt32 Persist;
    public UInt32 AttributeCount;
    public IntPtr Attributes;
    [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
    [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
}

public static class UniwareCredentialNative {
    private const UInt32 CRED_TYPE_DOMAIN_PASSWORD = 2;
    private const UInt32 CRED_PERSIST_LOCAL_MACHINE = 2;

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref UNIWARE_CREDENTIAL credential, UInt32 flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, UInt32 type, UInt32 flags, out IntPtr credential);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    public static bool Write(string target, string userName, string password, out int errorCode) {
        errorCode = 0;
        if (String.IsNullOrWhiteSpace(target) || String.IsNullOrWhiteSpace(userName)) {
            errorCode = 87;
            return false;
        }
        byte[] passwordBytes = Encoding.Unicode.GetBytes(password ?? String.Empty);
        if (passwordBytes.Length > 512) {
            errorCode = 87;
            return false;
        }

        IntPtr passwordPointer = IntPtr.Zero;
        try {
            passwordPointer = Marshal.StringToCoTaskMemUni(password ?? String.Empty);
            UNIWARE_CREDENTIAL credential = new UNIWARE_CREDENTIAL();
            credential.Flags = 0;
            credential.Type = CRED_TYPE_DOMAIN_PASSWORD;
            credential.TargetName = target;
            credential.Comment = "Criado pelo Utilitario Uniware";
            credential.CredentialBlobSize = (UInt32)passwordBytes.Length;
            credential.CredentialBlob = passwordPointer;
            credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
            credential.AttributeCount = 0;
            credential.Attributes = IntPtr.Zero;
            credential.TargetAlias = null;
            credential.UserName = userName;

            bool result = CredWrite(ref credential, 0);
            if (!result) { errorCode = Marshal.GetLastWin32Error(); }
            return result;
        } finally {
            Array.Clear(passwordBytes, 0, passwordBytes.Length);
            if (passwordPointer != IntPtr.Zero) { Marshal.ZeroFreeCoTaskMemUnicode(passwordPointer); }
        }
    }

    public static bool Exists(string target) {
        IntPtr credential;
        bool result = CredRead(target, CRED_TYPE_DOMAIN_PASSWORD, 0, out credential);
        if (result && credential != IntPtr.Zero) { CredFree(credential); }
        return result;
    }
}
'@ -ErrorAction Stop
}

Function New-UniwareWindowsCredential {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " CREDENCIAL DO WINDOWS - UNILABIMP" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "Informe o computador que compartilha a pasta ou impressora." -ForegroundColor Gray
    $TargetMachine = (Read-Host "Nome do computador de destino (ou 0 para cancelar)").Trim()
    if ($TargetMachine -eq "0" -or [string]::IsNullOrWhiteSpace($TargetMachine)) {
        Write-Host "Operacao cancelada. Nenhuma credencial foi criada." -ForegroundColor Yellow
        return
    }
    $TargetMachine = $TargetMachine.TrimStart([char[]]@('\','/'))
    if ($TargetMachine -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$') {
        Write-Host "Nome de computador invalido. Use apenas letras, numeros, ponto, hifen ou sublinhado." -ForegroundColor Red
        return
    }

    $CredentialUser = "${TargetMachine}\Unilabimp"
    $PlainPassword = $null
    try {
        Initialize-UniwareCredentialApi
        $PlainPassword = Get-UniwareSuggestedPassword
        $ErrorCode = 0
        $Written = [UniwareCredentialNative]::Write($TargetMachine,$CredentialUser,$PlainPassword,[ref]$ErrorCode)
        if (-not $Written) {
            throw [ComponentModel.Win32Exception]::new($ErrorCode)
        }
        if (-not [UniwareCredentialNative]::Exists($TargetMachine)) {
            throw "O Windows informou sucesso, mas a credencial nao foi localizada na validacao."
        }
        Write-Host ("[OK] Credencial criada para: " + $TargetMachine) -ForegroundColor Green
        Write-Host ("[OK] Usuario armazenado: " + $CredentialUser) -ForegroundColor Green
        Write-Host "A credencial pode ser consultada no Gerenciador de Credenciais do Windows." -ForegroundColor Gray
        Write-SystemToolsLog -Acao "CREDENCIAL-WINDOWS" -Resultado "SUCESSO" -Detalhes ("Destino={0}; Usuario={1}" -f $TargetMachine,$CredentialUser)
    } catch {
        Write-Host ("[ERRO] Nao foi possivel criar a credencial: " + $_.Exception.Message) -ForegroundColor Red
        Write-SystemToolsLog -Acao "CREDENCIAL-WINDOWS" -Resultado "ERRO" -Detalhes ("Destino={0}; Mensagem={1}" -f $TargetMachine,$_.Exception.Message)
    } finally {
        $PlainPassword = $null
    }
}

Function Remove-LocalUsersInteractive {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " REMOVER USUARIOS LOCAIS" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "Selecione quais contas locais deseja remover." -ForegroundColor Gray
    Write-Host "As pastas de perfil e seus arquivos serao preservados." -ForegroundColor Yellow

    try {
        $LocalUsers = @(Get-LocalUser -ErrorAction Stop | Sort-Object Name)
    } catch {
        Write-Host ("Nao foi possivel consultar os usuarios locais: " + $_.Exception.Message) -ForegroundColor Red
        return
    }
    if ($LocalUsers.Count -eq 0) {
        Write-Host "Nenhum usuario local foi encontrado." -ForegroundColor Yellow
        return
    }

    $Users = @($LocalUsers | ForEach-Object {
        $SidValue = if ($_.SID) { $_.SID.Value } else { "" }
        $ProtectionReason = $null
        if ($_.Name -ieq $env:USERNAME) {
            $ProtectionReason = "usuario conectado"
        } elseif ($SidValue -match '-(500|501|503|504)$') {
            $ProtectionReason = "conta interna do Windows"
        }
        [pscustomobject]@{
            Account = $_
            Name = $_.Name
            Enabled = $_.Enabled
            Protected = -not [string]::IsNullOrWhiteSpace($ProtectionReason)
            ProtectionReason = $ProtectionReason
        }
    })

    Write-Host ""
    for ($Index = 0; $Index -lt $Users.Count; $Index++) {
        $State = if ($Users[$Index].Enabled) { "Ativo" } else { "Desativado" }
        $Protection = if ($Users[$Index].Protected) { " | PROTEGIDO: " + $Users[$Index].ProtectionReason } else { "" }
        $Color = if ($Users[$Index].Protected) { "DarkGray" } else { "White" }
        Write-Host (" {0,2} - {1} [{2}]{3}" -f ($Index + 1),$Users[$Index].Name,$State,$Protection) -ForegroundColor $Color
    }
    Write-Host "  0 - Cancelar"
    $InputSelection = Read-Host "Digite os numeros separados por virgula"
    $Selection = ConvertTo-RemovalSelection -InputText $InputSelection -Maximum $Users.Count
    if (-not $Selection.Valid) {
        Write-Host "Selecao invalida. Nenhum usuario foi removido." -ForegroundColor Red
        return
    }
    if ($Selection.Indices.Count -eq 0) {
        Write-Host "Operacao cancelada. Nenhum usuario foi removido." -ForegroundColor Yellow
        return
    }

    $SelectedUsers = @($Selection.Indices | ForEach-Object { $Users[$_] })
    Write-Host ("Selecionados: " + (($SelectedUsers | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor Yellow
    $Confirmation = (Read-Host "Digite REMOVER para confirmar").Trim()
    if ($Confirmation -cne "REMOVER") {
        Write-Host "Confirmacao incorreta. Nenhum usuario foi removido." -ForegroundColor Yellow
        return
    }

    foreach ($User in $SelectedUsers) {
        if ($User.Protected) {
            Write-Host ("[BLOQUEADO] {0}: {1}." -f $User.Name,$User.ProtectionReason) -ForegroundColor Red
            Write-SystemToolsLog -Acao "REMOVER-USUARIO" -Resultado "BLOQUEADO" -Detalhes ("Usuario={0}; Motivo={1}" -f $User.Name,$User.ProtectionReason)
            continue
        }
        try {
            Remove-LocalUser -Name $User.Name -ErrorAction Stop
            Write-Host ("[OK] Usuario removido: " + $User.Name) -ForegroundColor Green
            Write-SystemToolsLog -Acao "REMOVER-USUARIO" -Resultado "SUCESSO" -Detalhes ("Usuario={0}; PerfilPreservado=True" -f $User.Name)
        } catch {
            Write-Host ("[ERRO] Nao foi possivel remover {0}: {1}" -f $User.Name,$_.Exception.Message) -ForegroundColor Red
            Write-SystemToolsLog -Acao "REMOVER-USUARIO" -Resultado "ERRO" -Detalhes ("Usuario={0}; Mensagem={1}" -f $User.Name,$_.Exception.Message)
        }
    }
}

Function Menu-UsuarioECredencial {
    while ($true) {
        Clear-Host
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        Write-Host " USUARIO, SPOOLER E CREDENCIAL" -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Criar usuario e liberar a pasta PRINTERS"
        Write-Host " 02 - Criar credencial do Windows para outro computador"
        Write-Host " 00 - Voltar"
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        $Option = Read-Host "Selecione uma opcao"
        switch -Regex ($Option) {
            '^0?1$' { Config-UsuarioSpool; Pause }
            '^0?2$' { New-UniwareWindowsCredential; Pause }
            '^0?0$' { return }
            default { Write-Host "Opcao invalida!" -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

# ---------------------------------------------------------------------
# REMOCAO CONTROLADA DE IMPRESSORAS E DRIVERS
# ---------------------------------------------------------------------
$Global:PrinterRemovalLogDir = Join-Path $PSScriptRoot "LOGS\REMOCAO_IMPRESSORAS"

Function Write-PrinterRemovalLog {
    param([string]$Tipo,[string]$Nome,[string]$Resultado,[string]$Detalhes = "")
    try {
        New-Item -ItemType Directory -Force -Path $Global:PrinterRemovalLogDir -ErrorAction Stop | Out-Null
        $arquivo = Join-Path $Global:PrinterRemovalLogDir ("Remocao_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
        $linha = "[{0}] Tipo={1}; Nome={2}; Resultado={3}; Usuario={4}; PC={5}; {6}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Tipo,$Nome,$Resultado,$env:USERNAME,$env:COMPUTERNAME,$Detalhes
        Add-Content -LiteralPath $arquivo -Value $linha -Encoding UTF8
    } catch {}
}

Function ConvertTo-RemovalSelection {
    param([string]$InputText,[int]$Maximum)
    if ([string]::IsNullOrWhiteSpace($InputText) -or $InputText -eq "0") {
        return [pscustomobject]@{ Valid = $true; Indices = @() }
    }
    $indices = [System.Collections.Generic.List[int]]::new()
    foreach ($item in ($InputText -split ',')) {
        $item = $item.Trim()
        if ($item -notmatch '^\d+$') { return [pscustomobject]@{ Valid = $false; Indices = @() } }
        $value = [int]$item
        if ($value -lt 1 -or $value -gt $Maximum) { return [pscustomobject]@{ Valid = $false; Indices = @() } }
        if (-not $indices.Contains($value - 1)) { $indices.Add($value - 1) }
    }
    return [pscustomobject]@{ Valid = $true; Indices = @($indices) }
}

Function Remove-InstalledPrinterOnly {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " REMOVER SOMENTE A IMPRESSORA INSTALADA" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "A fila sera removida. O driver e a porta permanecerao instalados." -ForegroundColor Yellow
    Write-Host ""

    try { $printers = @(Get-Printer -ErrorAction Stop | Sort-Object Name) }
    catch {
        Write-Host "Nao foi possivel consultar as impressoras: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    if ($printers.Count -eq 0) {
        Write-Host "Nenhuma impressora instalada foi encontrada." -ForegroundColor Yellow
        return
    }

    for ($i = 0; $i -lt $printers.Count; $i++) {
        $p = $printers[$i]
        Write-Host (" [{0}] {1}" -f ($i + 1),$p.Name) -ForegroundColor White
        Write-Host ("      Driver: {0} | Porta: {1}" -f $p.DriverName,$p.PortName) -ForegroundColor Gray
    }
    Write-Host ""
    $entrada = Read-Host "Numero da impressora (varias: 1,3,4) ou 0 para cancelar"
    $selection = ConvertTo-RemovalSelection -InputText $entrada -Maximum $printers.Count
    if (-not $selection.Valid) {
        Write-Host "Selecao invalida. Nenhuma alteracao foi realizada." -ForegroundColor Red
        return
    }
    $indices = @($selection.Indices)
    if ($indices.Count -eq 0) { return }

    Write-Host "`nSerao removidas somente estas filas de impressao:" -ForegroundColor Yellow
    foreach ($index in $indices) { Write-Host (" - " + $printers[$index].Name) -ForegroundColor White }
    $confirmacao = Read-Host "Digite REMOVER para confirmar"
    if ($confirmacao -cne "REMOVER") {
        Write-Host "Operacao cancelada. Nenhuma alteracao foi realizada." -ForegroundColor Yellow
        return
    }

    foreach ($index in $indices) {
        $printer = $printers[$index]
        try {
            Remove-Printer -Name $printer.Name -Confirm:$false -ErrorAction Stop
            Write-Host ("[OK] Impressora removida: " + $printer.Name) -ForegroundColor Green
            Write-PrinterRemovalLog -Tipo "IMPRESSORA" -Nome $printer.Name -Resultado "REMOVIDA" -Detalhes ("Driver preservado={0}; Porta preservada={1}" -f $printer.DriverName,$printer.PortName)
        } catch {
            Write-Host ("[ERRO] {0}: {1}" -f $printer.Name,$_.Exception.Message) -ForegroundColor Red
            Write-PrinterRemovalLog -Tipo "IMPRESSORA" -Nome $printer.Name -Resultado "ERRO" -Detalhes $_.Exception.Message
        }
    }
}

Function Remove-InstalledManufacturerDriverOnly {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " REMOVER SOMENTE O DRIVER DO FABRICANTE" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "As impressoras instaladas nao serao removidas por esta rotina." -ForegroundColor Yellow
    Write-Host "Drivers em uso por alguma impressora serao bloqueados." -ForegroundColor Yellow
    Write-Host ""

    try { $allDrivers = @(Get-PrinterDriver -ErrorAction Stop | Sort-Object Name) }
    catch {
        Write-Host "Nao foi possivel consultar os drivers: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    $drivers = @($allDrivers | Where-Object {
        $_.Name -notmatch 'Microsoft|OneNote|Fax|XPS|PDF' -and
        ([string]::IsNullOrWhiteSpace([string]$_.Manufacturer) -or $_.Manufacturer -notmatch 'Microsoft')
    })
    if ($drivers.Count -eq 0) {
        Write-Host "Nenhum driver de fabricante foi encontrado." -ForegroundColor Yellow
        return
    }

    for ($i = 0; $i -lt $drivers.Count; $i++) {
        $d = $drivers[$i]
        $fabricante = if ([string]::IsNullOrWhiteSpace([string]$d.Manufacturer)) { "Fabricante nao informado" } else { $d.Manufacturer }
        Write-Host (" [{0}] {1}" -f ($i + 1),$d.Name) -ForegroundColor White
        Write-Host ("      Fabricante: {0} | INF: {1}" -f $fabricante,$d.InfPath) -ForegroundColor Gray
    }
    Write-Host ""
    $entrada = Read-Host "Numero do driver (varios: 1,3,4) ou 0 para cancelar"
    $selection = ConvertTo-RemovalSelection -InputText $entrada -Maximum $drivers.Count
    if (-not $selection.Valid) {
        Write-Host "Selecao invalida. Nenhuma alteracao foi realizada." -ForegroundColor Red
        return
    }
    $indices = @($selection.Indices)
    if ($indices.Count -eq 0) { return }

    $printers = @(Get-Printer -ErrorAction SilentlyContinue)
    $removiveis = [System.Collections.Generic.List[object]]::new()
    foreach ($index in $indices) {
        $driver = $drivers[$index]
        $emUso = @($printers | Where-Object { $_.DriverName -eq $driver.Name })
        if ($emUso.Count -gt 0) {
            Write-Host ("`n[BLOQUEADO] Driver em uso: " + $driver.Name) -ForegroundColor Red
            foreach ($printer in $emUso) { Write-Host ("  Usado por: " + $printer.Name) -ForegroundColor Yellow }
            Write-Host "  Remova primeiro a impressora usando a opcao separada." -ForegroundColor Gray
            Write-PrinterRemovalLog -Tipo "DRIVER" -Nome $driver.Name -Resultado "BLOQUEADO" -Detalhes ("Em uso por: " + (($emUso.Name) -join ', '))
        } else {
            $removiveis.Add($driver)
        }
    }
    if ($removiveis.Count -eq 0) {
        Write-Host "`nNenhum dos drivers selecionados pode ser removido." -ForegroundColor Yellow
        return
    }

    Write-Host "`nSerao removidos do Windows somente estes drivers:" -ForegroundColor Yellow
    foreach ($driver in $removiveis) { Write-Host (" - " + $driver.Name) -ForegroundColor White }
    $confirmacao = Read-Host "Digite REMOVER para confirmar"
    if ($confirmacao -cne "REMOVER") {
        Write-Host "Operacao cancelada. Nenhuma alteracao foi realizada." -ForegroundColor Yellow
        return
    }

    $supportsDriverStore = (Get-Command Remove-PrinterDriver -ErrorAction SilentlyContinue).Parameters.ContainsKey("RemoveFromDriverStore")
    foreach ($driver in $removiveis) {
        try {
            if ($supportsDriverStore) {
                Remove-PrinterDriver -Name $driver.Name -RemoveFromDriverStore -Confirm:$false -ErrorAction Stop
            } else {
                Remove-PrinterDriver -Name $driver.Name -Confirm:$false -ErrorAction Stop
            }
            Write-Host ("[OK] Driver removido: " + $driver.Name) -ForegroundColor Green
            Write-PrinterRemovalLog -Tipo "DRIVER" -Nome $driver.Name -Resultado "REMOVIDO" -Detalhes ("INF={0}; DriverStore={1}" -f $driver.InfPath,$supportsDriverStore)
        } catch {
            Write-Host ("[ERRO] {0}: {1}" -f $driver.Name,$_.Exception.Message) -ForegroundColor Red
            Write-Host "O Windows pode estar mantendo o driver em uso por outro componente." -ForegroundColor Gray
            Write-PrinterRemovalLog -Tipo "DRIVER" -Nome $driver.Name -Resultado "ERRO" -Detalhes $_.Exception.Message
        }
    }
}

# ---------------------------------------------------------------------
# ACESSO REMOTO, UAC E FIREWALL
# ---------------------------------------------------------------------
$Global:SystemToolsLogDir = Join-Path $PSScriptRoot "LOGS\SISTEMA"

Function Write-SystemToolsLog {
    param([string]$Acao,[string]$Resultado,[string]$Detalhes = "")
    try {
        New-Item -ItemType Directory -Force -Path $Global:SystemToolsLogDir -ErrorAction Stop | Out-Null
        $arquivo = Join-Path $Global:SystemToolsLogDir ("Sistema_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
        $linha = "[{0}] Acao={1}; Resultado={2}; Usuario={3}; PC={4}; {5}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Acao,$Resultado,$env:USERNAME,$env:COMPUTERNAME,$Detalhes
        Add-Content -LiteralPath $arquivo -Value $linha -Encoding UTF8
    } catch {}
}

Function Install-RunRustDeskHighPriority {
    $url = "https://uniware.com.br/updates/rustdesk/Unilab%20Rustdesk%20Windows.exe"
    $destino = Join-Path $env:TEMP "Unilab Rustdesk Windows.exe"

    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " BAIXAR E EXECUTAR UNILAB RUSTDESK" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "Origem: $url" -ForegroundColor Gray
    Write-Host "Destino temporario: $destino" -ForegroundColor Gray
    Write-Host ""

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Baixar-ArquivoComProgresso -Url $url -Destino $destino
        if (-not (Test-Path -LiteralPath $destino) -or (Get-Item -LiteralPath $destino).Length -le 0) {
            throw "O download nao produziu um arquivo valido."
        }
        Write-Host "Download concluido com sucesso." -ForegroundColor Green
        Unblock-File -LiteralPath $destino -ErrorAction SilentlyContinue
        Write-Host "`nExecutando RustDesk..." -ForegroundColor Cyan
        $processoInicial = Start-Process -FilePath $destino -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 2

        $processos = @($processoInicial)
        $processos += @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -ne $processoInicial.Id -and ($_.ProcessName -match 'rustdesk|unilab')
        })
        $ajustados = 0
        foreach ($processo in ($processos | Sort-Object Id -Unique)) {
            try {
                $processo.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
                $ajustados++
                Write-Host ("[OK] Prioridade alta aplicada: {0} (PID {1})" -f $processo.ProcessName,$processo.Id) -ForegroundColor Green
            } catch {
                Write-Host ("[AVISO] Nao foi possivel alterar a prioridade do PID {0}: {1}" -f $processo.Id,$_.Exception.Message) -ForegroundColor Yellow
            }
        }
        if ($ajustados -eq 0) {
            Write-Host "O programa foi iniciado, mas nenhum processo permaneceu disponivel para ajuste de prioridade." -ForegroundColor Yellow
        }
        Write-SystemToolsLog -Acao "RUSTDESK" -Resultado "EXECUTADO" -Detalhes ("Arquivo={0}; ProcessosAltaPrioridade={1}" -f $destino,$ajustados)
    } catch {
        Write-Host ("`n[ERRO] Nao foi possivel baixar ou executar o RustDesk: " + $_.Exception.Message) -ForegroundColor Red
        Write-SystemToolsLog -Acao "RUSTDESK" -Resultado "ERRO" -Detalhes $_.Exception.Message
    }
}

Function Test-UniwareDownloadedFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item -or $item.Length -lt 2) { return $false }
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $first = $stream.ReadByte()
        $second = $stream.ReadByte()
        switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
            ".exe" { return ($first -eq 0x4D -and $second -eq 0x5A) }
            ".zip" { return ($first -eq 0x50 -and $second -eq 0x4B) }
            default { return $true }
        }
    } catch { return $false }
    finally { if ($stream) { $stream.Dispose() } }
}

Function Invoke-UniwarePackageDownload {
    param(
        [string]$Name,
        [string]$Url,
        [string]$FileName,
        [string]$DestinationFolder,
        [switch]$Extract,
        [switch]$Execute
    )
    $destination = Join-Path $DestinationFolder $FileName
    try {
        New-Item -ItemType Directory -Force -Path $DestinationFolder -ErrorAction Stop | Out-Null
        Write-Host ("`nBaixando {0}..." -f $Name) -ForegroundColor Cyan
        Write-Host (" Origem: " + $Url) -ForegroundColor Gray
        Write-Host (" Destino: " + $destination) -ForegroundColor Gray
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Baixar-ArquivoComProgresso -Url $Url -Destino $destination
        if (-not (Test-UniwareDownloadedFile -Path $destination)) {
            throw "O arquivo recebido nao corresponde a um $([IO.Path]::GetExtension($FileName)) valido. O servidor pode ter retornado uma pagina de login ou erro."
        }
        $sizeMB = [math]::Round((Get-Item -LiteralPath $destination).Length / 1MB,2)
        Write-Host ("[OK] Download validado: {0} MB" -f $sizeMB) -ForegroundColor Green

        $extractedPath = $null
        if ($Extract) {
            $folderName = [IO.Path]::GetFileNameWithoutExtension($FileName)
            $extractedPath = Join-Path $DestinationFolder $folderName
            New-Item -ItemType Directory -Force -Path $extractedPath -ErrorAction Stop | Out-Null
            Expand-Archive -LiteralPath $destination -DestinationPath $extractedPath -Force -ErrorAction Stop
            $extractedFiles = @(Get-ChildItem -LiteralPath $extractedPath -Recurse -File -ErrorAction Stop)
            if ($extractedFiles.Count -eq 0) { throw "O ZIP foi aberto, mas nenhum arquivo foi extraido." }
            Write-Host ("[OK] Extraido em: " + $extractedPath) -ForegroundColor Green
        }

        if ($Execute) {
            Unblock-File -LiteralPath $destination -ErrorAction SilentlyContinue
            Start-Process -FilePath $destination -ErrorAction Stop | Out-Null
            Write-Host ("[OK] Programa iniciado: " + $Name) -ForegroundColor Green
        }
        Write-SystemToolsLog -Acao "DOWNLOAD-UNIWARE" -Resultado "SUCESSO" -Detalhes ("Nome={0}; Arquivo={1}; Extraido={2}; Executado={3}" -f $Name,$destination,$Extract,$Execute)
        return [pscustomobject]@{ Success=$true; Name=$Name; Path=$destination; ExtractedPath=$extractedPath; Error=$null }
    } catch {
        $message = $_.Exception.Message
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
        Write-Host ("[ERRO] Falha em {0}: {1}" -f $Name,$message) -ForegroundColor Red
        if ($statusCode) { Write-Host (" Codigo HTTP: " + $statusCode) -ForegroundColor Gray }
        if ($statusCode -in @(401,403)) {
            Write-Host " O servidor exige autorizacao ou bloqueou o acesso ao arquivo." -ForegroundColor Yellow
        } elseif ($message -match 'name could not be resolved|nome.*resolvido|connect|conexao') {
            Write-Host " Verifique internet, DNS, proxy e acesso ao dominio informado." -ForegroundColor Yellow
        }
        Write-SystemToolsLog -Acao "DOWNLOAD-UNIWARE" -Resultado "ERRO" -Detalhes ("Nome={0}; URL={1}; HTTP={2}; Mensagem={3}" -f $Name,$Url,$statusCode,$message)
        return [pscustomobject]@{ Success=$false; Name=$Name; Path=$destination; ExtractedPath=$null; Error=$message }
    }
}

Function Install-UnilabNuvem {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " UNILAB NUVEM" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    $folder = Join-Path $env:USERPROFILE "Downloads\Uniware\UnilabNuvem"
    $result = Invoke-UniwarePackageDownload -Name "Unilab Nuvem 0.1.55" -Url "https://uniware.com.br/updates/cloud/Unilab-0.1.55-win.exe" -FileName "Unilab-0.1.55-win.exe" -DestinationFolder $folder -Execute
    if (-not $result.Success) {
        Write-Host "Consulte LOGS\SISTEMA para o diagnostico completo." -ForegroundColor Gray
    }
}

Function Get-PasswordPanelPackages {
    return @(
        [pscustomobject]@{ Name="Painel Lancador"; Url="https://github.com/user-attachments/files/32448015/painel-lancador.zip"; FileName="painel-lancador.zip"; Extract=$true; Execute=$false }
        [pscustomobject]@{ Name="UniSenhas 6.0.4.0"; Url="https://github.com/user-attachments/files/32447994/UniSenha_6.0.4.0.zip"; FileName="UniSenha_6.0.4.0.zip"; Extract=$true; Execute=$false }
        [pscustomobject]@{ Name="UniCheckin 2.0.0.2"; Url="https://github.com/user-attachments/files/32447996/UniCheckin_2.0.0.2.zip"; FileName="UniCheckin_2.0.0.2.zip"; Extract=$true; Execute=$false }
        [pscustomobject]@{ Name="TesteBotoeira"; Url="https://github.com/user-attachments/files/32448016/TesteBotoeira.zip"; FileName="TesteBotoeira.zip"; Extract=$true; Execute=$false }
    )
}

Function Invoke-PasswordPanelPackage {
    param([int]$Index,[switch]$DownloadOnly)
    $packages = @(Get-PasswordPanelPackages)
    if ($Index -lt 0 -or $Index -ge $packages.Count) { return $null }
    $package = $packages[$Index]
    $folder = Join-Path $env:USERPROFILE "Downloads\Uniware\PainelSenhas"
    $executeNow = $package.Execute -and -not $DownloadOnly
    return Invoke-UniwarePackageDownload -Name $package.Name -Url $package.Url -FileName $package.FileName -DestinationFolder $folder -Extract:([bool]$package.Extract) -Execute:([bool]$executeNow)
}

Function Download-AllPasswordPanelPackages {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " PAINEL DE SENHAS - BAIXAR TODOS" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "Os executaveis serao baixados sem abrir. Os ZIPs serao extraidos." -ForegroundColor Yellow
    $confirmacao = (Read-Host "Digite [1] para baixar todos ou [0] para cancelar").Trim()
    if ($confirmacao -ne "1") {
        Write-Host "Operacao cancelada. Nenhum download foi iniciado." -ForegroundColor Yellow
        return
    }
    $results = @()
    for ($i=0; $i -lt 4; $i++) { $results += Invoke-PasswordPanelPackage -Index $i -DownloadOnly }
    $successCount = @($results | Where-Object Success).Count
    $failureCount = @($results | Where-Object { -not $_.Success }).Count
    Write-Host "`n==============================================================" -ForegroundColor DarkCyan
    Write-Host ("Concluidos: {0} | Falhas: {1}" -f $successCount,$failureCount) -ForegroundColor $(if($failureCount -eq 0){"Green"}else{"Yellow"})
    $folder = Join-Path $env:USERPROFILE "Downloads\Uniware\PainelSenhas"
    if (Test-Path -LiteralPath $folder) { Start-Process explorer.exe -ArgumentList "`"$folder`"" }
}

Function Menu-PasswordPanel {
    while ($true) {
        Clear-Host
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        Write-Host " PAINEL DE SENHAS" -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Painel Lancador (baixar e extrair)"
        Write-Host " 02 - UniSenhas 6.0.4.0 (baixar e extrair)"
        Write-Host " 03 - UniCheckin 2.0.0.2 (baixar e extrair)"
        Write-Host " 04 - TesteBotoeira (baixar e extrair)"
        Write-Host " 05 - Baixar todos"
        Write-Host " 00 - Voltar"
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        $op = Read-Host "Selecione uma opcao"
        switch -Regex ($op) {
            "^0?1$" { $null=Invoke-PasswordPanelPackage -Index 0; Pause }
            "^0?2$" { $null=Invoke-PasswordPanelPackage -Index 1; Pause }
            "^0?3$" { $null=Invoke-PasswordPanelPackage -Index 2; Pause }
            "^0?4$" { $null=Invoke-PasswordPanelPackage -Index 3; Pause }
            "^0?5$" { Download-AllPasswordPanelPackages; Pause }
            "^0?0$" { return }
            default { Write-Host "Opcao invalida!" -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

Function Disable-WindowsUACMaximum {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " DESATIVAR UAC DO WINDOWS" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "Esta configuracao desativa o Controle de Conta de Usuario." -ForegroundColor Yellow
    Write-Host "O computador precisara ser reiniciado para aplicar EnableLUA=0." -ForegroundColor Yellow
    Write-Host ""
    $confirmacao = (Read-Host "Digite [1] para desativar ou [0] para cancelar").Trim()
    if ($confirmacao -ne "1") {
        if ($confirmacao -eq "0") {
            Write-Host "`n[CANCELADO] O tecnico escolheu a opcao 0." -ForegroundColor Yellow
            Write-Host "Nenhuma configuracao do Windows foi alterada." -ForegroundColor Green
            Write-SystemToolsLog -Acao "UAC" -Resultado "CANCELADO-USUARIO" -Detalhes "Opcao=0"
        } else {
            Write-ConfirmationCanceled -Expected "1" -Received $confirmacao -Operation "UAC-DESATIVAR"
        }
        return
    }
    if (-not (Test-UniwareAdministrator)) {
        Write-Host "`n[FALHA] A janela nao possui privilegios de administrador." -ForegroundColor Red
        Write-Host "Solucao: feche o utilitario e execute Abrir-Utilitarios.bat como administrador." -ForegroundColor Yellow
        Write-SystemToolsLog -Acao "UAC" -Resultado "ERRO-SEM-ADMIN" -Detalhes "Processo sem elevacao"
        return
    }

    $systemPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $stateDir = Join-Path $PSScriptRoot "ESTADO\UAC"
    $backupFile = Join-Path $stateDir ("UAC_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $propertyNames = @("EnableLUA","ConsentPromptBehaviorAdmin","ConsentPromptBehaviorUser","PromptOnSecureDesktop","FilterAdministratorToken","EnableInstallerDetection","LocalAccountTokenFilterPolicy")
    try {
        New-Item -ItemType Directory -Force -Path $stateDir -ErrorAction Stop | Out-Null
        $current = Get-ItemProperty -LiteralPath $systemPath -ErrorAction Stop
        $backupValues = [ordered]@{}
        foreach ($name in $propertyNames) {
            $property = $current.PSObject.Properties[$name]
            $backupValues[$name] = if ($null -eq $property) { $null } else { $property.Value }
        }
        [pscustomobject]@{
            SavedAt = (Get-Date).ToString("o")
            Computer = $env:COMPUTERNAME
            RegistryPath = $systemPath
            Values = $backupValues
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backupFile -Encoding UTF8

        $newValues = [ordered]@{
            EnableLUA = 0
            ConsentPromptBehaviorAdmin = 0
            ConsentPromptBehaviorUser = 0
            PromptOnSecureDesktop = 0
            FilterAdministratorToken = 0
            EnableInstallerDetection = 0
            LocalAccountTokenFilterPolicy = 1
        }
        foreach ($entry in $newValues.GetEnumerator()) {
            New-ItemProperty -LiteralPath $systemPath -Name $entry.Key -Value $entry.Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        }

        $validated = Get-ItemProperty -LiteralPath $systemPath -ErrorAction Stop
        $failed = @($newValues.GetEnumerator() | Where-Object {
            $validatedProperty = $validated.PSObject.Properties[$_.Key]
            $null -eq $validatedProperty -or [int]$validatedProperty.Value -ne [int]$_.Value
        })
        if ($failed.Count -gt 0) { throw "A validacao encontrou valores que nao foram aplicados." }

        Write-Host "`n[OK] UAC configurado para desativacao completa." -ForegroundColor Green
        Write-Host "Backup salvo em: $backupFile" -ForegroundColor Gray
        Write-Host "REINICIE O COMPUTADOR para concluir a alteracao." -ForegroundColor Yellow
        Write-SystemToolsLog -Acao "UAC" -Resultado "DESATIVADO-PENDENTE-REINICIO" -Detalhes ("Backup=" + $backupFile)
    } catch {
        $errorMessage = $_.Exception.Message
        $errorId = $_.FullyQualifiedErrorId
        $errorCategory = [string]$_.CategoryInfo.Category
        $errorHresult = "0x{0:X8}" -f ($_.Exception.HResult -band 0xffffffffL)
        Write-Host "`n[ERRO] Nao foi possivel alterar o UAC." -ForegroundColor Red
        Write-Host ("Motivo informado pelo Windows: " + $errorMessage) -ForegroundColor White
        Write-Host ("Codigo tecnico: {0} | Categoria: {1} | HRESULT: {2}" -f $errorId,$errorCategory,$errorHresult) -ForegroundColor Gray
        Write-Host "Possiveis solucoes:" -ForegroundColor Cyan
        if ($errorMessage -match 'access|acesso|denied|privilege|privilegio|0x80070005' -or $errorCategory -eq "PermissionDenied") {
            Write-Host " - Execute Abrir-Utilitarios.bat como administrador." -ForegroundColor Yellow
        } elseif ($errorMessage -match 'policy|politica|GPO|domain|dominio') {
            Write-Host " - Verifique se uma GPO de dominio esta controlando as configuracoes do UAC." -ForegroundColor Yellow
        } else {
            Write-Host " - Verifique politicas corporativas, antivirus ou protecao do registro." -ForegroundColor Yellow
            Write-Host " - Use o codigo tecnico acima para consultar o Visualizador de Eventos." -ForegroundColor Yellow
        }
        Write-SystemToolsLog -Acao "UAC" -Resultado "ERRO" -Detalhes ("Mensagem={0}; Id={1}; Categoria={2}; HRESULT={3}" -f $errorMessage,$errorId,$errorCategory,$errorHresult)
    }
}

Function Show-FirewallStatus {
    Write-Host "`nEstado dos perfis do Firewall:" -ForegroundColor Cyan
    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction Stop | Sort-Object Name)
        foreach ($profile in $profiles) {
            $cor = if ($profile.Enabled) { "Green" } else { "Red" }
            Write-Host (" - {0}: {1}" -f $profile.Name,($(if($profile.Enabled){"ATIVO"}else{"DESATIVADO"}))) -ForegroundColor $cor
        }
    } catch {
        Write-Host ("Nao foi possivel consultar o Firewall: " + $_.Exception.Message) -ForegroundColor Red
    }
}

Function Test-UniwareAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

Function Write-ConfirmationCanceled {
    param([string]$Expected,[string]$Received,[string]$Operation)
    $receivedText = if ([string]::IsNullOrWhiteSpace($Received)) { "nenhuma resposta (apenas Enter)" } else { "'$Received'" }
    Write-Host ""
    Write-Host "[CANCELADO] A operacao nao foi executada." -ForegroundColor Yellow
    Write-Host ("Motivo: a confirmacao recebida foi {0}." -f $receivedText) -ForegroundColor White
    Write-Host ("Para executar, digite exatamente {0} e pressione Enter." -f $Expected) -ForegroundColor Cyan
    Write-Host "Nenhuma configuracao do Windows foi alterada." -ForegroundColor Green
    Write-SystemToolsLog -Acao $Operation -Resultado "CANCELADO-CONFIRMACAO" -Detalhes ("Esperado={0}; Recebido={1}" -f $Expected,$receivedText)
}

Function Test-FirewallPrerequisites {
    $ok = $true
    Write-Host "`nVerificando requisitos..." -ForegroundColor Cyan

    if (Test-UniwareAdministrator) {
        Write-Host " [OK] PowerShell executado como administrador." -ForegroundColor Green
    } else {
        Write-Host " [FALHA] A janela nao possui privilegios de administrador." -ForegroundColor Red
        Write-Host " Solucao: feche o utilitario e execute Abrir-Utilitarios.bat como administrador." -ForegroundColor Yellow
        $ok = $false
    }

    foreach ($commandName in @("Get-NetFirewallProfile","Set-NetFirewallProfile","New-NetFirewallRule")) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            Write-Host (" [FALHA] Comando ausente: " + $commandName) -ForegroundColor Red
            Write-Host " Solucao: verifique o modulo NetSecurity e a integridade do Windows." -ForegroundColor Yellow
            $ok = $false
        }
    }

    foreach ($serviceName in @("BFE","MpsSvc")) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            if ($service.Status -eq "Running") {
                Write-Host (" [OK] Servico {0}: em execucao." -f $serviceName) -ForegroundColor Green
            } else {
                Write-Host (" [FALHA] Servico {0}: {1}." -f $serviceName,$service.Status) -ForegroundColor Red
                Write-Host (" Solucao: inicie o servico {0} e tente novamente." -f $serviceName) -ForegroundColor Yellow
                $ok = $false
            }
        } catch {
            Write-Host (" [FALHA] Nao foi possivel consultar o servico {0}: {1}" -f $serviceName,$_.Exception.Message) -ForegroundColor Red
            $ok = $false
        }
    }

    if (-not $ok) {
        Write-Host "`nA operacao foi interrompida porque um ou mais requisitos falharam." -ForegroundColor Red
        Write-SystemToolsLog -Acao "FIREWALL-PREFLIGHT" -Resultado "FALHA" -Detalhes "Administrador, comandos ou servicos indisponiveis"
    }
    return $ok
}

Function Write-FirewallTechnicalError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord,[string]$Operation)
    $message = $ErrorRecord.Exception.Message
    $errorId = $ErrorRecord.FullyQualifiedErrorId
    $category = [string]$ErrorRecord.CategoryInfo.Category
    $hresult = "0x{0:X8}" -f ($ErrorRecord.Exception.HResult -band 0xffffffffL)

    Write-Host ""
    Write-Host "[ERRO] A operacao do Firewall nao foi concluida." -ForegroundColor Red
    Write-Host ("Motivo informado pelo Windows: " + $message) -ForegroundColor White
    Write-Host ("Codigo tecnico: {0} | Categoria: {1} | HRESULT: {2}" -f $errorId,$category,$hresult) -ForegroundColor Gray
    Write-Host "Possiveis solucoes:" -ForegroundColor Cyan
    if ($message -match 'access|acesso|denied|privilege|privilegio|0x80070005' -or $category -eq "PermissionDenied") {
        Write-Host " - Execute Abrir-Utilitarios.bat como administrador." -ForegroundColor Yellow
    } elseif ($message -match 'policy|politica|GPO|domain|dominio') {
        Write-Host " - Verifique se uma GPO de dominio ou politica local esta controlando o Firewall." -ForegroundColor Yellow
        Write-Host " - Gere gpresult /h para identificar a politica aplicada." -ForegroundColor Yellow
    } elseif ($message -match 'service|servico|BFE|MpsSvc|RPC') {
        Write-Host " - Verifique e inicie os servicos BFE e MpsSvc." -ForegroundColor Yellow
    } elseif ($message -match 'not found|nao.*encontr|module|modulo|cmdlet') {
        Write-Host " - Verifique o modulo NetSecurity e repare os componentes do Windows." -ForegroundColor Yellow
    } else {
        Write-Host " - Consulte o codigo tecnico acima e o Visualizador de Eventos do Windows." -ForegroundColor Yellow
        Write-Host " - Confirme se antivirus, EDR ou politica corporativa bloqueou a alteracao." -ForegroundColor Yellow
    }
    Write-SystemToolsLog -Acao $Operation -Resultado "ERRO" -Detalhes ("Mensagem={0}; Id={1}; Categoria={2}; HRESULT={3}" -f $message,$errorId,$category,$hresult)
}

Function Set-AllFirewallProfiles {
    param([bool]$Enabled)
    $verb = if ($Enabled) { "REATIVAR" } else { "DESATIVAR" }
    Write-Host ""
    Write-Host ("Acao selecionada: {0} o Firewall em Domain, Private e Public." -f $verb) -ForegroundColor Yellow
    $confirmacao = (Read-Host "Digite [1] para executar ou [0] para cancelar").Trim()
    if ($confirmacao -ne "1") {
        if ($confirmacao -eq "0") {
            Write-Host "`n[CANCELADO] O tecnico escolheu a opcao 0." -ForegroundColor Yellow
            Write-Host "Nenhuma configuracao do Windows foi alterada." -ForegroundColor Green
            Write-SystemToolsLog -Acao "FIREWALL-$verb" -Resultado "CANCELADO-USUARIO" -Detalhes "Opcao=0"
        } else {
            Write-ConfirmationCanceled -Expected "1" -Received $confirmacao -Operation "FIREWALL-$verb"
        }
        return
    }
    if (-not (Test-FirewallPrerequisites)) { return }
    try {
        Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled $Enabled -ErrorAction Stop
        $profiles = @(Get-NetFirewallProfile -ErrorAction Stop)
        $invalid = @($profiles | Where-Object { [bool]$_.Enabled -ne $Enabled })
        if ($invalid.Count -gt 0) { throw "A validacao encontrou perfis em estado diferente do solicitado." }
        $resultado = if ($Enabled) { "REATIVADO" } else { "DESATIVADO" }
        Write-Host ("[OK] Firewall $resultado em todos os perfis e validado.") -ForegroundColor Green
        Write-SystemToolsLog -Acao "FIREWALL" -Resultado $resultado -Detalhes "Perfis=Domain,Private,Public"
    } catch {
        Write-FirewallTechnicalError -ErrorRecord $_ -Operation "FIREWALL-$verb"
    }
}

Function Test-FirewallPortExpression {
    param([string]$Ports)
    if ([string]::IsNullOrWhiteSpace($Ports)) { return $false }
    foreach ($part in ($Ports -split ',')) {
        $part = $part.Trim()
        if ($part -match '^(\d+)$') {
            $port = [int]$Matches[1]
            if ($port -lt 1 -or $port -gt 65535) { return $false }
        } elseif ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]; $end = [int]$Matches[2]
            if ($start -lt 1 -or $end -gt 65535 -or $start -gt $end) { return $false }
        } else { return $false }
    }
    return $true
}

Function New-AndValidateFirewallPortRule {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host " CRIAR E VALIDAR REGRA DE PORTA" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    $ports = (Read-Host "Porta, lista ou intervalo (ex: 9100 | 80,443 | 5000-5010)").Trim()
    if (-not (Test-FirewallPortExpression -Ports $ports)) {
        Write-Host "Portas invalidas. Use valores entre 1 e 65535." -ForegroundColor Red
        return
    }
    $protocolInput = (Read-Host "Protocolo: [T] TCP ou [U] UDP").Trim()
    $protocol = if ($protocolInput -match '^[Uu]$') { "UDP" } elseif ($protocolInput -match '^[Tt]$') { "TCP" } else { $null }
    if (-not $protocol) { Write-Host "Protocolo invalido." -ForegroundColor Red; return }
    $directionInput = (Read-Host "Direcao: [E] Entrada ou [S] Saida").Trim()
    $direction = if ($directionInput -match '^[Ee]$') { "Inbound" } elseif ($directionInput -match '^[Ss]$') { "Outbound" } else { $null }
    if (-not $direction) { Write-Host "Direcao invalida." -ForegroundColor Red; return }
    $defaultName = "Uniware $protocol $ports $direction"
    $displayName = Read-Host "Nome da regra (Enter para '$defaultName')"
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $defaultName }

    $existing = @(Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        Write-Host "Ja existe uma regra com esse nome. A regra existente sera apenas validada." -ForegroundColor Yellow
    } else {
        $confirmacao = (Read-Host "Digite CRIAR para adicionar e validar a regra").Trim()
        if ($confirmacao -cne "CRIAR") {
            Write-ConfirmationCanceled -Expected "CRIAR" -Received $confirmacao -Operation "FIREWALL-CRIAR-REGRA"
            return
        }
        if (-not (Test-FirewallPrerequisites)) { return }
        try {
            $ruleParameters = @{
                DisplayName = $displayName
                Direction = $direction
                Protocol = $protocol
                Action = "Allow"
                Profile = "Any"
                Enabled = "True"
                ErrorAction = "Stop"
            }
            if ($direction -eq "Inbound") { $ruleParameters.LocalPort = $ports }
            else { $ruleParameters.RemotePort = $ports }
            New-NetFirewallRule @ruleParameters | Out-Null
            Write-Host "Regra criada. Iniciando validacao..." -ForegroundColor Cyan
        } catch {
            Write-FirewallTechnicalError -ErrorRecord $_ -Operation "FIREWALL-CRIAR-REGRA"
            return
        }
    }

    try {
        $rule = Get-NetFirewallRule -DisplayName $displayName -ErrorAction Stop | Select-Object -First 1
        $filter = $rule | Get-NetFirewallPortFilter -ErrorAction Stop | Select-Object -First 1
        $protocolValue = [string]$filter.Protocol
        if ($protocolValue -eq "6") { $protocolValue = "TCP" }
        if ($protocolValue -eq "17") { $protocolValue = "UDP" }
        $requestedPorts = @(($ports -split ',') | ForEach-Object { $_.Trim() } | Sort-Object)
        $configuredPorts = if ($direction -eq "Inbound") { $filter.LocalPort } else { $filter.RemotePort }
        $actualPorts = @($configuredPorts | ForEach-Object { ([string]$_ -split ',') } | ForEach-Object { $_.Trim() } | Sort-Object)
        $portsMatch = (($requestedPorts -join ',') -eq ($actualPorts -join ','))
        $valid = ($rule.Enabled -eq "True" -or $rule.Enabled -eq $true) -and [string]$rule.Action -eq "Allow" -and [string]$rule.Direction -eq $direction -and $protocolValue -eq $protocol -and $portsMatch
        if (-not $valid) { throw "A regra existe, mas seus parametros nao correspondem ao solicitado." }
        Write-Host "`n[OK] Regra validada no Firewall:" -ForegroundColor Green
        Write-Host (" Nome={0} | Direcao={1} | Protocolo={2} | Porta={3} | Acao=Allow | Ativa=True" -f $displayName,$direction,$protocol,$ports) -ForegroundColor White

        $singlePorts = @($ports -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        if ($direction -eq "Outbound") {
            Write-Host " Regra de saida validada. O teste de escuta local nao se aplica a portas remotas." -ForegroundColor Gray
            $singlePorts = @()
        }
        foreach ($port in $singlePorts) {
            if ($protocol -eq "TCP") {
                $listening = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue).Count -gt 0
            } else {
                $listening = @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue).Count -gt 0
            }
            if ($listening) {
                Write-Host (" [OK] Existe um programa escutando na porta {0}/{1}." -f $port,$protocol) -ForegroundColor Green
            } else {
                Write-Host (" [AVISO] Regra aberta, mas nenhum programa esta escutando agora em {0}/{1}." -f $port,$protocol) -ForegroundColor Yellow
            }
        }
        Write-SystemToolsLog -Acao "FIREWALL-REGRA" -Resultado "CRIADA-E-VALIDADA" -Detalhes ("Nome={0}; Direcao={1}; Protocolo={2}; Portas={3}" -f $displayName,$direction,$protocol,$ports)
    } catch {
        Write-FirewallTechnicalError -ErrorRecord $_ -Operation "FIREWALL-VALIDAR-REGRA"
    }
}

Function Menu-FirewallTools {
    while ($true) {
        Clear-Host
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        Write-Host " FIREWALL E PORTAS" -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Consultar estado dos perfis"
        Write-Host " 02 - Desativar Firewall em todos os perfis"
        Write-Host " 03 - Reativar Firewall em todos os perfis"
        Write-Host " 04 - Criar e validar regra TCP/UDP"
        Write-Host " 00 - Voltar"
        Write-Host "==============================================================" -ForegroundColor DarkCyan
        $op = Read-Host "Selecione uma opcao"
        switch -Regex ($op) {
            "^0?1$" { Show-FirewallStatus; Pause }
            "^0?2$" { Set-AllFirewallProfiles -Enabled $false; Pause }
            "^0?3$" { Set-AllFirewallProfiles -Enabled $true; Pause }
            "^0?4$" { New-AndValidateFirewallPortRule; Pause }
            "^0?0$" { return }
            default { Write-Host "Opcao invalida!" -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

Function Instalar-ImpressoraTCP {
    param ($IP, $Modelo)

    $NomePorta = "IP_$IP"
    Write-Host "`n[1/2] Criando porta TCP/IP ($IP)..." -ForegroundColor Cyan
    if (-not (Get-PrinterPort -Name $NomePorta -ErrorAction SilentlyContinue)) {
        try {
            Add-PrinterPort -Name $NomePorta -PrinterHostAddress $IP -PortNumber 9100 -ErrorAction Stop
            Write-Host "Porta $NomePorta criada!" -ForegroundColor Green
        } catch {
            Write-Host "[-] Erro ao criar a porta de impressao: ${_}" -ForegroundColor Red
            return
        }
    }

    Write-Host "[2/2] Buscando driver compativel no sistema..." -ForegroundColor Cyan
    $DriversDisponiveis = Get-PrinterDriver | Select-Object -ExpandProperty Name | Sort-Object

    if (-not $DriversDisponiveis) {
        Write-Host "[-] Nenhum driver de impressora encontrado no sistema. Instale o driver da marca antes." -ForegroundColor Red
        return
    }

    $DriverSugerido = $null
    $PalavrasChave = $Modelo -split '[\s\-_\(\)]+'
    foreach ($Palavra in $PalavrasChave) {
        if ($Palavra.Length -gt 2) {
            $DriverSugerido =$DriversDisponiveis | Where-Object { $_ -like "*$Palavra*" } | Select-Object -First 1
            if ($DriverSugerido) { break }
        }
    }

    Write-Host "`n-------------------------------------------------" -ForegroundColor Cyan
    Write-Host " SELECIONE O DRIVER PARA A IMPRESSORA ($IP):" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
    for ($d = 0; $d -lt $DriversDisponiveis.Count; $d++) {
        $TextoExibicao = " [$($d + 1)] $($DriversDisponiveis[$d])"
        if ($DriversDisponiveis[$d] -eq $DriverSugerido) {
            Write-Host "$TextoExibicao <-- [RECOMENDADO DETECTADO]" -ForegroundColor Green
        } else {
            Write-Host $TextoExibicao -ForegroundColor White
        }
    }
    Write-Host "-------------------------------------------------" -ForegroundColor Cyan

    $EscolhaDriver = Read-Host "Digite o numero do Driver desejado"

    if ($EscolhaDriver -match '^\d+$' -and [int]$EscolhaDriver -le $DriversDisponiveis.Count) {
        $DriverSelecionado = $DriversDisponiveis[[int]$EscolhaDriver - 1]
        
        $NomeFila = Read-Host "`nDigite o nome para a Impressora (Pressione Enter para '$DriverSelecionado')"
        if ([string]::IsNullOrWhiteSpace($NomeFila)) { $NomeFila = "$DriverSelecionado" }

        try {
            Add-Printer -Name $NomeFila -DriverName $DriverSelecionado -PortName $NomePorta -ErrorAction Stop
            Write-Host "`n[SUCESSO] Impressora '$NomeFila' instalada com sucesso!" -ForegroundColor Green
        } catch {
            Write-Host "[-] Falha ao adicionar impressora: ${_}" -ForegroundColor Red
        }
    }
}

Function Scan-Locais {
    Write-Host "`n[+] Buscando impressoras conectadas via USB e Portas COM..." -ForegroundColor Cyan

    $DispositivosEncontrados = [System.Collections.Generic.List[PSCustomObject]]::new()

    $DispositivosUSB = Get-CimInstance Win32_PnPEntity | Where-Object { 
        $_.PNPClass -eq "Printer" -or $_.Service -like "*usbprint*" -or $_.Caption -like "*USB Printing*" -or $_.Caption -like "*Impressora*"
    }

    foreach ($usb in $DispositivosUSB) {
        if ($usb.Caption) {$DispositivosEncontrados.Add([PSCustomObject]@{
                Tipo   = "USB"
                Porta  = "USB/PnP"
                Modelo = $usb.Caption
            })
        }
    }

    $DispositivosCOM = Get-CimInstance Win32_PnPEntity | Where-Object {$_.PNPClass -eq "PORTS" -and ($_.Name -like "*COM*" -or $_.Caption -like "*Serial*") }

    foreach ($com in $DispositivosCOM) {$DispositivosEncontrados.Add([PSCustomObject]@{
            Tipo   = "COM"
            Porta  = $com.Name
            Modelo = $com.Caption
        })
    }

    if ($DispositivosEncontrados.Count -eq 0) {
        Write-Host "[-] Nenhuma impressora USB ou Porta COM encontrada." -ForegroundColor Yellow
        return
    }

    Write-Host "`n-------------------------------------------------" -ForegroundColor Yellow
    Write-Host " IMPRESSORAS E DISPOSITIVOS LOCAIS ENCONTRADOS:" -ForegroundColor Yellow
    Write-Host "-------------------------------------------------" -ForegroundColor Yellow

    for ($i = 0; $i -lt $DispositivosEncontrados.Count; $i++) {
        $item = $DispositivosEncontrados[$i]
        Write-Host " [$($i + 1)] [$($item.Tipo)] $($item.Modelo) (Porta/ID: $($item.Porta))" -ForegroundColor White
    }
    Write-Host " [0] Voltar ao Menu Principal" -ForegroundColor Gray
    Write-Host "-------------------------------------------------" -ForegroundColor Yellow

    $Escolha = Read-Host "Digite o numero do dispositivo para configurar o driver"

    if ($Escolha -ne "0" -and $Escolha -match '^\d+$' -and [int]$Escolha -le $DispositivosEncontrados.Count) {
        $DispSel = $DispositivosEncontrados[[int]$Escolha - 1]
        $ModeloAuto = $DispSel.Modelo

        Write-Host "`n[1/2] Buscando drivers disponiveis no Windows..." -ForegroundColor Cyan
        $DriversDisponiveis = Get-PrinterDriver | Select-Object -ExpandProperty Name | Sort-Object

        if (-not $DriversDisponiveis) {
            Write-Host "[-] Nenhum driver de impressora instalado no Windows. Instale o driver da marca primeiro." -ForegroundColor Red
            return
        }

        $DriverSugerido = $null
        $PalavrasChave = $ModeloAuto -split '[\s\-_\(\)]+'
        foreach ($Palavra in $PalavrasChave) {
            if ($Palavra.Length -gt 2 -and $Palavra -notmatch 'USB|Serial|Port|Device|Generic|Standard') {
                $DriverSugerido =$DriversDisponiveis | Where-Object { $_ -like "*$Palavra*" } | Select-Object -First 1
                if ($DriverSugerido) { break }
            }
        }

        Write-Host "`n-------------------------------------------------" -ForegroundColor Cyan
        Write-Host " SELECIONE O DRIVER PARA INSTALACAO:" -ForegroundColor Cyan
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
        for ($d = 0; $d -lt $DriversDisponiveis.Count; $d++) {
            $TextoExibicao = " [$($d + 1)] $($DriversDisponiveis[$d])"
            if ($DriversDisponiveis[$d] -eq $DriverSugerido) {
                Write-Host "$TextoExibicao <-- [RECOMENDADO DETECTADO]" -ForegroundColor Green
            } else {
                Write-Host $TextoExibicao -ForegroundColor White
            }
        }
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan

        $EscolhaDriver = Read-Host "Digite o numero do Driver desejado"

        if ($EscolhaDriver -match '^\d+$' -and [int]$EscolhaDriver -le $DriversDisponiveis.Count) {
            $DriverSelecionado = $DriversDisponiveis[[int]$EscolhaDriver - 1]
            
            $NomeFila = Read-Host "`nDigite o nome para a Impressora (Pressione Enter para '$DriverSelecionado')"
            if ([string]::IsNullOrWhiteSpace($NomeFila)) {
                $NomeFila = "$DriverSelecionado"
            }

            Write-Host "`n[2/2] Instalando '$NomeFila'..." -ForegroundColor Cyan
            try {
                $PortaInstalacao = if ($DispSel.Tipo -eq "USB") { "USB001" } else { $DispSel.Porta }
                
                Add-Printer -Name $NomeFila -DriverName $DriverSelecionado -PortName $PortaInstalacao -ErrorAction Stop
                Write-Host "`n[SUCESSO] Impressora local '$NomeFila' instalada na porta$PortaInstalacao!" -ForegroundColor Green
            } catch {
                Write-Host "[-] Falha ao adicionar impressora: ${_}" -ForegroundColor Red
            }
        }
    }
}

Function Menu-Tomate {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "       SUBMENU - ETIQUETADORAS TOMATE            " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - TOMATE MDK-20744 / MDK20744"
        Write-Host " 00 - Voltar"
        Write-Host "=================================================" -ForegroundColor DarkCyan

        $OpTomate = Read-Host "Selecione o modelo"
        switch -Regex ($OpTomate) {
            "^0?1$" {
                Baixar-E-Executar -NomeMarca "TOMATE_MDK_20744" -UrlDownload "https://github.com/user-attachments/files/32449230/TOMATE_MDK_20744BARCODE.driver.2024.01.05.1.zip" -Extensao ".zip"
                Pause
            }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

Function Start-XprinterUniversalDriver {
    $DownloadUrl = "https://github.com/brandoncarmo94/Etiquetadoras/releases/download/Xprinters/Xprinter-ExpressDelivery_2023.2_M-4.zip"
    $ZipPath = Join-Path $env:TEMP "Xprinter-ExpressDelivery_2023.2_M-4.zip"
    $ExtractPath = Join-Path $env:TEMP "Uniware-Xprinter-2023.2-M4"
    $ExpectedHash = "EDB89222E2E7F4C72B9C0C9601CEB5339B657C9C868654DFF99118345303E58E"

    try {
        Write-Host "`nBaixando o pacote universal Xprinter da GitHub Release..." -ForegroundColor Cyan
        Baixar-ArquivoComProgresso -Url $DownloadUrl -Destino $ZipPath

        $ZipStream = [System.IO.File]::OpenRead($ZipPath)
        try {
            $Byte1 = $ZipStream.ReadByte()
            $Byte2 = $ZipStream.ReadByte()
        } finally {
            $ZipStream.Dispose()
        }
        if ($Byte1 -ne 0x50 -or $Byte2 -ne 0x4B) {
            throw "O arquivo recebido nao possui um cabecalho ZIP valido."
        }

        Write-Host "Extraindo o pacote Xprinter..." -ForegroundColor Cyan
        if (Test-Path -LiteralPath $ExtractPath) {
            Remove-Item -LiteralPath $ExtractPath -Recurse -Force -ErrorAction Stop
        }
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force -ErrorAction Stop

        $DriverPath = Get-ChildItem -LiteralPath $ExtractPath -Recurse -File -Filter "ExpressDelivery_2023.2_M-4.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $DriverPath) {
            $DriverPath = Get-ChildItem -LiteralPath $ExtractPath -Recurse -File -Filter "*ExpressDelivery*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $DriverPath) {
            throw "O instalador ExpressDelivery nao foi encontrado dentro do ZIP."
        }

        Write-Host "Validando o instalador extraido..." -ForegroundColor Cyan
        $CurrentHash = (Get-FileHash -LiteralPath $DriverPath.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($CurrentHash -ne $ExpectedHash) {
            Write-Host "[BLOQUEADO] O hash do instalador Xprinter nao corresponde ao arquivo validado." -ForegroundColor Red
            Write-Host "Esperado: $ExpectedHash" -ForegroundColor Gray
            Write-Host "Encontrado: $CurrentHash" -ForegroundColor Yellow
            return
        }

        $Signature = Get-AuthenticodeSignature -LiteralPath $DriverPath.FullName
        if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
            $Signature.SignerCertificate.Subject -notmatch "Seagull Scientific") {
            Write-Host "[BLOQUEADO] A assinatura digital do driver nao foi validada." -ForegroundColor Red
            Write-Host ("Estado: {0}" -f $Signature.Status) -ForegroundColor Yellow
            return
        }

        Write-Host "[OK] Hash SHA-256 conferido." -ForegroundColor Green
        Write-Host "[OK] Assinatura digital valida: Seagull Scientific." -ForegroundColor Green
        Write-Host "Abrindo o assistente com aproximadamente 300 modelos Xprinter..." -ForegroundColor Cyan
        Start-Process -FilePath $DriverPath.FullName -ErrorAction Stop
    } catch {
        Write-Host "[ERRO] Nao foi possivel baixar, validar ou abrir o driver: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Origem: $DownloadUrl" -ForegroundColor Gray
    }
}

Function Menu-Xprinter {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "       SUBMENU - ETIQUETADORAS XPRINTER          " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " Pacote universal Seagull 2023.2.4.0"
        Write-Host " Aproximadamente 300 modelos, incluindo:" -ForegroundColor Gray
        Write-Host " XP-410B, XP-420B, XP-450B, XP-460B, XP-480B,"
        Write-Host " XP-D361B, XP-D461B, XP-T4501B e XP-TT428B."
        Write-Host "-------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " 01 - Validar e abrir o driver universal"
        Write-Host " 00 - Voltar"
        Write-Host "=================================================" -ForegroundColor DarkCyan

        $OpXprinter = Read-Host "Selecione uma opcao"
        switch -Regex ($OpXprinter) {
            "^0?1$" { Start-XprinterUniversalDriver; Pause }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

Function Show-LabelCalibrationHelp {
    Clear-Host
    Write-Host "===============================================================" -ForegroundColor DarkCyan
    Write-Host "  GUIA RAPIDO - ETIQUETAS, SENSORES E METODO DE IMPRESSAO      " -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "===============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "GAP (espaco entre etiquetas)" -ForegroundColor Cyan
    Write-Host "Use quando existe um pequeno espaco entre uma etiqueta e outra."
    Write-Host "E o formato mais comum nas etiquetas destacaveis de laboratorio."
    Write-Host ""
    Write-Host "MARCA PRETA" -ForegroundColor Cyan
    Write-Host "Use quando o verso do rolo possui uma faixa preta indicando onde"
    Write-Host "cada etiqueta comeca. O sensor procura essa faixa refletiva."
    Write-Host ""
    Write-Host "PAPEL CONTINUO" -ForegroundColor Cyan
    Write-Host "Use quando nao existe espaco nem marca entre as etiquetas."
    Write-Host "Nesse modo o avanco depende somente do tamanho configurado."
    Write-Host ""
    Write-Host "TERMICA DIRETA - SEM RIBBON" -ForegroundColor Cyan
    Write-Host "A cabeca aquece diretamente a etiqueta termica. Selecione esta"
    Write-Host "opcao quando a impressora esta sem ribbon."
    Write-Host ""
    Write-Host "TRANSFERENCIA TERMICA - COM RIBBON" -ForegroundColor Cyan
    Write-Host "A cabeca transfere a tinta do ribbon para a etiqueta. Selecione"
    Write-Host "somente quando o modelo suporta ribbon e ele esta instalado."
    Write-Host ""
    Write-Host "ATENCAO" -ForegroundColor Yellow
    Write-Host "Escolher o sensor errado pode fazer a impressora pular etiquetas,"
    Write-Host "parar no meio ou imprimir fora da posicao. Durante a calibracao,"
    Write-Host "a impressora avancara algumas etiquetas automaticamente."
    Write-Host ""
    Write-Host "MODELOS ATENDIDOS" -ForegroundColor Cyan
    Write-Host "- Xprinter e TOMATE: configuracao automatica por TSPL/TSPL2."
    Write-Host "- Zebra GC420, ZD220, ZD230 e TLP 2844-Z: configuracao por ZPL."
    Write-Host "- Zebra TLP 2844 sem o sufixo Z: calibracao manual (EPL)."
    Write-Host "- Elgin L42, L42 Pro, L42 Pro Full e L42DT: configuracao por ZPL."
    Write-Host "- Argox OS-214, OS-214plus, OS-214 Pro e OS-214EX: guia manual."
    Write-Host ""
    Write-Host "A L42DT e os modelos Zebra terminados em 'd' usam somente termica"
    Write-Host "direta. Nos modelos terminados em 't', confirme se o ribbon esta"
    Write-Host "instalado. A Elgin precisa estar usando a emulacao ZPL."
    Write-Host ""
    Write-Host "CALIBRACAO MANUAL ARGox / ZEBRA EPL" -ForegroundColor Cyan
    Write-Host "Desligue a impressora, mantenha FEED pressionado, ligue e solte"
    Write-Host "quando o motor iniciar ou a impressora comecar a imprimir o perfil."
    Write-Host "O assistente abre as preferencias para informar o tamanho e metodo."
    Pause
}

Function Initialize-UniwareRawPrinter {
    if ("UniwareRawPrinter" -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class UniwareRawPrinter
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private class DOC_INFO_1
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
    }

    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);
    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern int StartDocPrinter(IntPtr hPrinter, int level, [In] DOC_INFO_1 di);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.drv", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int count, out int written);

    public static void Send(string printerName, byte[] data, string documentName)
    {
        IntPtr printer = IntPtr.Zero;
        IntPtr unmanaged = IntPtr.Zero;
        bool documentStarted = false;
        bool pageStarted = false;
        try
        {
            if (!OpenPrinter(printerName, out printer, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Nao foi possivel abrir a fila de impressao.");

            DOC_INFO_1 doc = new DOC_INFO_1 { pDocName = documentName, pDataType = "RAW", pOutputFile = null };
            if (StartDocPrinter(printer, 1, doc) == 0)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Nao foi possivel iniciar o trabalho RAW.");
            documentStarted = true;

            if (!StartPagePrinter(printer))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Nao foi possivel iniciar a pagina RAW.");
            pageStarted = true;

            unmanaged = Marshal.AllocCoTaskMem(data.Length);
            Marshal.Copy(data, 0, unmanaged, data.Length);
            int written;
            if (!WritePrinter(printer, unmanaged, data.Length, out written) || written != data.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "O Windows nao enviou todos os comandos a impressora.");
        }
        finally
        {
            if (unmanaged != IntPtr.Zero) Marshal.FreeCoTaskMem(unmanaged);
            if (pageStarted) EndPagePrinter(printer);
            if (documentStarted) EndDocPrinter(printer);
            if (printer != IntPtr.Zero) ClosePrinter(printer);
        }
    }
}
'@
}

Function Send-UniwareRawPrinterData {
    param(
        [Parameter(Mandatory = $true)][string]$PrinterName,
        [Parameter(Mandatory = $true)][string]$Data,
        [string]$DocumentName = "Uniware - Configuracao TSPL"
    )
    Initialize-UniwareRawPrinter
    $Bytes = [System.Text.Encoding]::ASCII.GetBytes($Data)
    [UniwareRawPrinter]::Send($PrinterName,$Bytes,$DocumentName)
}

Function Read-LabelDecimal {
    param(
        [string]$Prompt,
        [double]$Minimum,
        [double]$Maximum,
        [Nullable[double]]$DefaultValue = $null
    )
    while ($true) {
        $DefaultText = if ($null -ne $DefaultValue) { " [padrao: $DefaultValue]" } else { "" }
        $InputText = Read-Host ($Prompt + $DefaultText)
        if ([string]::IsNullOrWhiteSpace($InputText) -and $null -ne $DefaultValue) {
            return [double]$DefaultValue
        }
        $InputText = $InputText.Trim().Replace(',','.')
        [double]$Value = 0
        if ([double]::TryParse($InputText,[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$Value) -and
            $Value -ge $Minimum -and $Value -le $Maximum) {
            return $Value
        }
        Write-Host ("Informe um valor entre {0} e {1}." -f $Minimum,$Maximum) -ForegroundColor Yellow
    }
}

$Global:LabelLogDir = Join-Path $PSScriptRoot "LOGS\ETIQUETADORAS"
New-Item -ItemType Directory -Force -Path $Global:LabelLogDir -ErrorAction SilentlyContinue | Out-Null

Function Write-LabelCalibrationLog {
    param([string]$Printer,[string]$Result,[string]$Details)
    $LogFile = Join-Path $Global:LabelLogDir ("Calibracao_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
    $Line = "[{0}] [{1}] Impressora={2} Usuario={3} PC={4} :: {5}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Result,$Printer,$env:USERNAME,$env:COMPUTERNAME,$Details
    try { Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8 } catch {}
}

Function Start-LabelCalibrationWizard {
    Clear-Host
    Write-Host "===============================================================" -ForegroundColor DarkCyan
    Write-Host "       CONFIGURAR E CALIBRAR ETIQUETADORA                       " -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "===============================================================" -ForegroundColor DarkCyan

    try { $Printers = @(Get-Printer -ErrorAction Stop | Sort-Object Name) }
    catch {
        Write-Host "Nao foi possivel consultar as impressoras: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    if ($Printers.Count -eq 0) {
        Write-Host "Nenhuma impressora instalada foi encontrada." -ForegroundColor Yellow
        return
    }

    Write-Host "`nImpressoras instaladas:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Printers.Count; $i++) {
        $Printer = $Printers[$i]
        $KnownLabelPrinter = ("{0} {1}" -f $Printer.Name,$Printer.DriverName) -match '(?i)Xprinter|TSPL|TSC|TOMATE|Seagull|Zebra|ZDesigner|GC420|ZD220|ZD230|TLP.?2844|Elgin|L42|Argox|OS.?214'
        $Tag = if ($KnownLabelPrinter) { " [etiquetadora provavel]" } else { "" }
        Write-Host (" [{0}] {1}{2}" -f ($i + 1),$Printer.Name,$Tag) -ForegroundColor $(if($KnownLabelPrinter){'Green'}else{'White'})
        Write-Host ("     Driver: {0} | Porta: {1} | Estado: {2}" -f $Printer.DriverName,$Printer.PortName,$Printer.PrinterStatus) -ForegroundColor Gray
    }
    Write-Host " [0] Cancelar"
    $Choice = Read-Host "Numero da etiquetadora"
    if ($Choice -eq '0') { return }
    if ($Choice -notmatch '^\d+$' -or [int]$Choice -lt 1 -or [int]$Choice -gt $Printers.Count) {
        Write-Host "Selecao invalida." -ForegroundColor Red
        return
    }
    $SelectedPrinter = $Printers[[int]$Choice - 1]

    $Models = @(
        [pscustomobject]@{Name='Xprinter / TOMATE compativel';Language='TSPL';SupportsRibbon=$true;Note='TSPL/TSPL2'},
        [pscustomobject]@{Name='Zebra TLP 2844 (EPL, sem sufixo Z)';Language='MANUAL';SupportsRibbon=$true;Note='calibracao manual'},
        [pscustomobject]@{Name='Zebra TLP 2844-Z';Language='ZPL';SupportsRibbon=$true;Note='ZPL'},
        [pscustomobject]@{Name='Zebra GC420d';Language='ZPL';SupportsRibbon=$false;Note='termica direta'},
        [pscustomobject]@{Name='Zebra GC420t';Language='ZPL';SupportsRibbon=$true;Note='termica direta ou ribbon'},
        [pscustomobject]@{Name='Zebra ZD220d / ZD230d';Language='ZPL';SupportsRibbon=$false;Note='termica direta'},
        [pscustomobject]@{Name='Zebra ZD220t / ZD230t';Language='ZPL';SupportsRibbon=$true;Note='termica direta ou ribbon'},
        [pscustomobject]@{Name='Elgin L42DT';Language='ZPL';SupportsRibbon=$false;Note='termica direta; emulacao ZPL'},
        [pscustomobject]@{Name='Elgin L42 / L42 Pro / L42 Pro Full';Language='ZPL';SupportsRibbon=$true;Note='usar emulacao ZPL'},
        [pscustomobject]@{Name='Argox OS-214 / OS-214plus / OS-214 Pro / OS-214EX';Language='MANUAL';SupportsRibbon=$true;Note='PPLA/PPLB; calibracao manual'}
    )
    Write-Host "`nFamilia/modelo da etiquetadora:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Models.Count; $i++) {
        Write-Host (" [{0}] {1} - {2}" -f ($i + 1),$Models[$i].Name,$Models[$i].Note)
    }
    Write-Host " [0] Cancelar"
    $ModelChoice = Read-Host "Selecione o modelo"
    if ($ModelChoice -eq '0') { return }
    if ($ModelChoice -notmatch '^\d+$' -or [int]$ModelChoice -lt 1 -or [int]$ModelChoice -gt $Models.Count) {
        Write-Host "Modelo invalido." -ForegroundColor Red
        return
    }
    $SelectedModel = $Models[[int]$ModelChoice - 1]
    $Language = $SelectedModel.Language

    $Identity = "{0} {1}" -f $SelectedPrinter.Name,$SelectedPrinter.DriverName
    $ExpectedPattern = switch ($Language) {
        'TSPL' { '(?i)Xprinter|TSPL|TSC|TOMATE|Seagull' }
        'ZPL'  { '(?i)Zebra|ZDesigner|GC420|ZD220|ZD230|TLP.?2844|Elgin|L42' }
        default { '(?i)TLP.?2844|Argox|OS.?214' }
    }
    if ($Identity -notmatch $ExpectedPattern) {
        Write-Host "`n[ATENCAO] O nome da fila/driver nao corresponde claramente ao modelo escolhido." -ForegroundColor Yellow
        Write-Host "Fila: $($SelectedPrinter.Name) | Driver: $($SelectedPrinter.DriverName)" -ForegroundColor Yellow
        $Continue = Read-Host "Digite 1 para continuar com o modelo escolhido ou 0 para cancelar"
        if ($Continue -ne '1') { return }
    }

    $Profiles = @(
        [pscustomobject]@{Name='60 x 40 mm';Width=60.0;Height=40.0},
        [pscustomobject]@{Name='60 x 30 mm';Width=60.0;Height=30.0},
        [pscustomobject]@{Name='60 x 25 mm';Width=60.0;Height=25.0},
        [pscustomobject]@{Name='50 x 40 mm';Width=50.0;Height=40.0},
        [pscustomobject]@{Name='50 x 30 mm';Width=50.0;Height=30.0},
        [pscustomobject]@{Name='50 x 25 mm';Width=50.0;Height=25.0},
        [pscustomobject]@{Name='40 x 40 mm';Width=40.0;Height=40.0},
        [pscustomobject]@{Name='40 x 30 mm';Width=40.0;Height=30.0},
        [pscustomobject]@{Name='40 x 25 mm';Width=40.0;Height=25.0}
    )
    Write-Host "`nPerfis de etiqueta (largura x altura):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Profiles.Count; $i++) { Write-Host (" [{0}] {1}" -f ($i + 1),$Profiles[$i].Name) }
    Write-Host " [10] Tamanho personalizado (40-60 x 25-40 mm)"
    $ProfileChoice = Read-Host "Selecione o perfil"
    if ($ProfileChoice -eq '10') {
        $Width = Read-LabelDecimal -Prompt "Largura em mm" -Minimum 40 -Maximum 60
        $Height = Read-LabelDecimal -Prompt "Altura em mm" -Minimum 25 -Maximum 40
    } elseif ($ProfileChoice -match '^\d+$' -and [int]$ProfileChoice -ge 1 -and [int]$ProfileChoice -le $Profiles.Count) {
        $Profile = $Profiles[[int]$ProfileChoice - 1]
        $Width = $Profile.Width
        $Height = $Profile.Height
    } else {
        Write-Host "Perfil invalido." -ForegroundColor Red
        return
    }

    Write-Host "`nSensor do rolo:" -ForegroundColor Cyan
    Write-Host " [1] GAP - espaco entre etiquetas (recomendado para laboratorio)"
    Write-Host " [2] Marca preta no verso"
    Write-Host " [3] Papel continuo"
    $SensorChoice = Read-Host "Selecione o sensor"
    switch ($SensorChoice) {
        '1' { $Sensor='GAP'; $SensorSize=Read-LabelDecimal -Prompt "Espaco GAP em mm" -Minimum 1 -Maximum 10 -DefaultValue 2 }
        '2' { $Sensor='BLACKMARK'; $SensorSize=Read-LabelDecimal -Prompt "Largura da marca preta em mm" -Minimum 1 -Maximum 10 -DefaultValue 2 }
        '3' { $Sensor='CONTINUOUS'; $SensorSize=0.0 }
        default { Write-Host "Sensor invalido." -ForegroundColor Red; return }
    }

    if ($SelectedModel.SupportsRibbon) {
        Write-Host "`nMetodo de impressao:" -ForegroundColor Cyan
        Write-Host " [1] Termica direta - sem ribbon"
        Write-Host " [2] Transferencia termica - com ribbon"
        $MethodChoice = Read-Host "Selecione o metodo"
        switch ($MethodChoice) {
            '1' { $Ribbon='OFF'; $MethodName='TERMICA DIRETA' }
            '2' { $Ribbon='ON'; $MethodName='COM RIBBON' }
            default { Write-Host "Metodo invalido." -ForegroundColor Red; return }
        }
    } else {
        $Ribbon='OFF'
        $MethodName='TERMICA DIRETA'
        Write-Host "`n[INFO] Este modelo usa somente termica direta; ribbon foi desativado." -ForegroundColor Cyan
    }

    $Speed = [int](Read-LabelDecimal -Prompt "Velocidade de impressao (2 a 6)" -Minimum 2 -Maximum 6 -DefaultValue 3)
    $Density = [int](Read-LabelDecimal -Prompt "Intensidade (0 clara, 15 escura)" -Minimum 0 -Maximum 15 -DefaultValue 8)
    Write-Host "`nOrientacao:" -ForegroundColor Cyan
    Write-Host " [1] Normal"
    Write-Host " [2] Invertida 180 graus"
    $DirectionChoice = Read-Host "Selecione a orientacao"
    if ($DirectionChoice -notin @('1','2')) { Write-Host "Orientacao invalida." -ForegroundColor Red; return }
    $Direction = if ($DirectionChoice -eq '2') { 1 } else { 0 }

    $Culture = [System.Globalization.CultureInfo]::InvariantCulture
    $W = $Width.ToString('0.##',$Culture)
    $H = $Height.ToString('0.##',$Culture)
    $S = $SensorSize.ToString('0.##',$Culture)
    $Commands = New-Object System.Collections.Generic.List[string]
    if ($Language -eq 'TSPL') {
        $Commands.Add("SET RIBBON $Ribbon")
        $Commands.Add("SIZE $W mm,$H mm")
        $Commands.Add("SPEED $Speed")
        $Commands.Add("DENSITY $Density")
        $Commands.Add("DIRECTION $Direction")
        $Commands.Add("SET TEAR ON")
        switch ($Sensor) {
            'GAP'       { $Commands.Add("GAP $S mm,0 mm"); $Commands.Add('GAPDETECT') }
            'BLACKMARK' { $Commands.Add("BLINE $S mm,0 mm"); $Commands.Add('BLINEDETECT') }
            'CONTINUOUS'{ $Commands.Add('GAP 0 mm,0 mm') }
        }
    } elseif ($Language -eq 'ZPL') {
        $WidthDots = [int][math]::Round($Width * 8)
        $HeightDots = [int][math]::Round($Height * 8)
        $ZplMedia = switch ($Sensor) { 'GAP' {'Y'} 'BLACKMARK' {'M'} default {'N'} }
        $ZplMethod = if ($Ribbon -eq 'ON') { 'T' } else { 'D' }
        $ZplOrientation = if ($Direction -eq 1) { 'I' } else { 'N' }
        $ZplDarkness = [math]::Min(30,($Density * 2))
        $Commands.Add('^XA')
        $Commands.Add("^MN$ZplMedia")
        $Commands.Add("^MT$ZplMethod")
        $Commands.Add("^PW$WidthDots")
        $Commands.Add("^LL$HeightDots")
        $Commands.Add("^PR$Speed")
        $Commands.Add("~SD$ZplDarkness")
        $Commands.Add("^PO$ZplOrientation")
        $Commands.Add('^XZ')
        $Commands.Add('~JC')
    }
    $RawConfiguration = ($Commands -join "`r`n") + "`r`n"

    Write-Host "`nResumo antes do envio:" -ForegroundColor Cyan
    Write-Host (" Impressora : {0}" -f $SelectedPrinter.Name)
    Write-Host (" Modelo     : {0}" -f $SelectedModel.Name)
    Write-Host (" Protocolo  : {0}" -f $(if($Language -eq 'MANUAL'){'MANUAL / DRIVER'}else{$Language}))
    Write-Host (" Driver     : {0}" -f $SelectedPrinter.DriverName)
    Write-Host (" Porta      : {0}" -f $SelectedPrinter.PortName)
    Write-Host (" Etiqueta   : {0} x {1} mm" -f $W,$H)
    Write-Host (" Sensor     : {0}{1}" -f $Sensor,$(if($SensorSize -gt 0){" ($S mm)"}else{""}))
    Write-Host (" Metodo     : {0}" -f $MethodName)
    Write-Host (" Velocidade : {0} | Intensidade: {1} | Direcao: {2}" -f $Speed,$Density,$Direction)
    if ($Language -eq 'MANUAL') {
        Write-Host "O assistente abrira as preferencias e exibira a calibracao pelo botao FEED." -ForegroundColor Yellow
    } else {
        Write-Host "A calibracao pode avancar algumas etiquetas." -ForegroundColor Yellow
    }
    $Confirm = Read-Host "Digite 1 para CONTINUAR ou 0 para cancelar"
    if ($Confirm -ne '1') {
        Write-Host "Operacao cancelada. Nenhum comando foi enviado." -ForegroundColor Yellow
        return
    }

    if ($Language -eq 'MANUAL') {
        Write-Host "`nCALIBRACAO MANUAL PARA $($SelectedModel.Name)" -ForegroundColor Cyan
        Write-Host " 1. Carregue corretamente o rolo e feche a tampa."
        Write-Host " 2. Desligue a impressora."
        Write-Host " 3. Mantenha o botao FEED pressionado e ligue a impressora."
        Write-Host " 4. Solte FEED quando o motor iniciar ou o perfil comecar a imprimir."
        Write-Host " 5. Nas preferencias, defina $W x $H mm, sensor $Sensor e $MethodName."
        Write-Host " 6. Depois da calibracao, pressione FEED uma vez e confirme um avanco correto."
        try {
            $PrintUiArgs = 'printui.dll,PrintUIEntry /e /n "{0}"' -f $SelectedPrinter.Name
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\rundll32.exe') -ArgumentList $PrintUiArgs -ErrorAction Stop
            Write-Host "`n[OK] Preferencias da impressora abertas." -ForegroundColor Green
            Write-LabelCalibrationLog -Printer $SelectedPrinter.Name -Result 'MANUAL-ORIENTADO' -Details ("Modelo={0}; Driver={1}; Porta={2}; Tamanho={3}x{4}mm; Sensor={5}; Metodo={6}" -f $SelectedModel.Name,$SelectedPrinter.DriverName,$SelectedPrinter.PortName,$W,$H,$Sensor,$MethodName)
        } catch {
            Write-Host "`n[ERRO] Nao foi possivel abrir as preferencias: $($_.Exception.Message)" -ForegroundColor Red
            Write-LabelCalibrationLog -Printer $SelectedPrinter.Name -Result 'ERRO-PREFERENCIAS' -Details $_.Exception.Message
        }
        return
    }

    try {
        Send-UniwareRawPrinterData -PrinterName $SelectedPrinter.Name -Data $RawConfiguration -DocumentName "Uniware - Aplicar perfil e calibrar"
        Write-Host "`n[OK] Perfil e comando de calibracao enviados ao spooler." -ForegroundColor Green
        Write-LabelCalibrationLog -Printer $SelectedPrinter.Name -Result 'ENVIADO' -Details ("Modelo={0}; Protocolo={1}; Driver={2}; Porta={3}; Tamanho={4}x{5}mm; Sensor={6}; SensorSize={7}; Metodo={8}; Speed={9}; Density={10}; Direction={11}" -f $SelectedModel.Name,$Language,$SelectedPrinter.DriverName,$SelectedPrinter.PortName,$W,$H,$Sensor,$S,$MethodName,$Speed,$Density,$Direction)
    } catch {
        Write-Host "`n[ERRO] Falha ao enviar os comandos: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Confirme se a fila esta online e se o driver/modelo aceita $Language." -ForegroundColor Gray
        Write-LabelCalibrationLog -Printer $SelectedPrinter.Name -Result 'ERRO' -Details $_.Exception.Message
        return
    }

    $PrintTest = Read-Host "Digite 1 para imprimir uma etiqueta de teste ou 0 para finalizar"
    if ($PrintTest -eq '1') {
        if ($Language -eq 'TSPL') {
            $TestLines = New-Object System.Collections.Generic.List[string]
            foreach ($Line in $Commands | Where-Object { $_ -notin @('GAPDETECT','BLINEDETECT') }) { $TestLines.Add($Line) }
            $TestLines.Add('CLS')
            $TestLines.Add('TEXT 12,12,"2",0,1,1,"UNIWARE TESTE"')
            $TestLines.Add(('TEXT 12,42,"2",0,1,1,"{0}x{1} {2}"' -f $W,$H,$Sensor))
            $TestLines.Add(('TEXT 12,72,"2",0,1,1,"{0}"' -f $MethodName))
            $TestLines.Add(('TEXT 12,102,"2",0,1,1,"{0}"' -f (Get-Date -Format 'dd/MM/yyyy HH:mm')))
            $TestLines.Add('PRINT 1,1')
        } else {
            $TestLines = New-Object System.Collections.Generic.List[string]
            $TestLines.Add('^XA')
            $TestLines.Add("^PW$WidthDots")
            $TestLines.Add("^LL$HeightDots")
            $TestLines.Add('^FO12,12^A0N,26,26^FDUNIWARE TESTE^FS')
            $TestLines.Add(('^FO12,45^A0N,20,20^FD{0}x{1} {2}^FS' -f $W,$H,$Sensor))
            $TestLines.Add(('^FO12,72^A0N,20,20^FD{0}^FS' -f $MethodName))
            $TestLines.Add(('^FO12,99^A0N,18,18^FD{0}^FS' -f (Get-Date -Format 'dd/MM/yyyy HH:mm')))
            $TestLines.Add('^XZ')
        }
        try {
            Send-UniwareRawPrinterData -PrinterName $SelectedPrinter.Name -Data (($TestLines -join "`r`n") + "`r`n") -DocumentName "Uniware - Etiqueta de teste"
            Write-Host "[OK] Etiqueta de teste enviada." -ForegroundColor Green
            Write-LabelCalibrationLog -Printer $SelectedPrinter.Name -Result 'TESTE-ENVIADO' -Details ("Tamanho={0}x{1}mm" -f $W,$H)
        } catch {
            Write-Host "[ERRO] Nao foi possivel enviar a etiqueta de teste: $($_.Exception.Message)" -ForegroundColor Red
            Write-LabelCalibrationLog -Printer $SelectedPrinter.Name -Result 'ERRO-TESTE' -Details $_.Exception.Message
        }
    }
}

Function Menu-LabelCalibration {
    while ($true) {
        Clear-Host
        Write-Host "===============================================================" -ForegroundColor DarkCyan
        Write-Host "       CONFIGURACAO E CALIBRACAO DE ETIQUETADORAS              " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "===============================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Entender GAP, marca preta, papel continuo e ribbon"
        Write-Host " 02 - Identificar impressora, aplicar perfil e calibrar"
        Write-Host " 00 - Voltar"
        Write-Host "===============================================================" -ForegroundColor DarkCyan
        $Option = Read-Host "Selecione uma opcao"
        switch -Regex ($Option) {
            '^0?1$' { Show-LabelCalibrationHelp }
            '^0?2$' { Start-LabelCalibrationWizard; Pause }
            '^0?0$' { return }
            default { Write-Host "Opcao invalida." -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}

Function Menu-Etiquetadoras {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "            SUBMENU - ETIQUETADORAS              " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Utilitarios e Drivers Zebra"
        Write-Host " 02 - Driver Elgin L42 Pro"
        Write-Host " 03 - TOMATE (Modelos)"
        Write-Host " 04 - XPRINTERS (Driver universal)"
        Write-Host " 05 - Configurar e calibrar etiquetadoras"
        Write-Host " 00 - Voltar ao Menu Principal"
        Write-Host "=================================================" -ForegroundColor DarkCyan
        
        $OpSub = Read-Host "Selecione uma opcao"
        switch -Regex ($OpSub) {
            "^0?1$" {
                Write-Host "`nBaixando instalador Zebra..." -ForegroundColor Cyan
                $ZipDestino = "$env:TEMP\zebra_repo.zip"
                $PastaExtracao = "$env:TEMP\ZebraExtraido"
                $UrlZebra = "https://www.zebra.com/content/dam/support-dam/en/driver/unrestricted/0002/zsu-1191327.zip" 

                try {
                    Baixar-ArquivoComProgresso -Url $UrlZebra -Destino $ZipDestino
                    Write-Host "Extraindo arquivos..." -ForegroundColor Green

                    if (Test-Path $PastaExtracao) { Remove-Item $PastaExtracao -Recurse -Force }
                    Expand-Archive -Path $ZipDestino -DestinationPath $PastaExtracao -Force
                    
                    $Instalador = Get-ChildItem -Path $PastaExtracao -Recurse -Include *.exe, *.msi | Select-Object -First 1

                    if ($Instalador) {
                        Write-Host "Abrindo instalador Zebra: $($Instalador.Name)..." -ForegroundColor Yellow
                        Start-Process -FilePath $Instalador.FullName
                    } else {
                        Write-Host "[-] Nenhum executavel localizado no arquivo ZIP." -ForegroundColor Red
                    }
                } catch { Write-Host "`nErro ao processar Zebra: ${_}" -ForegroundColor Red }
                Pause
            }
            "^0?2$" {
                Write-Host "`nBaixando driver Elgin L42 Pro..." -ForegroundColor Cyan
                $ZipDestino = "$env:TEMP\Driver_Elgin_L42Pro.zip"
                $PastaExtracao = "$env:TEMP\ElginExtraido"
                $UrlElgin = "https://www.bztech.com.br/arquivos/driver-elgin-l42.zip"

                try {
                    Baixar-ArquivoComProgresso -Url $UrlElgin -Destino $ZipDestino
                    Write-Host "Extraindo o ZIP..." -ForegroundColor Green

                    if (Test-Path $PastaExtracao) { Remove-Item $PastaExtracao -Recurse -Force }
                    Expand-Archive -Path $ZipDestino -DestinationPath $PastaExtracao -Force
                    
                    $CaminhoDriverSeagull = Join-Path $PastaExtracao "*Driver L42 (Seagull BarTender*)"
                    $Instalador = Get-ChildItem -Path $CaminhoDriverSeagull -Recurse -Include *.exe, *.msi -ErrorAction SilentlyContinue | Select-Object -First 1

                    if (-not $Instalador) {
                        $Instalador = Get-ChildItem -Path $PastaExtracao -Recurse -Include *Elgin*.exe, *Seagull*.exe, *Driver*.exe | Select-Object -First 1
                    }

                    if ($Instalador) {
                        Write-Host "Iniciando o instalador Elgin: $($Instalador.Name)..." -ForegroundColor Yellow
                        Start-Process -FilePath $Instalador.FullName
                    } else {
                        Write-Host "[-] Executavel nao encontrado." -ForegroundColor Red
                    }
                } catch { Write-Host "`nErro ao processar Elgin: ${_}" -ForegroundColor Red }
                Pause
            }
            "^0?3$" { Menu-Tomate }
            "^0?4$" { Menu-Xprinter }
            "^0?5$" { Menu-LabelCalibration }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

Function Menu-Cupons {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "          SUBMENU - IMPRESSORAS CUPONS          " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Driver Epson TM-T20"
        Write-Host " 02 - Driver Elgin i9"
        Write-Host " 03 - Driver Elgin i8"
        Write-Host " 04 - Driver Bematech MP-4200 TH"
        Write-Host " 00 - Voltar ao Menu Principal"
        Write-Host "=================================================" -ForegroundColor DarkCyan
        
        $OpSub = Read-Host "Selecione uma opcao"
        switch -Regex ($OpSub) {
            "^0?1$" {
                Write-Host "`nBaixando instalador Epson TM-T20..." -ForegroundColor Cyan
                $Destino = "$env:USERPROFILE\Downloads\TM-T20II-Utility_1.20.exe"
                $UrlEpson = "https://ftp.epson.com/drivers/pos/TM-T20II-Utility_1.20.exe"

                try {
                    Baixar-ArquivoComProgresso -Url $UrlEpson -Destino $Destino
                    Write-Host "Iniciando instalador Epson..." -ForegroundColor Yellow
                    Start-Process -FilePath $Destino
                } catch { Write-Host "`nErro ao baixar/executar Epson: ${_}" -ForegroundColor Red }
                Pause
            }
            "^0?2$" {
                Baixar-E-Executar -NomeMarca "Elgin_i9" -UrlDownload "https://www.bztech.com.br/arquivos/driver-elgin-i7-i8-e-i9-windows-e-linux.zip"
                Pause
            }
            "^0?3$" {
                Baixar-E-Executar -NomeMarca "Elgin_i8" -UrlDownload "https://www.bztech.com.br/arquivos/driver-elgin-i8-windows.zip"
                Pause
            }
            "^0?4$" {
                Baixar-E-Executar -NomeMarca "Bematech_MP4200" -UrlDownload "https://www.bztech.com.br/arquivos/driver-bematech-mp-4200.zip"
                Pause
            }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

Function Abrir-PaginaDriverOficial {
    param(
        [Parameter(Mandatory = $true)][string]$Marca,
        [Parameter(Mandatory = $true)][string]$Modelo,
        [Parameter(Mandatory = $true)][string]$Url
    )

    Write-Host "`nAbrindo o download oficial: $Marca $Modelo" -ForegroundColor Cyan
    Write-Host "A pagina do fabricante seleciona o pacote correto para a versao do Windows." -ForegroundColor Gray
    Write-Host "Se o download nao iniciar automaticamente, escolha Windows e clique em Download." -ForegroundColor Gray
    try {
        Start-Process -FilePath $Url -ErrorAction Stop
        Write-Host "[OK] Pagina oficial aberta no navegador." -ForegroundColor Green
    } catch {
        Write-Host "[ERRO] Nao foi possivel abrir a pagina oficial: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "URL: $Url" -ForegroundColor Yellow
    }
}

Function Menu-HP {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "            SUBMENU - MODELOS HP                 " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - HP Smart Tank 581 / 583 / 589"
        Write-Host " 02 - HP DeskJet Ink Advantage 2874 / 2975"
        Write-Host " 03 - HP Laser MFP 135w / 135a"
        Write-Host " 04 - HP Laser 107w"
        Write-Host " 05 - HP LaserJet Pro P1102w / serie P1100"
        Write-Host " 06 - HP Laser serie 408 / 408dn"
        Write-Host " 00 - Voltar ao Menu Anterior"
        Write-Host "=================================================" -ForegroundColor DarkCyan
        
        $OpHP = Read-Host "Selecione o modelo da HP"
        switch -Regex ($OpHP) {
            "^0?1$" { Abrir-PaginaDriverOficial -Marca "HP" -Modelo "Smart Tank serie 580" -Url "https://support.hp.com/br-pt/drivers/hp-smart-tank-580-all-in-one-printer/model/2101277335"; Pause }
            "^0?2$" { Abrir-PaginaDriverOficial -Marca "HP" -Modelo "DeskJet serie 2800" -Url "https://support.hp.com/br-pt/drivers/hp-deskjet-2800-all-in-one-printer-series/2101374533"; Pause }
            "^0?3$" { Abrir-PaginaDriverOficial -Marca "HP" -Modelo "Laser MFP serie 135" -Url "https://support.hp.com/br-pt/drivers/hp-laser-mfp-130-printer-series/24494378"; Pause }
            "^0?4$" { Abrir-PaginaDriverOficial -Marca "HP" -Modelo "Laser 107w" -Url "https://support.hp.com/br-pt/drivers/hp-laser-100-printer-series/model/24494340"; Pause }
            "^0?5$" { Abrir-PaginaDriverOficial -Marca "HP" -Modelo "LaserJet Pro P1102w" -Url "https://support.hp.com/br-pt/drivers/hp-laserjet-pro-p1102-printer-series/model/4110306"; Pause }
            "^0?6$" { Abrir-PaginaDriverOficial -Marca "HP" -Modelo "Laser serie 408 / 408dn" -Url "https://support.hp.com/br-pt/drivers/hp-laser-408-printer-series/31291471"; Pause }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}


Function Menu-Brother {
    $UrlHL1200 = "https://support.brother.com/g/b/downloadhowto.aspx?c=us_ot&lang=en&prod=hl1200_us_as&os=10013&dlid=dlf107160_000&flang=4&type3=11"

    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "             SUBMENU - BROTHER                   " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Brother HL-1200"
        Write-Host " 02 - Brother DCP-T720DW"
        Write-Host " 03 - Brother DCP-L2540DW"
        Write-Host " 00 - Voltar"
        Write-Host "=================================================" -ForegroundColor DarkCyan

        $OpBrother = Read-Host "Selecione uma opcao"
        switch -Regex ($OpBrother) {
            "^0?1$" {
                Write-Host "`nAbrindo pagina oficial do driver Brother HL-1200..." -ForegroundColor Cyan
                Write-Host "Conclua o download e a instalacao pelo navegador." -ForegroundColor Gray
                try {
                    Start-Process $UrlHL1200
                } catch {
                    Write-Host "[-] Nao foi possivel abrir o navegador: $_" -ForegroundColor Red
                }
                Pause
            }
            "^0?2$" {
                Abrir-PaginaDriverOficial -Marca "Brother" -Modelo "DCP-T720DW" -Url "https://support.brother.com/g/b/downloadtop.aspx?c=br&lang=pt&prod=dcpt720dw_all"
                Pause
            }
            "^0?3$" {
                Abrir-PaginaDriverOficial -Marca "Brother" -Modelo "DCP-L2540DW" -Url "https://support.brother.com/g/b/downloadtop.aspx?c=br&lang=pt&prod=dcpl2540dw_us_as"
                Pause
            }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

Function Menu-Epson {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "              SUBMENU - EPSON                    " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Epson EcoTank L3150"
        Write-Host " 02 - Epson EcoTank L3250"
        Write-Host " 00 - Voltar"
        Write-Host "=================================================" -ForegroundColor DarkCyan

        $OpEpson = Read-Host "Selecione uma opcao"
        switch -Regex ($OpEpson) {
            "^0?1$" { Abrir-PaginaDriverOficial -Marca "Epson" -Modelo "EcoTank L3150" -Url "https://epson.com.br/Suporte/Impressoras/Impressoras-multifuncionais/Epson-L/Epson-L3150/s/SPT_C11CG86301"; Pause }
            "^0?2$" { Abrir-PaginaDriverOficial -Marca "Epson" -Modelo "EcoTank L3250" -Url "https://epson.com.br/Suporte/Impressoras/Impressoras-multifuncionais/Epson-L/Epson-L3250/s/SPT_C11CJ67301"; Pause }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

Function Menu-Lexmark {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "             SUBMENU - LEXMARK                   " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Lexmark MX510de / familia MX510"
        Write-Host " 00 - Voltar"
        Write-Host "=================================================" -ForegroundColor DarkCyan

        $OpLexmark = Read-Host "Selecione uma opcao"
        switch -Regex ($OpLexmark) {
            "^0?1$" { Abrir-PaginaDriverOficial -Marca "Lexmark" -Modelo "MX510de / familia MX510" -Url "https://support.lexmark.com/pt_br/drivers-downloads.html"; Pause }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

Function Menu-Graficas {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "         SUBMENU - IMPRESSORAS GRAFICAS          " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - HP (Modelos)"
        Write-Host " 02 - EPSON"
        Write-Host " 03 - Brother"
        Write-Host " 04 - Canon"
        Write-Host " 05 - Lexmark"
        Write-Host " 06 - Kyocera"
        Write-Host " 07 - Ricoh"
        Write-Host " 08 - Pantum"
        Write-Host " 00 - Voltar ao Menu Principal"
        Write-Host "=================================================" -ForegroundColor DarkCyan
        
        $OpSub = Read-Host "Selecione uma opcao"
        switch -Regex ($OpSub) {
            "^0?1$" { Menu-HP }
            "^0?2$" { Menu-Epson }
            "^0?3$" { Menu-Brother }
            "^0?4$" { Abrir-PaginaDriverOficial -Marca "Canon" -Modelo "Central oficial de drivers" -Url "https://websupport.canon.com.br/"; Pause }
            "^0?5$" { Menu-Lexmark }
            "^0?6$" { Abrir-PaginaDriverOficial -Marca "Kyocera" -Modelo "Central oficial de downloads" -Url "https://www.kyoceradocumentsolutions.com.br/pt/support/downloads.html"; Pause }
            "^0?7$" { Abrir-PaginaDriverOficial -Marca "Ricoh" -Modelo "Central oficial de suporte e downloads" -Url "https://www.ricoh-americalatina.com/pt/suporte-e-download"; Pause }
            "^0?8$" { Abrir-PaginaDriverOficial -Marca "Pantum" -Modelo "Central oficial de drivers" -Url "https://www.pantum.com.br/support/download/update"; Pause }
            "^0?0$" { return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}



# ---------------------------------------------------------------------
# LOG DETALHADO - OTIMIZACAO E MANUTENCAO
# ---------------------------------------------------------------------
$Global:MaintenanceLogDir = Join-Path $PSScriptRoot "LOGS\MANUTENCAO"
New-Item -ItemType Directory -Force $Global:MaintenanceLogDir -ErrorAction SilentlyContinue | Out-Null
$Global:MaintenanceLogFile = Join-Path $Global:MaintenanceLogDir ("Manutencao_{0}_{1}.log" -f $env:COMPUTERNAME,(Get-Date -Format "yyyyMMdd_HHmmss"))

Function Write-MaintenanceLog {
    param(
        [string]$Action,
        [string]$Status = "INFO",
        [string]$Details = ""
    )
    $line = "[{0}] [{1}] [{2}] Usuario={3} PC={4} :: {5}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Status,$Action,$env:USERNAME,$env:COMPUTERNAME,$Details
    try { Add-Content -Path $Global:MaintenanceLogFile -Value $line -Encoding UTF8 } catch {}
}

Function Get-MaintenanceSnapshot {
    param([string]$Stage)
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB,2)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB,2)
        $usedGB = [math]::Round($totalGB-$freeGB,2)
        $usedPct = if($totalGB -gt 0){[math]::Round(($usedGB/$totalGB)*100,1)}else{0}
        $diskFree = if($disk){[math]::Round($disk.FreeSpace/1GB,2)}else{0}
        $diskTotal = if($disk){[math]::Round($disk.Size/1GB,2)}else{0}
        $power = (powercfg /getactivescheme 2>$null) -join " "
        Write-MaintenanceLog "SNAPSHOT-$Stage" "INFO" ("Windows='{0}' Build={1}; CPU='{2}'; RAM={3}GB usada={4}GB livre={5}GB ({6}%); DiscoC={7}GB livre/{8}GB; Energia='{9}'" -f $os.Caption,$os.BuildNumber,$cpu.Name,$totalGB,$usedGB,$freeGB,$usedPct,$diskFree,$diskTotal,$power)
    } catch {
        Write-MaintenanceLog "SNAPSHOT-$Stage" "ERRO" $_.Exception.Message
    }
}

Function Show-MaintenanceLog {
    Show-UniwareHeader
    UI-Center "LOGS DE OTIMIZACAO E MANUTENCAO" Cyan
    UI-Border
    Write-Host ""
    Write-Host " Log atual:" -ForegroundColor Cyan
    Write-Host " $Global:MaintenanceLogFile" -ForegroundColor Gray
    Write-Host ""
    if(Test-Path $Global:MaintenanceLogFile){
        Get-Content $Global:MaintenanceLogFile -Tail 35 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    } else {
        Write-Host " Nenhum log gerado nesta sessao." -ForegroundColor Yellow
    }
    Write-Host ""
    Read-Host " Pressione ENTER para voltar" | Out-Null
}

Write-MaintenanceLog "INICIO" "OK" ("Utilitario iniciado. PowerShell={0}; Admin={1}" -f $PSVersionTable.PSVersion,([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Get-MaintenanceSnapshot "INICIAL"

# ---------------------------------------------------------------------
# OTIMIZACAO E MANUTENCAO - integrado do Otimizador Uniware v0.3.1
# ---------------------------------------------------------------------
$OptState = Join-Path $PSScriptRoot "ESTADO"
$OptLogs  = Join-Path $PSScriptRoot "LOGS"
New-Item -ItemType Directory -Force $OptState,$OptLogs -ErrorAction SilentlyContinue | Out-Null
$OptLogFile = Join-Path $OptLogs ("Otimizador_"+(Get-Date -Format yyyyMMdd_HHmmss)+".log")

function Opt-Size($n){if($n-ge 1GB){"{0:N2} GB"-f($n/1GB)}elseif($n-ge 1MB){"{0:N2} MB"-f($n/1MB)}else{"{0:N2} KB"-f($n/1KB)}}
function Opt-FolderSize($p){if(Test-Path $p){[int64]((Get-ChildItem $p -Force -Recurse -File|Measure-Object Length -Sum).Sum)}else{0}}
function Opt-Opt-Targets{@(
 [pscustomobject]@{N="TEMP do usuario";P=$env:TEMP},
 [pscustomobject]@{N="Windows Temp";P=(Join-Path $env:WINDIR "Temp")},
 [pscustomobject]@{N="Prefetch";P=(Join-Path $env:WINDIR "Prefetch")}
)}
function Opt-Opt-Analyze{
 Clear-Host; Write-Host "=== UNILAB - ANALISE DE LIMPEZA ===" -ForegroundColor Cyan
 $a=@();[int64]$total=0
 foreach($t in Opt-Targets){$z=Opt-FolderSize $t.P;$total+=$z;$a+=[pscustomobject]@{N=$t.N;P=$t.P;Z=$z};Write-Host ("{0,-28} {1}"-f $t.N,(Opt-Size $z))}
 [int64]$bin=0
 try{$sh=New-Object -ComObject Shell.Application;foreach($i in $sh.Namespace(0xA).Items()){$bin+=[int64]$i.Size}}catch{}
 $total+=$bin;Write-Host ("{0,-28} {1}"-f "Lixeira",(Opt-Size $bin))
 Write-Host "`nPotencialmente liberavel: $(Opt-Size $total)" -ForegroundColor Yellow
 Write-Host "Downloads, Documentos e Desktop NAO serao apagados." -ForegroundColor DarkGray
 [pscustomobject]@{Total=$total;Items=$a}
}
function Opt-Clean{
  Write-MaintenanceLog "LIMPEZA" "INICIO" "Solicitada limpeza de TEMP, Windows Temp, Prefetch e Lixeira."
  Get-MaintenanceSnapshot "ANTES-LIMPEZA"
 $x=Opt-Analyze
 if((Read-Host "`nExecutar limpeza? [S/N]")-notmatch'^[Ss]$'){return}
 [int64]$before=$x.Total
 foreach($t in Opt-Targets){
   if(Test-Path $t.P){
     Get-ChildItem $t.P -Force -ErrorAction SilentlyContinue |
       Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
   }
 }
 try{Clear-RecycleBin -Force -ErrorAction SilentlyContinue}catch{}
 Start-Sleep -Milliseconds 500
 [int64]$remaining=0
 foreach($t in Opt-Targets){$remaining+=Opt-FolderSize $t.P}
 [int64]$freed=[Math]::Max(0,($before-$remaining))
 Clear-Host
 Write-Host "=== LIMPEZA CONCLUIDA ===" -ForegroundColor Green
 Write-Host ("Antes.................. {0}" -f (Opt-Size $before))
 Write-Host ("Restante............... {0}" -f (Opt-Size $remaining))
 Write-Host ("Liberado............... {0}" -f (Opt-Size $freed)) -ForegroundColor Green
 Write-Host "`nArquivos bloqueados/em uso foram ignorados." -ForegroundColor DarkGray
 Opt-Log "Limpeza executada. Antes=$(Opt-Size $before); Restante=$(Opt-Size $remaining); Liberado=$(Opt-Size $freed)"
 Opt-Pause
}
function Opt-Opt-ActiveGuid{$o=powercfg /getactivescheme|Out-String;if($o-match'([A-Fa-f0-9-]{36})'){$matches[1]}}
function Opt-Opt-SavePower{$g=Opt-ActiveGuid;if($g){Set-Content (Join-Path $OptState "PlanoAnterior.txt") $g};$g}
function Opt-High{
  Write-MaintenanceLog "ALTO-DESEMPENHO" "INICIO" "Solicitada alteracao do plano de energia."
 $old=Opt-SavePower;$hi="8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";powercfg /setactive $hi|Out-Null
 if((Opt-ActiveGuid)-ne$hi){$o=powercfg -duplicatescheme $hi|Out-String;if($o-match'([A-Fa-f0-9-]{36})'){powercfg /setactive $matches[1]|Out-Null}}
 Write-Host "Plano anterior: $old";Write-Host "Plano ativo: $(Opt-ActiveGuid)" -ForegroundColor Green;Opt-Log "Alto desempenho aplicado";Opt-Pause
}
function Opt-Weak{
  Write-MaintenanceLog "PC-FRACO" "INICIO" "Solicitada otimizacao visual e plano de energia."
  Get-MaintenanceSnapshot "ANTES-PC-FRACO"
 Clear-Host;Write-Host "=== MODO PC FRACO ===" -ForegroundColor Cyan
 Write-Host "Aplica Alto Desempenho e reduz efeitos visuais."
 Write-Host "NAO desativa Defender, Update, Spooler ou rede." -ForegroundColor Green
 if((Read-Host "Aplicar? [S/N]")-notmatch'^[Ss]$'){return}
 Opt-SavePower|Out-Null
 reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" (Join-Path $OptState "Visual.reg") /y|Out-Null
 reg export "HKCU\Control Panel\Desktop\WindowMetrics" (Join-Path $OptState "Window.reg") /y|Out-Null
 $hi="8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";powercfg /setactive $hi|Out-Null
 New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Force|Out-Null
 Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" VisualFXSetting 2
 New-Item "HKCU:\Control Panel\Desktop\WindowMetrics" -Force|Out-Null
 Set-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" MinAnimate "0"
 Write-Host "Modo PC Fraco aplicado. Alguns efeitos exigem novo logon." -ForegroundColor Green;Opt-Log "PC Fraco aplicado";Opt-Pause
}
function Opt-Restore{
  Write-MaintenanceLog "RESTAURACAO" "INICIO" "Solicitada restauracao das configuracoes salvas."
 $f=Join-Path $OptState "PlanoAnterior.txt";if(Test-Path$f){powercfg /setactive ((Get-Content$f -Raw).Trim())|Out-Null;Write-Host "Plano anterior restaurado." -ForegroundColor Green}
 foreach($n in "Visual.reg","Window.reg"){$p=Join-Path $OptState $n;if(Test-Path$p){reg import $p|Out-Null}}
 Write-Host "Restauracao concluida. Efeitos visuais podem exigir novo logon." -ForegroundColor Green;Opt-Log "Restauracao executada";Opt-Pause
}

function Opt-GetMemoryInfo{
 $os=Get-CimInstance Win32_OperatingSystem
 [int64]$total=$os.TotalVisibleMemorySize*1KB
 [int64]$free=$os.FreePhysicalMemory*1KB
 [int64]$used=$total-$free
 [pscustomobject]@{Total=$total;Used=$used;Free=$free;Pct=[math]::Round(($used/$total)*100,1)}
}
function Opt-TopMemory{
 Clear-Host;Write-Host "=== MAIORES CONSUMIDORES DE RAM ===" -ForegroundColor Cyan
 Get-Process|Sort-Object WorkingSet64 -Descending|Select-Object -First 12 `
  @{N="Processo";E={$_.ProcessName}},@{N="PID";E={$_.Id}},@{N="RAM_MB";E={[math]::Round($_.WorkingSet64/1MB,1)}}|Format-Table -AutoSize
 Opt-Pause
}
function Opt-ReduceMemory{
  Write-MaintenanceLog "MEMORIA" "INICIO" "Solicitada liberacao manual de working sets."
  Get-MaintenanceSnapshot "ANTES-MEMORIA"
 Clear-Host;Write-Host "=== UNILAB - LIBERAR MEMORIA ===" -ForegroundColor Cyan
 $before=Opt-GetMemoryInfo
 Write-Host ("Antes: {0} usados ({1}%) | {2} disponiveis" -f (Opt-Size $before.Used),$before.Pct,(Opt-Size $before.Free))
 Write-Host "`nO Windows usa RAM livre como cache. Esta funcao apenas reduz working sets de processos de usuario;"
 Write-Host "nao encerra processos e nao limpa listas internas do kernel." -ForegroundColor DarkGray
 if((Read-Host "`nExecutar agora? [S/N]")-notmatch'^[Ss]$'){return}

 if(-not ("NativeMemory" -as [type])){
 Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeMemory {
 [DllImport("psapi.dll", SetLastError=true)]
 public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@
 }
 $skip=@("Idle","System","Registry","Memory Compression","Secure System")
 $ok=0
 foreach($p in Get-Process){
  if($skip -contains $p.ProcessName){continue}
  try{
   if($p.SessionId -eq (Get-Process -Id $PID).SessionId -and $p.Id -ne $PID){
    if([NativeMemory]::EmptyWorkingSet($p.Handle)){$ok++}
   }
  }catch{}
 }
 Start-Sleep 2
 $after=Opt-GetMemoryInfo
 [int64]$gain=$after.Free-$before.Free
 Write-Host "`nDepois: $(Opt-Size $after.Used) usados ($($after.Pct)%) | $(Opt-Size $after.Free) disponiveis" -ForegroundColor Green
 if($gain-gt 0){Write-Host "Memoria disponibilizada imediatamente: $(Opt-Size $gain)" -ForegroundColor Green}
 else{Write-Host "Nao houve aumento mensuravel de memoria disponivel." -ForegroundColor Yellow}
 Write-Host "Processos ajustados: $ok"
 Write-Host "`nObservacao: parte dessa memoria pode voltar a ser usada conforme os programas trabalham." -ForegroundColor DarkGray
 Opt-Log "Redutor RAM: antes=$($before.Pct)% depois=$($after.Pct)% processos=$ok"
 Opt-Pause
}
function Opt-MemoryMenu{
 do{
  Clear-Host;$m=Opt-GetMemoryInfo
  Write-Host "============================================" -ForegroundColor Cyan
  Write-Host " UNILAB - GERENCIADOR DE MEMORIA v0.3.1" -ForegroundColor Cyan
  Write-Host "============================================" -ForegroundColor Cyan
  Write-Host ("RAM instalada........... {0}" -f (Opt-Size $m.Total))
  Write-Host ("RAM em uso.............. {0} ({1}%)" -f (Opt-Size $m.Used),$m.Pct)
  Write-Host ("RAM disponivel.......... {0}" -f (Opt-Size $m.Free))
  Write-Host "`n[1] Ver maiores consumidores de RAM"
  Write-Host "[2] Liberar memoria agora"
  Write-Host "[0] Voltar"
  $mo=Read-Host "`nOpcao"
  switch($mo){"1"{Opt-TopMemory}"2"{Opt-ReduceMemory}}
 }while($mo-ne"0")
}

Function Menu-Otimizacao {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host "        OTIMIZACAO E MANUTENCAO UNIWARE          " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor DarkCyan
        Write-Host " 01 - Analisar espaco para limpeza"
        Write-Host " 02 - Limpar TEMP / Windows Temp / Prefetch / Lixeira"
        Write-Host " 03 - Plano de energia - Alto Desempenho"
        Write-Host " 04 - Otimizar PC fraco"
        Write-Host " 05 - Restaurar configuracoes anteriores"
        Write-Host " 06 - Gerenciador de memoria RAM"
        Write-Host " 07 - Ver log detalhado desta sessao"
        Write-Host " 00 - Voltar ao Menu Principal"
        Write-Host "=================================================" -ForegroundColor DarkCyan
        $op=Read-Host "Selecione uma opcao"
        Write-MaintenanceLog "MENU-MANUTENCAO" "INFO" "Opcao selecionada: $op"
        switch -Regex ($op) {
            "^0?1$" { $null=Opt-Analyze; Opt-Pause }
            "^0?2$" { Opt-Clean; Get-MaintenanceSnapshot "DEPOIS-LIMPEZA" }
            "^0?3$" { Opt-High; Get-MaintenanceSnapshot "DEPOIS-ENERGIA" }
            "^0?4$" { Opt-Weak; Get-MaintenanceSnapshot "DEPOIS-PC-FRACO" }
            "^0?5$" { Opt-Restore; Get-MaintenanceSnapshot "DEPOIS-RESTAURACAO" }
             "^0?6$" { Opt-MemoryMenu }
            "^0?7$" { Show-MaintenanceLog }
            "^0?0$" { return }
            default { Write-Host "Opcao invalida!" -ForegroundColor Red; Start-Sleep 1 }
        }
    }
}


# ---------------------------------------------------------------------
# INTERFACE VISUAL - UTILITARIO UNIWARE
# ---------------------------------------------------------------------
$Global:UIWidth = 79

Function UI-Border {
    Write-Host ("+" + ("-" * $Global:UIWidth) + "+") -ForegroundColor Blue
}
Function UI-Line {
    param([string]$Text = "",[ConsoleColor]$Color = [ConsoleColor]::White)
    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -gt $Global:UIWidth) { $Text = $Text.Substring(0,$Global:UIWidth) }
    Write-Host "|" -NoNewline -ForegroundColor Blue
    Write-Host $Text.PadRight($Global:UIWidth) -NoNewline -ForegroundColor $Color
    Write-Host "|" -ForegroundColor Blue
}
Function UI-Center {
    param([string]$Text,[ConsoleColor]$Color = [ConsoleColor]::Cyan)
    if ($Text.Length -gt $Global:UIWidth) { $Text=$Text.Substring(0,$Global:UIWidth) }
    $l=[math]::Floor(($Global:UIWidth-$Text.Length)/2)
    $r=$Global:UIWidth-$Text.Length-$l
    Write-Host "|" -NoNewline -ForegroundColor Blue
    Write-Host ((" "*$l)+$Text+(" "*$r)) -NoNewline -ForegroundColor $Color
    Write-Host "|" -ForegroundColor Blue
}
Function UI-MenuItem {
    param([string]$Number,[string]$Text)
    UI-Line ("  ["+$Number+"]  "+$Text) White
}
Function Show-UniwareHeader {
    Clear-Host
    try { $Host.UI.RawUI.WindowTitle="UTILITARIO UNIWARE" } catch {}
    UI-Border
    UI-Line
    UI-Center "UTILITARIO UNIWARE" Cyan
    UI-Center "Uniware Consultoria em Informatica" White
    UI-Line
    UI-Border
}
Function Show-MainMenu {
    Show-UniwareHeader
    UI-Line
    UI-MenuItem "01" "Impressoras Graficas"
    UI-MenuItem "02" "Impressoras de Cupom / Termicas"
    UI-MenuItem "03" "Impressoras Locais (USB / COM)"
    UI-MenuItem "04" "Instalar / Atualizar Winget"
    UI-MenuItem "05" "Etiquetadoras"
    UI-MenuItem "06" "Drivers - Impressoras de Cupom"
    UI-MenuItem "07" "Drivers - Impressoras Graficas"
    UI-MenuItem "08" "Usuario Unilabimp / Spooler"
    UI-MenuItem "09" "Otimizacao e Manutencao"
    UI-MenuItem "10" "Remover somente uma Impressora"
    UI-MenuItem "11" "Remover somente Driver do Fabricante"
    UI-MenuItem "12" "Baixar e executar Unilab RustDesk"
    UI-MenuItem "13" "Desativar UAC do Windows"
    UI-MenuItem "14" "Firewall e Portas"
    UI-MenuItem "15" "Unilab Nuvem"
    UI-MenuItem "16" "Painel de Senhas"
    UI-MenuItem "17" "Remover Usuarios Locais"
    UI-MenuItem "18" "Configurar e Calibrar Etiquetadora TSPL"
    UI-MenuItem "19" "Rede: DNS, diagnostico e IP fixo seguro"
    UI-Line
    UI-MenuItem "00" "Sair"
    UI-Line
    UI-Border
    Write-Host ""
}

Function Start-ConsoleMenu {
    while ($true) {
        Show-MainMenu
        $Opcao = Read-Host " Selecione uma opcao"

        switch -Regex ($Opcao) {
            "^0?1$" { Scan-Rede-Graficas; Pause }
            "^0?2$" { Scan-Rede-Cupom; Pause }
            "^0?3$" { Scan-Locais; Pause }
            "^0?4$" { Install-Winget; Pause }
            "^0?5$" { Menu-Etiquetadoras }
            "^0?6$" { Menu-Cupons }
            "^0?7$" { Menu-Graficas }
            "^0?8$" { Menu-UsuarioECredencial }
            "^0?9$" { Menu-Otimizacao }
            "^10$" { Remove-InstalledPrinterOnly; Pause }
            "^11$" { Remove-InstalledManufacturerDriverOnly; Pause }
            "^12$" { Install-RunRustDeskHighPriority; Pause }
            "^13$" { Disable-WindowsUACMaximum; Pause }
            "^14$" { Menu-FirewallTools }
            "^15$" { Install-UnilabNuvem; Pause }
            "^16$" { Menu-PasswordPanel }
            "^17$" { Remove-LocalUsersInteractive; Pause }
            "^18$" { Menu-LabelCalibration }
            "^19$" { Menu-RedeUniware }
            "^0?0$" { Write-Host "Saindo..."; return }
            default { Write-Host "Opcao Invalida!" -ForegroundColor Red; Pause }
        }
    }
}

try {
    switch ($Action) {
        "ScanGraficas"    { Scan-Rede-Graficas; Pause }
        "ScanCupom"       { Scan-Rede-Cupom; Pause }
        "ScanLocais"      { Scan-Locais; Pause }
        "Winget"          { Install-Winget; Pause }
        "Etiquetadoras"   { Menu-Etiquetadoras }
        "CalibrarEtiqueta" { Menu-LabelCalibration }
        "DriversCupom"    { Menu-Cupons }
        "DriversGraficas" { Menu-Graficas }
        "UsuarioSpooler"  { Menu-UsuarioECredencial }
        "RemoveUsers"     { Remove-LocalUsersInteractive; Pause }
        "Otimizacao"      { Menu-Otimizacao }
        "RemoverImpressora" { Remove-InstalledPrinterOnly; Pause }
        "RemoverDriver"     { Remove-InstalledManufacturerDriverOnly; Pause }
        "RustDesk"           { Install-RunRustDeskHighPriority; Pause }
        "DisableUAC"         { Disable-WindowsUACMaximum; Pause }
        "Firewall"           { Menu-FirewallTools }
        "UnilabNuvem"        { Install-UnilabNuvem; Pause }
        "PainelSenhas"       { Menu-PasswordPanel }
        "Rede"              { Menu-RedeUniware }
        default            { Start-ConsoleMenu }
    }
} catch {
    $Global:ErroFatal = $_
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Red
    Write-Host " ERRO FATAL - O SCRIPT NAO CONSEGUIU CONTINUAR" -ForegroundColor White -BackgroundColor Red
    Write-Host "=================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Detalhes: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Pressione ENTER para fechar"
}

