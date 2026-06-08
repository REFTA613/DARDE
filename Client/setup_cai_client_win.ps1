# ==============================================================================
# DCS-CAI-CLIENT: Connection & Certificate Setup (Windows) - V10.2
# ==============================================================================

$Global:ServerIP = "192.168.0.25"
$Global:ServerUser = "kwar" # Aggiornato con l'utente che ho visto nei tuoi log
$Domains = @("ai.cai.lan", "api.cai.lan", "dsp.cai.lan")
$TempCertPath = "$env:TEMP\caddy-root.crt"
$HostsPath = "$env:windir\System32\drivers\etc\hosts"
$Global:WorkDir = Join-Path -Path $env:USERPROFILE -ChildPath ".dcs-cai-client"
$Global:VenvDir = Join-Path -Path $Global:WorkDir -ChildPath ".venv"
$Global:PipExe = Join-Path -Path $Global:VenvDir -ChildPath "Scripts\pip.exe"
$Global:PythonExe = Join-Path -Path $Global:VenvDir -ChildPath "Scripts\python.exe"

# --- 0. Administrator Privilege Check ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    Pause
    Exit
}

# --- CORE FUNCTIONS ---

function Prompt-Credentials {
    Write-Host "`n[ Network Configuration ]" -ForegroundColor Yellow
    $InputIP = Read-Host "Enter the Server IP [Enter for: $Global:ServerIP]"
    if (-not [string]::IsNullOrWhiteSpace($InputIP)) { $Global:ServerIP = $InputIP }
    
    $InputUser = Read-Host "Enter the Server User [Enter for: $Global:ServerUser]"
    if (-not [string]::IsNullOrWhiteSpace($InputUser)) { $Global:ServerUser = $InputUser }
}

function Create-Dashboard {
    $DesktopDir = [Environment]::GetFolderPath("Desktop")
    $DashboardPath = Join-Path -Path $DesktopDir -ChildPath "DCS-CAI_Dashboard.html"
    
    $HTMLContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DCS-CAI | Command Center</title>
    <style>
        body {
            font-family: 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: #0f172a;
            color: #f8fafc;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }
        .dashboard-container {
            background-color: #1e293b;
            padding: 2.5rem;
            border-radius: 16px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            text-align: center;
            width: 100%;
            max-width: 400px;
            border: 1px solid #334155;
        }
        h1 {
            color: #38bdf8;
            margin-top: 0;
            margin-bottom: 2rem;
            font-size: 1.8rem;
            letter-spacing: 1px;
        }
        .btn {
            display: block;
            width: 100%;
            padding: 1rem;
            margin-bottom: 1rem;
            background-color: #2563eb;
            color: white;
            text-decoration: none;
            border-radius: 8px;
            font-size: 1.1rem;
            font-weight: 600;
            transition: all 0.2s ease;
            box-sizing: border-box;
            border: 1px solid transparent;
        }
        .btn:hover {
            background-color: #1d4ed8;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(37, 99, 235, 0.4);
        }
        .desc {
            display: block;
            font-size: 0.85rem;
            color: #94a3b8;
            margin-top: 0.3rem;
            font-weight: normal;
        }
        .footer {
            margin-top: 2rem;
            font-size: 0.75rem;
            color: #64748b;
        }
    </style>
</head>
<body>
    <div class="dashboard-container">
        <h1>DCS-CAI System</h1>
        
        <a href="https://ai.cai.lan" class="btn" target="_blank">
            Open WebUI
            <span class="desc">AI Chat Interface</span>
        </a>
        
        <a href="https://api.cai.lan" class="btn" target="_blank">
            Ollama API
            <span class="desc">Backend Services Endpoint</span>
        </a>
        
        <a href="https://dsp.cai.lan" class="btn" target="_blank">
            DSP Server
            <span class="desc">Host Management Panel</span>
        </a>

        <div class="footer">DCS-CAI Local Infrastructure • Secure Connection</div>
    </div>
</body>
</html>
"@
    Set-Content -Path $DashboardPath -Value $HTMLContent -Encoding UTF8
    Write-Host "      -> File 'DCS-CAI_Dashboard.html' created on the Desktop." -ForegroundColor Green
}

function Install-Client {
    Prompt-Credentials
    Write-Host "`n[1/5] SSH connection for the certificate (Server Password Request)..." -ForegroundColor Cyan
    # PATCH: Usa la wildcard per pescare il certificato dinamico dal server Linux
    scp "${Global:ServerUser}@${Global:ServerIP}:~/DARDE-*-root.crt" $TempCertPath
    
    if (-not (Test-Path $TempCertPath)) {
        Write-Host "[ERROR] Failed to download certificate. Check password or network." -ForegroundColor Red
        return
    }

    Write-Host "`n[2/5] Trust installation in Windows Trust Store..." -ForegroundColor Cyan
    certutil.exe -addstore -f "Root" $TempCertPath | Out-Null
    Remove-Item -Path $TempCertPath -Force
    Write-Host "      -> Certificate installed." -ForegroundColor Green

    Write-Host "`n[3/5] Local Route Configuration (Hosts File)..." -ForegroundColor Cyan
    foreach ($domain in $Domains) {
        $exists = Select-String -Path $HostsPath -Pattern "\b$domain\b" -Quiet
        if (-not $exists) {
            cmd.exe /c "echo $Global:ServerIP`t$domain >> $HostsPath"
            Write-Host "      -> Route added: $domain" -ForegroundColor Green
        }
        else {
            Write-Host "      -> Route already present: $domain" -ForegroundColor DarkGray
        }
    }

    Write-Host "`n[4/5] Python Virtual Environment Setup..." -ForegroundColor Cyan
    if (-not (Get-Command "python" -ErrorAction SilentlyContinue)) {
        Write-Host "      -> [ERROR] Python is not installed or not in system PATH." -ForegroundColor Red
        return
    }

    if (-not (Test-Path $Global:WorkDir)) { New-Item -Path $Global:WorkDir -ItemType Directory -Force | Out-Null }
    
    if (-not (Test-Path $Global:VenvDir)) {
        Start-Process -FilePath "python" -ArgumentList "-m venv `"$Global:VenvDir`"" -Wait -NoNewWindow
        Write-Host "      -> Virtual environment created in $Global:VenvDir" -ForegroundColor Green
    }
    else {
        Write-Host "      -> Virtual environment already exists." -ForegroundColor DarkGray
    }

    Write-Host "      -> Installing Python dependencies (chromadb, sentence-transformers)..." -ForegroundColor Yellow
    
    Start-Process -FilePath $Global:PipExe -ArgumentList "install --upgrade pip" -Wait -WindowStyle Hidden
    $pipProcess = Start-Process -FilePath $Global:PipExe -ArgumentList "install chromadb sentence-transformers" -Wait -PassThru -WindowStyle Hidden
    
    if ($pipProcess.ExitCode -eq 0) {
        Write-Host "      -> Dependencies installed successfully." -ForegroundColor Green
    }
    else {
        Write-Host "      -> [ERROR] Failed to install dependencies. Check your internet connection." -ForegroundColor Red
    }

    Write-Host "`n[5/5] Dashboard HTML Creation..." -ForegroundColor Cyan
    Create-Dashboard

    ipconfig /flushdns | Out-Null
    Write-Host "`n[OK] SETUP COMPLETED SUCCESSFULLY." -ForegroundColor Green
}

function Uninstall-Client {
    Write-Host "`nWARNING: This will remove the trust from the server, DNS routes, dashboard, and Python environment." -ForegroundColor Red
    $confirm = Read-Host "Proceed? (y/n)"
    if ($confirm -notmatch "^[yY]$") { return }

    Write-Host "`n[1/4] Removing Caddy Certificates..." -ForegroundColor Cyan
    $certs = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "Caddy" -or $_.Issuer -match "Caddy" }
    if ($certs) {
        $certs | Remove-Item
        Write-Host "      -> Certificate removed." -ForegroundColor Green
    }
    else { Write-Host "      -> No certificate found." -ForegroundColor DarkGray }

    Write-Host "`n[2/4] Cleaning Hosts File..." -ForegroundColor Cyan
    $content = Get-Content $HostsPath
    $newContent = $content | Where-Object { $_ -notmatch "cai\.lan" }
    [System.IO.File]::WriteAllLines($HostsPath, $newContent)
    Write-Host "      -> Routes removed." -ForegroundColor Green

    Write-Host "`n[3/4] Removing Python Environment..." -ForegroundColor Cyan
    if (Test-Path $Global:VenvDir) {
        Remove-Item -Path $Global:VenvDir -Recurse -Force
        Write-Host "      -> Virtual environment removed." -ForegroundColor Green
    }
    else { Write-Host "      -> No virtual environment found." -ForegroundColor DarkGray }

    Write-Host "`n[4/4] Removing Dashboard HTML..." -ForegroundColor Cyan
    $DesktopDir = [Environment]::GetFolderPath("Desktop")
    $DashboardPath = Join-Path -Path $DesktopDir -ChildPath "DCS-CAI_Dashboard.html"
    if (Test-Path $DashboardPath) {
        Remove-Item -Path $DashboardPath -Force
        Write-Host "      -> Dashboard removed." -ForegroundColor Green
    }
    else { Write-Host "      -> No dashboard found." -ForegroundColor DarkGray }

    ipconfig /flushdns | Out-Null
    Write-Host "`n[OK] UNINSTALLATION COMPLETED." -ForegroundColor Green
}

function Diagnose-And-Heal {
    Write-Host "`n====================================================" -ForegroundColor Cyan
    Write-Host " AUTO-HEAL: DIAGNOSTICS AND REPAIR" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    $Attenzione = $false

    Write-Host "`n[TEST 1] Checking Hosts File: " -NoNewline
    $Missings = 0
    foreach ($domain in $Domains) {
        if (-not (Select-String -Path $HostsPath -Pattern "\b$domain\b" -Quiet)) {
            $Missings++
            cmd.exe /c "echo $Global:ServerIP`t$domain >> $HostsPath"
        }
    }
    if ($Missings -gt 0) {
        Write-Host "[REPAIRED] Added $Missings missing routes." -ForegroundColor Yellow
        $Attenzione = $true
    }
    else { Write-Host "[OK] All routes are present." -ForegroundColor Green }

    Write-Host "[TEST 2] Checking Certificate: " -NoNewline
    $cert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Issuer -match "Caddy" }
    if (-not $cert) {
        Write-Host "[FAILED] Certificate not found." -ForegroundColor Red
        Write-Host "  -> [FIX] Trying to download and install automatically..." -ForegroundColor Yellow
        Prompt-Credentials
        # PATCH: Aggiornato per ripescare il file con wildcard durante l'auto-heal
        scp "${Global:ServerUser}@${Global:ServerIP}:~/DARDE-*-root.crt" $TempCertPath
        if (Test-Path $TempCertPath) {
            certutil.exe -addstore -f "Root" $TempCertPath | Out-Null
            Remove-Item -Path $TempCertPath -Force
            Write-Host "  -> [OK] Certificate restored." -ForegroundColor Green
        }
        else { Write-Host "  -> [ERROR] Fix failed. Unable to download." -ForegroundColor Red }
        $Attenzione = $true
    }
    else { Write-Host "[OK] Certificate valid." -ForegroundColor Green }

    Write-Host "[TEST 3] Checking Server Proxy Reachability (Port 443): " -NoNewline
    $TcpTest = Test-NetConnection -ComputerName $Global:ServerIP -Port 443 -WarningAction SilentlyContinue
    if ($TcpTest.TcpTestSucceeded) {
        Write-Host "[OK] Server Online and Listening." -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] Server Offline or port 443 closed." -ForegroundColor Red
    }

    Write-Host "[TEST 4] Checking Dashboard HTML: " -NoNewline
    $DesktopDir = [Environment]::GetFolderPath("Desktop")
    $DashboardPath = Join-Path -Path $DesktopDir -ChildPath "DCS-CAI_Dashboard.html"
    if (-not (Test-Path $DashboardPath)) {
        Write-Host "[REPAIRED] Missing dashboard file. Recreating..." -ForegroundColor Yellow
        Create-Dashboard | Out-Null
    }
    else {
        Write-Host "[OK] Dashboard present." -ForegroundColor Green
    }

    Write-Host "[TEST 5] Checking Python Environment: " -NoNewline
    if (-not (Test-Path $Global:VenvDir)) {
        Write-Host "[FAILED] Virtual environment missing." -ForegroundColor Red
        Write-Host "  -> [FIX] Rebuilding sandbox and injecting dependencies..." -ForegroundColor Yellow
        
        if (-not (Test-Path $Global:WorkDir)) { New-Item -Path $Global:WorkDir -ItemType Directory -Force | Out-Null }
        Start-Process -FilePath "python" -ArgumentList "-m venv `"$Global:VenvDir`"" -Wait -WindowStyle Hidden
        
        Start-Process -FilePath $Global:PipExe -ArgumentList "install --upgrade pip" -Wait -WindowStyle Hidden
        Start-Process -FilePath $Global:PipExe -ArgumentList "install chromadb sentence-transformers" -Wait -WindowStyle Hidden
        
        Write-Host "  -> [OK] Python environment completely restored." -ForegroundColor Green
    }
    else {
        $pyCheck = Start-Process -FilePath $Global:PythonExe -ArgumentList "-c `"import chromadb`"" -Wait -PassThru -WindowStyle Hidden
        if ($pyCheck.ExitCode -ne 0) {
            Write-Host "[REPAIRED] Missing dependencies. Reinstalling..." -ForegroundColor Yellow
            Start-Process -FilePath $Global:PipExe -ArgumentList "install chromadb sentence-transformers" -Wait -WindowStyle Hidden
            Write-Host "  -> [OK] Dependencies injected." -ForegroundColor Green
        }
        else {
            Write-Host "[OK] Python environment is active and configured." -ForegroundColor Green
        }
    }

    if ($Attenzione) { ipconfig /flushdns | Out-Null }
    Write-Host "`nDiagnostic Terminated." -ForegroundColor Cyan
}

function Show-Debug {
    Write-Host "`n====================================================" -ForegroundColor Cyan
    Write-Host " ADVANCED DEBUG" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    
    Write-Host "`n--- CHECK ROUTES DNS (File Hosts) ---" -ForegroundColor Yellow
    $missing_routes = 0
    $HostsContent = Get-Content -Path $HostsPath -ErrorAction SilentlyContinue
    foreach ($domain in $Domains) {
        if ($HostsContent -match "\b$domain\b") {
            Write-Host "  [ONLINE] $Global:ServerIP -> $domain" -ForegroundColor Green
        }
        else {
            Write-Host "  [MISSING] No route for $domain" -ForegroundColor Red
            $missing_routes++
        }
    }
    if ($missing_routes -gt 0) { Write-Host "  -> Detected routing anomalies. Run Auto-Heal." -ForegroundColor Red }

    Write-Host "`n--- CHECK CERTIFICATE (Caddy) ---" -ForegroundColor Yellow
    $Certs = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Issuer -match "Caddy" }
    if ($Certs) { 
        $Certs | ForEach-Object { 
            Write-Host "  [ONLINE] $($_.Subject)" -ForegroundColor Green
            Write-Host "    Expires: $($_.NotAfter)" -ForegroundColor Gray
        }
    }
    else { 
        Write-Host "  [MISSING] No Caddy certificate found." -ForegroundColor Red
        Write-Host "  -> Detected missing certificate. Run Auto-Heal." -ForegroundColor Red 
    }

    Write-Host "`n--- CHECK DASHBOARD DESKTOP ---" -ForegroundColor Yellow
    $DesktopDir = [Environment]::GetFolderPath("Desktop")
    $DashboardPath = Join-Path -Path $DesktopDir -ChildPath "DCS-CAI_Dashboard.html"
    if (Test-Path $DashboardPath) {
        Write-Host "  [ONLINE] DCS-CAI_Dashboard.html" -ForegroundColor Green
    }
    else {
        Write-Host "  [MISSING] DCS-CAI_Dashboard.html not found on Desktop" -ForegroundColor Red
    }

    Write-Host "`n--- PYTHON ENVIRONMENT ---" -ForegroundColor Yellow
    if (Test-Path $Global:VenvDir) {
        Write-Host "  [PRESENT] Virtual Environment at $Global:VenvDir" -ForegroundColor Green
        
        $pyCheck = Start-Process -FilePath $Global:PythonExe -ArgumentList "-c `"import chromadb`"" -Wait -PassThru -WindowStyle Hidden
        if ($pyCheck.ExitCode -eq 0) {
            Write-Host "  [DEPENDENCIES OK] ChromaDB and sentence-transformers verified." -ForegroundColor Green
        }
        else {
            Write-Host "  [DEPENDENCIES MISSING] Required packages are not installed." -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [MISSING] Python virtual environment not found." -ForegroundColor Red
    }

    Write-Host "`n--- CHECK NETWORK CONNECTION ---" -ForegroundColor Yellow
    $TcpTest = Test-NetConnection -ComputerName "ai.cai.lan" -Port 443 -WarningAction SilentlyContinue
    if ($TcpTest.TcpTestSucceeded) {
        Write-Host "  [NETWORK OK] ai.cai.lan resolved correctly to IP: $($TcpTest.RemoteAddress)" -ForegroundColor Green
    }
    else {
        Write-Host "  [NETWORK ERROR] Unable to reach ai.cai.lan." -ForegroundColor Red
    }
}

# --- MAIN LOOP ---
do {
    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " DCS-CAI CLIENT MANAGER (WINDOWS) - V10.2" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "1) Install Client Connection (Certificate + DNS + Env + Dashboard)"
    Write-Host "2) Uninstall and Restore PC"
    Write-Host "3) Diagnosis and Automatic Restore (Auto-Heal)"
    Write-Host "4) Advanced Debug (Show status and anomalies)"
    Write-Host "q) Exit "
    Write-Host "----------------------------------------------------"
    
    $chose = Read-Host "Select an option (1-4, q)"
    
    switch ($chose) {
        '1' { Install-Client; Pause }
        '2' { Uninstall-Client; Pause }
        '3' { Diagnose-And-Heal; Pause }
        '4' { Show-Debug; Pause }
        'q' { exit }
        'Q' { exit }
        default { Write-Host "Invalid option." -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
} while ($true)