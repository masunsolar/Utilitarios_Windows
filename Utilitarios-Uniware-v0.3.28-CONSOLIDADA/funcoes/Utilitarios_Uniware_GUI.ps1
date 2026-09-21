param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$CoreScript = Join-Path $PSScriptRoot "Utilitarios_Uniware.PS1"
$script:Accent = [System.Drawing.Color]::FromArgb(37,99,235)
$script:Sidebar = [System.Drawing.Color]::FromArgb(20,33,61)
$script:SidebarMuted = [System.Drawing.Color]::FromArgb(157,171,195)
$script:Background = [System.Drawing.Color]::FromArgb(239,243,248)
$script:Surface = [System.Drawing.Color]::White
$script:Text = [System.Drawing.Color]::FromArgb(24,34,52)
$script:Muted = [System.Drawing.Color]::FromArgb(99,113,137)
$script:Line = [System.Drawing.Color]::FromArgb(222,229,238)
$script:NavButtons = @()

function New-UiFont {
    param([float]$Size = 9, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    New-Object System.Drawing.Font("Segoe UI", $Size, $Style)
}

function Start-ToolAction {
    param([string]$Action)
    if (-not (Test-Path -LiteralPath $CoreScript)) {
        [System.Windows.Forms.MessageBox]::Show("O arquivo Utilitarios_Uniware.PS1 nao foi encontrado.","Arquivo ausente","OK","Error") | Out-Null
        return
    }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$CoreScript`" -Action $Action"
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WorkingDirectory $PSScriptRoot
}

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height = 24,
        [float]$Size = 9,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
        [System.Drawing.Color]$Color = $script:Text
    )
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X,$Y)
    $label.Size = New-Object System.Drawing.Size($Width,$Height)
    $label.Font = New-UiFont -Size $Size -Style $Style
    $label.ForeColor = $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    return $label
}

function New-ActionButton {
    param(
        [string]$Title,
        [string]$Description,
        [string]$Action,
        [int]$X,
        [int]$Y,
        [int]$Width = 235,
        [int]$Height = 112,
        [switch]$Destructive
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "$Title`r`n$Description"
    $button.Tag = $Action
    $button.Location = New-Object System.Drawing.Point($X,$Y)
    $button.Size = New-Object System.Drawing.Size($Width,$Height)
    $button.Font = New-UiFont -Size 9
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $button.Padding = New-Object System.Windows.Forms.Padding(15,8,12,8)
    $button.AutoEllipsis = $false
    if ($Height -ge 55) {
        $measureFlags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl
        $measureWidth = [Math]::Max(40, $Width - $button.Padding.Horizontal - 8)
        $measured = [System.Windows.Forms.TextRenderer]::MeasureText(
            $button.Text,
            $button.Font,
            (New-Object System.Drawing.Size($measureWidth,1000)),
            $measureFlags
        )
        $requiredHeight = $measured.Height + $button.Padding.Vertical + 8
        if ($requiredHeight -gt $button.Height) { $button.Height = $requiredHeight }
    }
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderColor = $script:Line
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(234,242,255)
    $button.BackColor = $script:Surface
    $button.ForeColor = $script:Text
    if ($Destructive) {
        $button.ForeColor = [System.Drawing.Color]::FromArgb(166,40,40)
        $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226,178,178)
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(255,238,238)
    }
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_Click({ Start-ToolAction -Action ([string]$this.Tag) })
    return $button
}

function New-InfoPanel {
    param([string]$Title,[int]$X,[int]$Y,[int]$Width,[int]$Height)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X,$Y)
    $panel.Size = New-Object System.Drawing.Size($Width,$Height)
    $panel.BackColor = $script:Surface
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $panel.Controls.Add((New-Label -Text $Title -X 17 -Y 14 -Width ($Width-34) -Height 24 -Size 10 -Style Bold))
    return $panel
}

function Clear-Content {
    $Content.SuspendLayout()
    $Content.Controls.Clear()
}

function Finish-Content {
    $Content.ResumeLayout()
    $Content.Refresh()
}

function Get-ResponsiveLayout {
    $margin = 28
    $gap = 15
    $usableWidth = [Math]::Max(600, $Content.ClientSize.Width - ($margin * 2))
    $cardWidth = [Math]::Floor(($usableWidth - ($gap * 2)) / 3)
    [pscustomobject]@{
        Margin = $margin
        Gap = $gap
        UsableWidth = $usableWidth
        CardWidth = $cardWidth
        X1 = $margin
        X2 = $margin + $cardWidth + $gap
        X3 = $margin + (($cardWidth + $gap) * 2)
    }
}

function Set-ActiveNavigation {
    param([string]$Page)
    foreach ($button in $script:NavButtons) {
        if ([string]$button.Tag -eq $Page) {
            $button.BackColor = [System.Drawing.Color]::FromArgb(48,62,89)
            $button.ForeColor = [System.Drawing.Color]::White
        } else {
            $button.BackColor = $script:Sidebar
            $button.ForeColor = $script:SidebarMuted
        }
    }
}

function Show-HomePage {
    $script:CurrentPage = "Inicio"
    Set-ActiveNavigation "Inicio"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "Central tecnica" -X 28 -Y 22 -Width 420 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Acesso rapido as rotinas mais usadas pela equipe" -X 29 -Y 55 -Width 520 -Height 22 -Size 9 -Color $script:Muted))
    $Content.Controls.Add((New-Label -Text "O que voce deseja fazer?" -X 28 -Y 98 -Width 400 -Height 25 -Size 11 -Style Bold))
    $Content.Controls.Add((New-ActionButton -Title "BUSCAR NA REDE" -Description "Localizar impressoras graficas por IP" -Action "ScanGraficas" -X $layout.X1 -Y 132 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "BUSCAR CUPOM" -Description "Detectar termicas e instalar durante a busca" -Action "ScanCupom" -X $layout.X2 -Y 132 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "CONFIGURAR USB / COM" -Description "Detectar dispositivo e associar o driver" -Action "ScanLocais" -X $layout.X3 -Y 132 -Width $layout.CardWidth))

    $recentWidth = ($layout.CardWidth * 2) + $layout.Gap
    $recent = New-InfoPanel -Title "Atalhos de instalacao" -X $layout.X1 -Y 268 -Width $recentWidth -Height 230
    $innerGap = 14
    $innerWidth = [Math]::Floor(($recentWidth - 46) / 2)
    $innerX2 = 16 + $innerWidth + $innerGap
    $driverGraphicsButton = New-ActionButton -Title "Drivers de impressoras graficas" -Description "HP, Epson, Brother, Canon e outras" -Action "DriversGraficas" -X 16 -Y 51 -Width $innerWidth -Height 68
    $driverCouponButton = New-ActionButton -Title "Drivers de cupom" -Description "Epson, Elgin e Bematech" -Action "DriversCupom" -X $innerX2 -Y 51 -Width $innerWidth -Height 68
    $secondRowY = [Math]::Max($driverGraphicsButton.Bottom,$driverCouponButton.Bottom) + 14
    $labelButton = New-ActionButton -Title "Etiquetadoras" -Description "Zebra, Elgin, TOMATE, Xprinter e Argox" -Action "Etiquetadoras" -X 16 -Y $secondRowY -Width $innerWidth -Height 68
    $wingetButton = New-ActionButton -Title "Instalar / atualizar Winget" -Description "Gerenciador de pacotes do Windows" -Action "Winget" -X $innerX2 -Y $secondRowY -Width $innerWidth -Height 68
    foreach ($button in @($driverGraphicsButton,$driverCouponButton,$labelButton,$wingetButton)) { $recent.Controls.Add($button) }
    $recent.Height = [Math]::Max($labelButton.Bottom,$wingetButton.Bottom) + 16
    $Content.Controls.Add($recent)

    $machine = New-InfoPanel -Title "Este computador" -X $layout.X3 -Y 268 -Width $layout.CardWidth -Height $recent.Height
    $spoolerStatus = "Indisponivel"
    $spoolerColor = [System.Drawing.Color]::FromArgb(184,102,0)
    try {
        $service = Get-Service -Name Spooler -ErrorAction Stop
        $spoolerStatus = if ($service.Status -eq "Running") { "Ativo" } else { [string]$service.Status }
        if ($service.Status -eq "Running") { $spoolerColor = [System.Drawing.Color]::FromArgb(21,115,71) }
    } catch {}
    $machineValueX = 92
    $machineValueWidth = [Math]::Max(80, $layout.CardWidth - 108)
    $machine.Controls.Add((New-Label -Text "Computador" -X 17 -Y 54 -Width 72 -Height 20 -Size 8 -Color $script:Muted))
    $machine.Controls.Add((New-Label -Text $env:COMPUTERNAME -X $machineValueX -Y 54 -Width $machineValueWidth -Height 20 -Size 8 -Style Bold))
    $machine.Controls.Add((New-Label -Text "Usuario" -X 17 -Y 84 -Width 72 -Height 20 -Size 8 -Color $script:Muted))
    $machine.Controls.Add((New-Label -Text $env:USERNAME -X $machineValueX -Y 84 -Width $machineValueWidth -Height 20 -Size 8 -Style Bold))
    $machine.Controls.Add((New-Label -Text "Spooler" -X 17 -Y 114 -Width 72 -Height 20 -Size 8 -Color $script:Muted))
    $machine.Controls.Add((New-Label -Text $spoolerStatus -X $machineValueX -Y 114 -Width $machineValueWidth -Height 20 -Size 8 -Style Bold -Color $spoolerColor))
    $machine.Controls.Add((New-Label -Text "PowerShell" -X 17 -Y 144 -Width 72 -Height 20 -Size 8 -Color $script:Muted))
    $machine.Controls.Add((New-Label -Text $PSVersionTable.PSVersion.ToString() -X $machineValueX -Y 144 -Width $machineValueWidth -Height 20 -Size 8 -Style Bold))
    $optimizeY = $machine.Height - 42
    $optimize = New-ActionButton -Title "Abrir manutencao" -Description "" -Action "Otimizacao" -X 16 -Y $optimizeY -Width ($layout.CardWidth - 32) -Height 31
    $optimize.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $optimize.Padding = New-Object System.Windows.Forms.Padding(0)
    $machine.Controls.Add($optimize)
    $Content.Controls.Add($machine)
    Finish-Content
}

function Show-PrintersPage {
    $script:CurrentPage = "Impressoras"
    Set-ActiveNavigation "Impressoras"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "Impressoras" -X 28 -Y 22 -Width 420 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Localize, instale e ajuste impressoras de rede ou locais" -X 29 -Y 55 -Width 520 -Height 22 -Size 9 -Color $script:Muted))
    $Content.Controls.Add((New-ActionButton -Title "IMPRESSORAS GRAFICAS" -Description "Varredura de rede e instalacao TCP/IP" -Action "ScanGraficas" -X $layout.X1 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "CUPOM / TERMICAS" -Description "Varredura com teste RAW na porta 9100" -Action "ScanCupom" -X $layout.X2 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "LOCAIS USB / COM" -Description "Detectar e configurar dispositivos conectados" -Action "ScanLocais" -X $layout.X3 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "USUARIO UNILABIMP / SPOOLER" -Description "Criar usuario, liberar PRINTERS e criar credencial" -Action "UsuarioSpooler" -X $layout.X1 -Y 236 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "REMOVER IMPRESSORA" -Description "Apagar somente a fila; preservar driver e porta" -Action "RemoverImpressora" -X $layout.X2 -Y 236 -Width $layout.CardWidth -Destructive))
    $Content.Controls.Add((New-ActionButton -Title "REMOVER DRIVER" -Description "Apagar somente o driver do fabricante" -Action "RemoverDriver" -X $layout.X3 -Y 236 -Width $layout.CardWidth -Destructive))
    Finish-Content
}

function Show-DriversPage {
    $script:CurrentPage = "Drivers"
    Set-ActiveNavigation "Drivers"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "Drivers e instaladores" -X 28 -Y 22 -Width 500 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Catalogo organizado por tipo de equipamento" -X 29 -Y 55 -Width 500 -Height 22 -Size 9 -Color $script:Muted))
    $Content.Controls.Add((New-ActionButton -Title "IMPRESSORAS GRAFICAS" -Description "HP, Epson, Brother, Canon, Lexmark e outras" -Action "DriversGraficas" -X $layout.X1 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "IMPRESSORAS DE CUPOM" -Description "Epson TM-T20, Elgin e Bematech" -Action "DriversCupom" -X $layout.X2 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "ETIQUETADORAS" -Description "Zebra, Elgin, TOMATE e Xprinter universal" -Action "Etiquetadoras" -X $layout.X3 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "WINGET" -Description "Instalar ou atualizar o gerenciador de pacotes" -Action "Winget" -X $layout.X1 -Y 236 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "CALIBRAR ETIQUETADORA" -Description "Xprinter, Zebra, Elgin e Argox; sensores, ribbon e teste" -Action "CalibrarEtiqueta" -X $layout.X2 -Y 236 -Width $layout.CardWidth))
    Finish-Content
}

function Show-UnilabCloudPage {
    $script:CurrentPage = "UnilabNuvem"
    Set-ActiveNavigation "UnilabNuvem"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "UnilabNuvem" -X 28 -Y 22 -Width 500 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Instalacao e atualizacao do cliente Unilab em nuvem" -X 29 -Y 55 -Width 560 -Height 22 -Size 9 -Color $script:Muted))
    $Content.Controls.Add((New-ActionButton -Title "UNILAB NUVEM 0.1.55" -Description "Baixar, validar e executar o instalador" -Action "UnilabNuvem" -X $layout.X1 -Y 105 -Width $layout.CardWidth))
    Finish-Content
}

function Show-UtilitiesPage {
    $script:CurrentPage = "Utilitarios"
    Set-ActiveNavigation "Utilitarios"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "Utilitarios" -X 28 -Y 22 -Width 500 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Ferramentas de acesso remoto e atendimento Unilab" -X 29 -Y 55 -Width 560 -Height 22 -Size 9 -Color $script:Muted))
    $Content.Controls.Add((New-ActionButton -Title "UNILAB RUSTDESK" -Description "Baixar, executar e aplicar prioridade alta" -Action "RustDesk" -X $layout.X1 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "PAINEL DE SENHAS" -Description "Painel Lancador, UniSenhas, UniCheckin e TesteBotoeira" -Action "PainelSenhas" -X $layout.X2 -Y 105 -Width $layout.CardWidth))
    Finish-Content
}

function Show-ComputerPage {
    $script:CurrentPage = "Computador"
    Set-ActiveNavigation "Computador"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "Computador" -X 28 -Y 22 -Width 420 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Configuracoes, manutencao e diagnostico local" -X 29 -Y 55 -Width 520 -Height 22 -Size 9 -Color $script:Muted))
    $Content.Controls.Add((New-ActionButton -Title "OTIMIZACAO E MANUTENCAO" -Description "Limpeza, energia, memoria e restauracao" -Action "Otimizacao" -X $layout.X1 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "USUARIO / SPOOLER" -Description "Criar Unilabimp e liberar a pasta PRINTERS" -Action "UsuarioSpooler" -X $layout.X2 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "INSTALAR / ATUALIZAR WINGET" -Description "Preparar o Windows para instalacoes" -Action "Winget" -X $layout.X3 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "DESATIVAR UAC" -Description "Aplicar acesso administrativo sem solicitacoes" -Action "DisableUAC" -X $layout.X1 -Y 236 -Width $layout.CardWidth -Destructive))
    $Content.Controls.Add((New-ActionButton -Title "FIREWALL E PORTAS" -Description "Gerenciar perfis, criar e validar regras" -Action "Firewall" -X $layout.X2 -Y 236 -Width $layout.CardWidth -Destructive))
    $Content.Controls.Add((New-ActionButton -Title "REMOVER USUARIOS" -Description "Listar contas locais e selecionar quais remover" -Action "RemoveUsers" -X $layout.X3 -Y 236 -Width $layout.CardWidth -Destructive))
    Finish-Content
}

function Show-NetworkPage {
    $script:CurrentPage = "Rede"
    Set-ActiveNavigation "Rede"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "Rede" -X 28 -Y 22 -Width 420 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Diagnostico, DNS e configuracao de IP com rollback automatico" -X 29 -Y 55 -Width 620 -Height 22 -Size 9 -Color $script:Muted))
    $Content.Controls.Add((New-ActionButton -Title "DIAGNOSTICO DE REDE" -Description "Ver IP, gateway, DHCP e DNS das interfaces ativas" -Action "Rede" -X $layout.X1 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "TESTAR DNS" -Description "Medir a latencia dos principais servidores DNS" -Action "Rede" -X $layout.X2 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "IP FIXO SEGURO" -Description "Configurar IPv4 e testar por ate 30s; rollback automatico se falhar" -Action "Rede" -X $layout.X3 -Y 105 -Width $layout.CardWidth))
    $Content.Controls.Add((New-ActionButton -Title "RESTAURAR REDE" -Description "Abrir o menu para restaurar backup ou DHCP/DNS automaticos" -Action "Rede" -X $layout.X1 -Y 236 -Width $layout.CardWidth))
    Finish-Content
}

function Show-HistoryPage {
    $script:CurrentPage = "Historico"
    Set-ActiveNavigation "Historico"
    Clear-Content
    $layout = Get-ResponsiveLayout
    $Content.Controls.Add((New-Label -Text "Historico" -X 28 -Y 22 -Width 420 -Height 31 -Size 17 -Style Bold))
    $Content.Controls.Add((New-Label -Text "Registros gerados pelas rotinas de manutencao" -X 29 -Y 55 -Width 520 -Height 22 -Size 9 -Color $script:Muted))
    $logPanel = New-InfoPanel -Title "Logs encontrados" -X $layout.X1 -Y 105 -Width $layout.UsableWidth -Height 300
    $logDir = Join-Path $PSScriptRoot "LOGS"
    $logs = @()
    if (Test-Path -LiteralPath $logDir) {
        $logs = @(Get-ChildItem -LiteralPath $logDir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 7)
    }
    if ($logs.Count -eq 0) {
        $logPanel.Controls.Add((New-Label -Text "Nenhum registro foi criado ainda." -X 17 -Y 60 -Width 400 -Height 24 -Size 9 -Color $script:Muted))
    } else {
        $y = 52
        foreach ($log in $logs) {
            $logPanel.Controls.Add((New-Label -Text $log.Name -X 17 -Y $y -Width 430 -Height 22 -Size 9 -Style Bold))
            $dateX = [Math]::Max(360, $layout.UsableWidth - 160)
            $logPanel.Controls.Add((New-Label -Text $log.LastWriteTime.ToString("dd/MM/yyyy HH:mm") -X $dateX -Y $y -Width 140 -Height 22 -Size 8 -Color $script:Muted))
            $y += 31
        }
    }
    $openLogs = New-Object System.Windows.Forms.Button
    $openLogs.Text = "Abrir pasta de logs"
    $openLogs.Location = New-Object System.Drawing.Point(17,248)
    $openLogs.Size = New-Object System.Drawing.Size(160,34)
    $openLogs.FlatStyle = "Flat"
    $openLogs.BackColor = $script:Accent
    $openLogs.ForeColor = [System.Drawing.Color]::White
    $openLogs.FlatAppearance.BorderSize = 0
    $openLogs.Cursor = [System.Windows.Forms.Cursors]::Hand
    $openLogs.Tag = $logDir
    $openLogs.Add_Click({
        $targetLogDir = [string]$this.Tag
        if (-not (Test-Path -LiteralPath $targetLogDir)) { New-Item -ItemType Directory -Force -Path $targetLogDir | Out-Null }
        Start-Process explorer.exe -ArgumentList "`"$targetLogDir`""
    })
    $logPanel.Controls.Add($openLogs)
    $Content.Controls.Add($logPanel)
    Finish-Content
}

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Utilitario Uniware - Interface Responsiva v0.3.29"
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Form.Size = New-Object System.Drawing.Size(1040,670)
$Form.MinimumSize = New-Object System.Drawing.Size(900,620)
$Form.BackColor = $script:Background
$Form.Font = New-UiFont -Size 9
$Form.Icon = [System.Drawing.SystemIcons]::Application
$Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$SidebarPanel = New-Object System.Windows.Forms.Panel
$SidebarPanel.Dock = [System.Windows.Forms.DockStyle]::Left
$SidebarPanel.Width = 214
$SidebarPanel.BackColor = $script:Sidebar
$Form.Controls.Add($SidebarPanel)

$Brand = New-Label -Text "UNIWARE" -X 22 -Y 24 -Width 160 -Height 28 -Size 14 -Style Bold -Color ([System.Drawing.Color]::White)
$SidebarPanel.Controls.Add($Brand)
$SidebarPanel.Controls.Add((New-Label -Text "Utilitario tecnico  v0.3.29" -X 23 -Y 53 -Width 175 -Height 20 -Size 8 -Color $script:SidebarMuted))
$SidebarPanel.Controls.Add((New-Label -Text "FERRAMENTAS" -X 22 -Y 105 -Width 150 -Height 18 -Size 7 -Style Bold -Color $script:SidebarMuted))

function Add-NavButton {
    param([string]$Text,[string]$Page,[int]$Y)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "   $Text"
    $button.Tag = $Page
    $button.Location = New-Object System.Drawing.Point(12,$Y)
    $button.Size = New-Object System.Drawing.Size(190,42)
    $button.Font = New-UiFont -Size 9
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $script:Sidebar
    $button.ForeColor = $script:SidebarMuted
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_Click({
        switch ([string]$this.Tag) {
            "Inicio"      { Show-HomePage }
            "Impressoras" { Show-PrintersPage }
            "Drivers"     { Show-DriversPage }
            "UnilabNuvem" { Show-UnilabCloudPage }
            "Utilitarios" { Show-UtilitiesPage }
            "Computador"  { Show-ComputerPage }
            "Rede"        { Show-NetworkPage }
            "Historico"   { Show-HistoryPage }
        }
    })
    $script:NavButtons += $button
    $SidebarPanel.Controls.Add($button)
}

Add-NavButton -Text "Inicio" -Page "Inicio" -Y 132
Add-NavButton -Text "Impressoras" -Page "Impressoras" -Y 177
Add-NavButton -Text "Drivers" -Page "Drivers" -Y 222
Add-NavButton -Text "UnilabNuvem" -Page "UnilabNuvem" -Y 267
Add-NavButton -Text "Utilitarios" -Page "Utilitarios" -Y 312
Add-NavButton -Text "Computador" -Page "Computador" -Y 357
Add-NavButton -Text "Rede" -Page "Rede" -Y 402
Add-NavButton -Text "Historico" -Page "Historico" -Y 447

$TechnicianLabel = New-Label -Text "Tecnico local" -X 22 -Y 545 -Width 170 -Height 20 -Size 9 -Style Bold -Color ([System.Drawing.Color]::White)
$TechnicianLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
$SidebarPanel.Controls.Add($TechnicianLabel)
$ComputerLabel = New-Label -Text ("PC: " + $env:COMPUTERNAME) -X 22 -Y 568 -Width 170 -Height 20 -Size 8 -Color $script:SidebarMuted
$ComputerLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom
$SidebarPanel.Controls.Add($ComputerLabel)

$Content = New-Object System.Windows.Forms.Panel
$Content.Location = New-Object System.Drawing.Point(214,0)
$Content.Size = New-Object System.Drawing.Size(($Form.ClientSize.Width - 214),$Form.ClientSize.Height)
$Content.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$Content.BackColor = $script:Background
$Content.AutoScroll = $true
$Form.Controls.Add($Content)

$script:CurrentPage = "Inicio"
$ResizeTimer = New-Object System.Windows.Forms.Timer
$ResizeTimer.Interval = 140
$ResizeTimer.Add_Tick({
    $ResizeTimer.Stop()
    switch ($script:CurrentPage) {
        "Inicio"      { Show-HomePage }
        "Impressoras" { Show-PrintersPage }
        "Drivers"     { Show-DriversPage }
        "UnilabNuvem" { Show-UnilabCloudPage }
        "Utilitarios" { Show-UtilitiesPage }
        "Computador"  { Show-ComputerPage }
            "Rede"        { Show-NetworkPage }
        "Historico"   { Show-HistoryPage }
    }
})
$Content.Add_Resize({
    if ($Form.Visible -and $Content.ClientSize.Width -gt 0) {
        $ResizeTimer.Stop()
        $ResizeTimer.Start()
    }
})

$Form.Add_Shown({ Show-HomePage })
[void]$Form.ShowDialog()

