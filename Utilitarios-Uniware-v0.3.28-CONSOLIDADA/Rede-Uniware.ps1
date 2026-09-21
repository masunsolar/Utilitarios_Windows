# =====================================================================
# REDE UNIWARE - DIAGNOSTICO, DNS E IP FIXO SEGURO
# Compatibilidade: Windows 10/11 - PowerShell 5.1+
# Uso: este arquivo e carregado pelo Utilitarios_Uniware.PS1
# =====================================================================

$script:UniwareNetworkStateDir = Join-Path $PSScriptRoot "ESTADO\REDE"
$script:UniwareNetworkLogDir   = Join-Path $PSScriptRoot "LOGS\REDE"
New-Item -ItemType Directory -Force -Path $script:UniwareNetworkStateDir -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Force -Path $script:UniwareNetworkLogDir -ErrorAction SilentlyContinue | Out-Null

function Write-NetworkLog {
    param(
        [string]$Action,
        [string]$Status = "INFO",
        [string]$Details = ""
    )
    $file = Join-Path $script:UniwareNetworkLogDir ("Rede_{0}_{1}.log" -f $env:COMPUTERNAME,(Get-Date -Format "yyyyMMdd_HHmmss"))
    $line = "[{0}] [{1}] [{2}] Usuario={3} PC={4} :: {5}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Status,$Action,$env:USERNAME,$env:COMPUTERNAME,$Details
    try { Add-Content -LiteralPath $file -Value $line -Encoding UTF8 } catch {}
}

function Test-NetworkAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Pause-Network {
    Read-Host "Pressione ENTER para continuar" | Out-Null
}

function Format-NetworkArray {
    param([object[]]$Items)
    if ($null -eq $Items -or @($Items).Count -eq 0) { return "-" }
    return (@($Items) -join ", ")
}

function Get-UniwareActiveAdapters {
    @(
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Status -eq "Up" -and
                $_.HardwareInterface -eq $true -and
                $_.InterfaceDescription -notmatch "Bluetooth|Virtual|VMware|VirtualBox|Hyper-V|Loopback|TAP|TUN|WireGuard"
            } |
            Sort-Object ifIndex
    )
}

function Get-UniwareNetworkSnapshot {
    param([object]$Adapter)

    $index = [int]$Adapter.ifIndex
    $ipInterface = Get-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $addresses = @(
        Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" } |
            ForEach-Object {
                [pscustomobject]@{
                    IPAddress    = [string]$_.IPAddress
                    PrefixLength = [int]$_.PrefixLength
                    Type         = [string]$_.PrefixOrigin
                }
            }
    )

    $routes = @(
        Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            ForEach-Object {
                [pscustomobject]@{
                    NextHop     = [string]$_.NextHop
                    RouteMetric = [int]$_.RouteMetric
                }
            }
    )

    $dns = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
    $dns6 = @(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)

    [pscustomobject]@{
        Version             = 1
        Timestamp           = (Get-Date).ToString("o")
        ComputerName        = $env:COMPUTERNAME
        InterfaceAlias      = [string]$Adapter.Name
        InterfaceIndex      = $index
        InterfaceDescription= [string]$Adapter.InterfaceDescription
        DhcpIPv4            = if ($ipInterface) { [string]$ipInterface.Dhcp } else { "Unknown" }
        IPv4Addresses       = $addresses
        DefaultRoutes       = $routes
        DnsIPv4             = @($dns)
        DnsIPv6             = @($dns6)
    }
}

function Save-UniwareNetworkSnapshot {
    param([object]$Adapter)
    $snapshot = Get-UniwareNetworkSnapshot -Adapter $Adapter
    $safeAlias = ($snapshot.InterfaceAlias -replace '[^a-zA-Z0-9_-]','_')
    $file = Join-Path $script:UniwareNetworkStateDir ("Backup_{0}_{1}.json" -f $safeAlias,(Get-Date -Format "yyyyMMdd_HHmmss"))
    $latest = Join-Path $script:UniwareNetworkStateDir ("UltimoBackup_{0}.json" -f $safeAlias)
    $json = $snapshot | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $file -Value $json -Encoding UTF8
    Set-Content -LiteralPath $latest -Value $json -Encoding UTF8
    Write-NetworkLog "BACKUP" "SUCESSO" ("Interface={0}; Arquivo={1}; DHCP={2}; IPv4={3}; Gateway={4}; DNS={5}" -f $snapshot.InterfaceAlias,$file,$snapshot.DhcpIPv4,(Format-NetworkArray $snapshot.IPv4Addresses.IPAddress),(Format-NetworkArray $snapshot.DefaultRoutes.NextHop),(Format-NetworkArray $snapshot.DnsIPv4))
    return $file
}

function Get-UniwareLatestNetworkSnapshot {
    param([string]$InterfaceAlias)
    $safeAlias = ($InterfaceAlias -replace '[^a-zA-Z0-9_-]','_')
    $file = Join-Path $script:UniwareNetworkStateDir ("UltimoBackup_{0}.json" -f $safeAlias)
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Test-UniwareIPv4 {
    param([string]$Address)
    $parsed = $null
    return [System.Net.IPAddress]::TryParse($Address,[ref]$parsed) -and $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
}

function Test-UniwarePrefixLength {
    param([string]$Prefix)
    $value = 0
    return [int]::TryParse($Prefix,[ref]$value) -and $value -ge 1 -and $value -le 32
}

function Test-UniwareLikelyIpConflict {
    param([string]$IPAddress)
    try {
        $reply = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
        return [bool]$reply
    } catch { return $false }
}

function Test-UniwareDnsServer {
    param(
        [string]$Server,
        [string[]]$Names = @("www.microsoft.com","www.google.com","www.cloudflare.com"),
        [int]$Attempts = 3
    )
    $samples = New-Object System.Collections.Generic.List[double]
    $failures = 0
    foreach ($name in $Names) {
        for ($i=1; $i -le $Attempts; $i++) {
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $null = Resolve-DnsName -Name $name -Server $Server -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
                $sw.Stop()
                [void]$samples.Add([double]$sw.Elapsed.TotalMilliseconds)
            } catch {
                $failures++
            }
        }
    }
    if ($samples.Count -eq 0) {
        return [pscustomobject]@{ Server=$Server; AverageMs=$null; MinMs=$null; MaxMs=$null; Samples=0; Failures=$failures; Success=$false }
    }
    return [pscustomobject]@{
        Server=$Server
        AverageMs=[math]::Round((($samples | Measure-Object -Average).Average),1)
        MinMs=[math]::Round((($samples | Measure-Object -Minimum).Minimum),1)
        MaxMs=[math]::Round((($samples | Measure-Object -Maximum).Maximum),1)
        Samples=$samples.Count
        Failures=$failures
        Success=$true
    }
}

function Get-UniwareDnsCandidates {
    @(
        [pscustomobject]@{ Name="Cloudflare"; Primary="1.1.1.1"; Secondary="1.0.0.1" },
        [pscustomobject]@{ Name="Google"; Primary="8.8.8.8"; Secondary="8.8.4.4" },
        [pscustomobject]@{ Name="Quad9"; Primary="9.9.9.9"; Secondary="149.112.112.112" },
        [pscustomobject]@{ Name="AdGuard"; Primary="94.140.14.14"; Secondary="94.140.15.15" }
    )
}

function Test-UniwareInternetConnectivity {
    param(
        [int]$InterfaceIndex,
        [string]$Gateway,
        [string]$DnsServer,
        [switch]$Quiet
    )

    $gatewayOk = $true
    if ($Gateway) {
        try { $gatewayOk = [bool](Test-Connection -ComputerName $Gateway -Count 1 -Quiet -ErrorAction SilentlyContinue) } catch { $gatewayOk = $false }
    }

    $ip443Ok = $false
    try {
        $r = Test-NetConnection -ComputerName "1.1.1.1" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $ip443Ok = [bool]$r
    } catch { $ip443Ok = $false }

    $dnsOk = $false
    if ($DnsServer) {
        try {
            $null = Resolve-DnsName -Name "www.microsoft.com" -Server $DnsServer -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
            $dnsOk = $true
        } catch { $dnsOk = $false }
    } else {
        try {
            $null = Resolve-DnsName -Name "www.microsoft.com" -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
            $dnsOk = $true
        } catch { $dnsOk = $false }
    }

    $httpsOk = $false
    foreach ($url in @("https://www.msftconnecttest.com/connecttest.txt","https://www.microsoft.com/")) {
        try {
            $null = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            $httpsOk = $true
            break
        } catch {}
    }

    $score = 0
    if ($gatewayOk) { $score++ }
    if ($ip443Ok)   { $score++ }
    if ($dnsOk)     { $score++ }
    if ($httpsOk)   { $score++ }

    # Gateway + IP externo sao os testes mais importantes para decidir rollback.
    $success = (($gatewayOk -or -not $Gateway) -and $ip443Ok -and $httpsOk)

    $result = [pscustomobject]@{
        Success=$success
        Gateway=$Gateway
        GatewayOk=$gatewayOk
        InternetIP443Ok=$ip443Ok
        DnsOk=$dnsOk
        HttpsOk=$httpsOk
        Score=$score
    }

    if (-not $Quiet) {
        Write-Host ("    Gateway : {0}" -f ($(if($gatewayOk){"OK"}else{"FALHA"}))) -ForegroundColor $(if($gatewayOk){"Green"}else{"Red"})
        Write-Host ("    Internet : {0}" -f ($(if($ip443Ok){"OK"}else{"FALHA"}))) -ForegroundColor $(if($ip443Ok){"Green"}else{"Red"})
        Write-Host ("    DNS : {0}" -f ($(if($dnsOk){"OK"}else{"FALHA"}))) -ForegroundColor $(if($dnsOk){"Green"}else{"Red"})
        Write-Host ("    HTTPS : {0}" -f ($(if($httpsOk){"OK"}else{"FALHA"}))) -ForegroundColor $(if($httpsOk){"Green"}else{"Red"})
    }
    return $result
}

function Restore-UniwareNetworkSnapshot {
    param(
        [Parameter(Mandatory=$true)]$Snapshot
    )

    $adapter = Get-NetAdapter -Name $Snapshot.InterfaceAlias -ErrorAction SilentlyContinue
    if (-not $adapter) {
        $adapter = Get-NetAdapter -InterfaceIndex ([int]$Snapshot.InterfaceIndex) -ErrorAction SilentlyContinue
    }
    if (-not $adapter) { throw "A interface '$($Snapshot.InterfaceAlias)' nao foi encontrada para restauracao." }

    $index = [int]$adapter.ifIndex
    Write-Host "`n[ROLLBACK] Restaurando configuracao anterior..." -ForegroundColor Yellow

    Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" } |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    $isDhcp = ([string]$Snapshot.DhcpIPv4 -eq "Enabled")
    if ($isDhcp) {
        Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
    } else {
        $addresses = @($Snapshot.IPv4Addresses)
        $routes = @($Snapshot.DefaultRoutes)
        if ($addresses.Count -eq 0) { throw "Backup sem endereco IPv4 para restaurar." }

        $first = $true
        foreach ($address in $addresses) {
            $gateway = $null
            if ($first -and $routes.Count -gt 0) { $gateway = [string]$routes[0].NextHop }
            if ($gateway) {
                New-NetIPAddress -InterfaceIndex $index -IPAddress ([string]$address.IPAddress) -PrefixLength ([int]$address.PrefixLength) -DefaultGateway $gateway -ErrorAction Stop | Out-Null
            } else {
                New-NetIPAddress -InterfaceIndex $index -IPAddress ([string]$address.IPAddress) -PrefixLength ([int]$address.PrefixLength) -ErrorAction Stop | Out-Null
            }
            $first = $false
        }
    }

    if (@($Snapshot.DnsIPv4).Count -gt 0) {
        Set-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ServerAddresses @($Snapshot.DnsIPv4) -ErrorAction SilentlyContinue
    } else {
        Set-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ResetServerAddresses -ErrorAction SilentlyContinue
    }

    if (@($Snapshot.DnsIPv6).Count -gt 0) {
        Set-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv6 -ServerAddresses @($Snapshot.DnsIPv6) -ErrorAction SilentlyContinue
    } else {
        Set-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv6 -ResetServerAddresses -ErrorAction SilentlyContinue
    }

    ipconfig /flushdns | Out-Null
    Start-Sleep -Seconds 2
    Write-NetworkLog "ROLLBACK" "SUCESSO" ("Interface={0}; DHCP={1}; IPv4={2}; Gateway={3}; DNS={4}" -f $adapter.Name,$Snapshot.DhcpIPv4,(Format-NetworkArray $Snapshot.IPv4Addresses.IPAddress),(Format-NetworkArray $Snapshot.DefaultRoutes.NextHop),(Format-NetworkArray $Snapshot.DnsIPv4))
    Write-Host "[OK] Configuracao anterior restaurada." -ForegroundColor Green
}

function Invoke-UniwareNetworkChangeWithRollback {
    param(
        [Parameter(Mandatory=$true)]$Adapter,
        [Parameter(Mandatory=$true)][string]$IPAddress,
        [Parameter(Mandatory=$true)][int]$PrefixLength,
        [Parameter(Mandatory=$true)][string]$Gateway,
        [Parameter(Mandatory=$true)][string[]]$DnsServers,
        [int]$ValidationSeconds = 30
    )

    $backupFile = Save-UniwareNetworkSnapshot -Adapter $Adapter
    $snapshot = Get-Content -LiteralPath $backupFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $index = [int]$Adapter.ifIndex

    try {
        Write-Host "`n[1/5] Aplicando IPv4 fixo..." -ForegroundColor Yellow
        Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop

        Get-NetRoute -InterfaceIndex $index -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" } |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceIndex $index -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction Stop | Out-Null

        Write-Host "[2/5] Aplicando DNS..." -ForegroundColor Yellow
        Set-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4 -ServerAddresses $DnsServers -ErrorAction Stop
        ipconfig /flushdns | Out-Null

        Write-Host "[3/5] Aguardando a interface estabilizar..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2

        Write-Host "[4/5] Validando conexao por ate $ValidationSeconds segundos..." -ForegroundColor Yellow
        $deadline = (Get-Date).AddSeconds($ValidationSeconds)
        $validated = $false
        $lastResult = $null
        while ((Get-Date) -lt $deadline) {
            $lastResult = Test-UniwareInternetConnectivity -InterfaceIndex $index -Gateway $Gateway -DnsServer $DnsServers[0] -Quiet
            if ($lastResult.Success) {
                $validated = $true
                break
            }
            Start-Sleep -Seconds 2
        }

        if (-not $validated) {
            Write-Host "[FALHA] A internet nao foi validada dentro da janela de seguranca." -ForegroundColor Red
            Write-Host "[5/5] Iniciando rollback automatico..." -ForegroundColor Yellow
            Write-NetworkLog "IP-FIXO" "ROLLBACK" ("Falha de validacao apos $ValidationSeconds s; IP=$IPAddress; Gateway=$Gateway; DNS=$($DnsServers -join ','); Score=$($lastResult.Score)")
            Restore-UniwareNetworkSnapshot -Snapshot $snapshot
            $post = Test-UniwareInternetConnectivity -InterfaceIndex $index -Gateway (($snapshot.DefaultRoutes | Select-Object -First 1).NextHop) -DnsServer (($snapshot.DnsIPv4 | Select-Object -First 1)) -Quiet
            if ($post.Success) {
                Write-Host "[OK] Internet voltou apos o rollback." -ForegroundColor Green
                Write-NetworkLog "IP-FIXO" "SUCESSO-ROLLBACK" "Conectividade restaurada apos rollback."
            } else {
                Write-Host "[ATENCAO] A configuracao foi restaurada, mas a conectividade ainda nao foi validada." -ForegroundColor Yellow
                Write-NetworkLog "IP-FIXO" "ATENCAO" "Rollback aplicado, mas teste posterior ainda falhou."
            }
            return $false
        }

        Write-Host "[5/5] Nova configuracao validada. Alteracao mantida." -ForegroundColor Green
        Write-NetworkLog "IP-FIXO" "COMMIT" ("IP=$IPAddress/$PrefixLength; Gateway=$Gateway; DNS=$($DnsServers -join ','); Validacao=OK")
        return $true
    } catch {
        Write-Host "[ERRO] Falha durante a alteracao: $($_.Exception.Message)" -ForegroundColor Red
        Write-NetworkLog "IP-FIXO" "ERRO" $_.Exception.Message
        try { Restore-UniwareNetworkSnapshot -Snapshot $snapshot } catch { Write-Host "[ERRO CRITICO] Falha no rollback: $($_.Exception.Message)" -ForegroundColor Red }
        return $false
    }
}

function Show-UniwareNetworkStatus {
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "              DIAGNOSTICO DE REDE               " -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "=================================================" -ForegroundColor Cyan
    $adapters = @(Get-UniwareActiveAdapters)
    if ($adapters.Count -eq 0) {
        Write-Host "Nenhuma interface fisica ativa foi encontrada." -ForegroundColor Red
        return
    }
    foreach ($adapter in $adapters) {
        $config = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
        $dns = @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses)
        Write-Host "`nInterface : $($adapter.Name)" -ForegroundColor White
        Write-Host "Descricao : $($adapter.InterfaceDescription)" -ForegroundColor Gray
        Write-Host "IPv4      : $((@($config.IPv4Address | ForEach-Object IPAddress) -join ', '))" -ForegroundColor Gray
        Write-Host "Gateway   : $((@($config.IPv4DefaultGateway | ForEach-Object NextHop) -join ', '))" -ForegroundColor Gray
        Write-Host "DNS IPv4  : $((@($dns) -join ', '))" -ForegroundColor Gray
        Write-Host "DHCP IPv4 : $((Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp)" -ForegroundColor Gray
    }
}

function Invoke-UniwareDnsBenchmark {
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "              TESTE DE DNS / LATENCIA            " -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "Medindo consultas reais contra os servidores DNS." -ForegroundColor Gray
    Write-Host "O resultado depende da rede atual; nao existe um DNS universalmente mais rapido.`n" -ForegroundColor Gray

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in Get-UniwareDnsCandidates) {
        Write-Host "Testando $($candidate.Name) ($($candidate.Primary))..." -ForegroundColor Yellow
        $result = Test-UniwareDnsServer -Server $candidate.Primary
        $result | Add-Member -NotePropertyName Name -NotePropertyValue $candidate.Name
        $result | Add-Member -NotePropertyName Secondary -NotePropertyValue $candidate.Secondary
        [void]$results.Add($result)
    }

    Write-Host "`nRESULTADO:" -ForegroundColor Cyan
    $results | Sort-Object @{Expression={if($_.Success){0}else{1}}}, AverageMs |
        Format-Table Name,Server,AverageMs,MinMs,MaxMs,Samples,Failures,Success -AutoSize

    $best = $results | Where-Object Success | Sort-Object AverageMs | Select-Object -First 1
    if ($best) {
        Write-Host "Menor media medida: $($best.Name) - $($best.Server) - $($best.AverageMs) ms" -ForegroundColor Green
        Write-NetworkLog "DNS-BENCHMARK" "SUCESSO" ("Melhor=$($best.Name); Server=$($best.Server); Media=$($best.AverageMs)ms")
    } else {
        Write-Host "Nenhum DNS respondeu de forma valida." -ForegroundColor Red
        Write-NetworkLog "DNS-BENCHMARK" "ERRO" "Nenhum servidor respondeu."
    }
}

function Set-UniwareDnsFast {
    $adapters = @(Get-UniwareActiveAdapters)
    if ($adapters.Count -eq 0) { Write-Host "Nenhum adaptador ativo encontrado." -ForegroundColor Red; return }

    Invoke-UniwareDnsBenchmark
    $results = @()
    foreach ($candidate in Get-UniwareDnsCandidates) {
        $result = Test-UniwareDnsServer -Server $candidate.Primary
        $result | Add-Member -NotePropertyName Name -NotePropertyValue $candidate.Name
        $result | Add-Member -NotePropertyName Secondary -NotePropertyValue $candidate.Secondary
        $results += $result
    }
    $best = $results | Where-Object Success | Sort-Object AverageMs | Select-Object -First 1
    if (-not $best) {
        Write-Host "Nao foi possivel escolher um DNS confiavel." -ForegroundColor Red
        return
    }

    Write-Host "`nDNS escolhido automaticamente: $($best.Name) ($($best.Server)) - media $($best.AverageMs) ms" -ForegroundColor Green
    $confirm = Read-Host "Aplicar esse DNS nas interfaces fisicas ativas? (S/N)"
    if ($confirm -notmatch '^[Ss]$') { return }

    foreach ($adapter in $adapters) {
        $backup = Save-UniwareNetworkSnapshot -Adapter $adapter
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ServerAddresses @($best.Server,$best.Secondary) -ErrorAction Stop
            ipconfig /flushdns | Out-Null
            $test = Test-UniwareInternetConnectivity -InterfaceIndex $adapter.ifIndex -Gateway ((Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue).IPv4DefaultGateway | Select-Object -First 1 -ExpandProperty NextHop) -DnsServer $best.Server -Quiet
            if (-not $test.Success) {
                $snapshot = Get-Content -LiteralPath $backup -Raw -Encoding UTF8 | ConvertFrom-Json
                Restore-UniwareNetworkSnapshot -Snapshot $snapshot
                Write-Host "[ATENCAO] DNS nao validado; configuracao anterior restaurada em $($adapter.Name)." -ForegroundColor Yellow
                Write-NetworkLog "DNS-APLICAR" "ROLLBACK" "Interface=$($adapter.Name); DNS=$($best.Server)"
            } else {
                Write-Host "[OK] $($adapter.Name): $($best.Server), $($best.Secondary)" -ForegroundColor Green
                Write-NetworkLog "DNS-APLICAR" "COMMIT" "Interface=$($adapter.Name); DNS=$($best.Server),$($best.Secondary); Backup=$backup"
            }
        } catch {
            Write-Host "[ERRO] $($adapter.Name): $($_.Exception.Message)" -ForegroundColor Red
            try {
                $snapshot = Get-Content -LiteralPath $backup -Raw -Encoding UTF8 | ConvertFrom-Json
                Restore-UniwareNetworkSnapshot -Snapshot $snapshot
            } catch {}
            Write-NetworkLog "DNS-APLICAR" "ERRO" $_.Exception.Message
        }
    }
}
function Restore-UniwareLatestNetwork {
    $adapters = @(Get-UniwareActiveAdapters)
    if ($adapters.Count -eq 0) { Write-Host "Nenhum adaptador ativo encontrado." -ForegroundColor Red; return }
    foreach ($adapter in $adapters) {
        $snapshot = Get-UniwareLatestNetworkSnapshot -InterfaceAlias $adapter.Name
        if (-not $snapshot) {
            Write-Host "[AVISO] Sem backup para $($adapter.Name)." -ForegroundColor Yellow
            continue
        }
        try { Restore-UniwareNetworkSnapshot -Snapshot $snapshot } catch { Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red }
    }
}

function Set-UniwareStaticIPv4Wizard {
    if (-not (Test-NetworkAdministrator)) {
        Write-Host "Esta operacao precisa ser executada como Administrador." -ForegroundColor Red
        return
    }

    $adapters = @(Get-UniwareActiveAdapters)
    if ($adapters.Count -eq 0) { Write-Host "Nenhuma interface fisica ativa encontrada." -ForegroundColor Red; return }

    Write-Host "`nINTERFACES ATIVAS:" -ForegroundColor Cyan
    for ($i=0; $i -lt $adapters.Count; $i++) {
        Write-Host (" [{0}] {1} - {2}" -f ($i+1),$adapters[$i].Name,$adapters[$i].InterfaceDescription)
    }
    $selected = Read-Host "Escolha a interface"
    $number = 0
    if (-not [int]::TryParse($selected,[ref]$number) -or $number -lt 1 -or $number -gt $adapters.Count) {
        Write-Host "Interface invalida." -ForegroundColor Red
        return
    }
    $adapter = $adapters[$number-1]
    $current = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
    $currentIp = @($current.IPv4Address | ForEach-Object IPAddress) -join ", "
    $currentGateway = @($current.IPv4DefaultGateway | ForEach-Object NextHop) -join ", "
    Write-Host "`nConfiguracao atual: IP=$currentIp | Gateway=$currentGateway" -ForegroundColor Gray

    $ip = Read-Host "Novo IPv4 (ex.: 192.168.1.50)"
    if (-not (Test-UniwareIPv4 $ip)) { Write-Host "IPv4 invalido." -ForegroundColor Red; return }
    $prefixText = Read-Host "Prefixo CIDR (ex.: 24)"
    if (-not (Test-UniwarePrefixLength $prefixText)) { Write-Host "Prefixo invalido. Use 1 a 32." -ForegroundColor Red; return }
    $prefix = [int]$prefixText
    $gateway = Read-Host "Gateway (ex.: 192.168.1.1)"
    if (-not (Test-UniwareIPv4 $gateway)) { Write-Host "Gateway IPv4 invalido." -ForegroundColor Red; return }

    $candidateDns = Get-UniwareDnsCandidates
    Write-Host "`nDNS:" -ForegroundColor Cyan
    for ($i=0; $i -lt $candidateDns.Count; $i++) { Write-Host (" [{0}] {1} - {2}" -f ($i+1),$candidateDns[$i].Name,$candidateDns[$i].Primary) }
    $dnsChoice = Read-Host "Escolha o DNS (1-4) ou digite um servidor IPv4"
    $dns = $null
    $dnsCandidate = $candidateDns | Where-Object { $_.Primary -eq $dnsChoice } | Select-Object -First 1
    if ($dnsCandidate) { $dns = @($dnsCandidate.Primary,$dnsCandidate.Secondary) }
    elseif (Test-UniwareIPv4 $dnsChoice) { $dns = @($dnsChoice) }
    else { Write-Host "DNS invalido." -ForegroundColor Red; return }

    Write-Host "`nRESUMO DA ALTERACAO" -ForegroundColor Cyan
    Write-Host "Interface : $($adapter.Name)"
    Write-Host "IPv4      : $ip/$prefix"
    Write-Host "Gateway   : $gateway"
    Write-Host "DNS       : $($dns -join ', ')"
    Write-Host "Rollback  : automatico se a internet nao for validada em ate 30 segundos" -ForegroundColor Yellow

    if (Test-UniwareLikelyIpConflict -IPAddress $ip) {
        Write-Host "`n[ATENCAO] O novo IP respondeu a um ping. Pode haver outro equipamento usando esse endereco." -ForegroundColor Red
        $continue = Read-Host "Continuar mesmo assim? (S/N)"
        if ($continue -notmatch '^[Ss]$') { return }
    }

    $confirm = Read-Host "Aplicar configuracao? (S/N)"
    if ($confirm -notmatch '^[Ss]$') { return }

    $ok = Invoke-UniwareNetworkChangeWithRollback -Adapter $adapter -IPAddress $ip -PrefixLength $prefix -Gateway $gateway -DnsServers $dns -ValidationSeconds 30
    if ($ok) {
        Write-Host "`nConfiguracao mantida com sucesso." -ForegroundColor Green
    } else {
        Write-Host "`nA alteracao nao foi mantida. O backup anterior foi usado para rollback." -ForegroundColor Yellow
    }
}

function Menu-RedeUniware {
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "                 REDE UNIWARE                   " -ForegroundColor White -BackgroundColor DarkCyan
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host " 01 - Diagnostico de rede"
        Write-Host " 02 - Testar DNS e medir latencia"
        Write-Host " 03 - Aplicar automaticamente o DNS com menor latencia medida"
        Write-Host " 04 - Configurar IP fixo com rollback automatico"
        Write-Host " 05 - Restaurar ultima configuracao salva"
        Write-Host " 06 - Restaurar DHCP + DNS automatico"
        Write-Host " 00 - Voltar"
        Write-Host "=================================================" -ForegroundColor Cyan
        $op = Read-Host "Selecione uma opcao"
        switch -Regex ($op) {
            '^0?1$' { Show-UniwareNetworkStatus; Pause-Network }
            '^0?2$' { Invoke-UniwareDnsBenchmark; Pause-Network }
            '^0?3$' { Set-UniwareDnsFast; Pause-Network }
            '^0?4$' { Set-UniwareStaticIPv4Wizard; Pause-Network }
            '^0?5$' { Restore-UniwareLatestNetwork; Pause-Network }
            '^0?6$' {
                $adapters = @(Get-UniwareActiveAdapters)
                foreach ($adapter in $adapters) {
                    try {
                        # Remove rotas/endereco estatico antes de voltar ao DHCP.
                        Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
                        Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                            Where-Object { $_.IPAddress -notlike "127.*" } |
                            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                        Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Dhcp Enabled -ErrorAction Stop
                        Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ResetServerAddresses -ErrorAction SilentlyContinue
                        ipconfig /flushdns | Out-Null
                        Write-Host "[OK] $($adapter.Name): DHCP + DNS automatico." -ForegroundColor Green
                        Write-NetworkLog "RESTAURAR-DHCP" "SUCESSO" "Interface=$($adapter.Name)"
                    } catch { Write-Host "[ERRO] $($_.Exception.Message)" -ForegroundColor Red }
                }
                Pause-Network
            }
            '^0?0$' { return }
            default { Write-Host "Opcao invalida." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}
