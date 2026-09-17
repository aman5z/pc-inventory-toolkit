# =====================================================================
# Collect-Inventory.ps1
#
# Collects hardware/software inventory from a Windows PC and uploads it to a
# Google Sheet (via Apps Script Web App) or falls back to a local CSV.
#
# USAGE
#   Local run (double-click via a .bat launcher, or run directly):
#       powershell -ExecutionPolicy Bypass -File Collect-Inventory.ps1
#
#   Remote run (from your admin PC, against a machine with WinRM enabled):
#       Invoke-Command -ComputerName BOYS-LAB1-04 -Credential $cred -FilePath .\Collect-Inventory.ps1
#
#   Remote run against ALL machines at once, results returned to admin PC:
#       $hosts  = Get-Content .\hosts.txt
#       $cred   = Get-Credential
#       $data   = Invoke-Command -ComputerName $hosts -Credential $cred -FilePath .\Collect-Inventory.ps1 -ErrorAction SilentlyContinue
#       $data | Export-Csv .\all-labs-inventory.csv -NoTypeInformation
#
# NOTES
#   - Edit GoogleScriptUrl below once you've deployed the Apps Script (see Code.gs).
#   - If no internet / POST fails, data is written to FallbackCsvPath instead.
#   - Keyboard/mouse serial numbers are usually NOT exposed by USB HID devices -
#     most consumer peripherals don't report one via Windows PnP. Model/VID/PID
#     is still captured where available. Monitor serials ARE usually available.
# =====================================================================

# ============ CONFIG - edit these two lines ============
$GoogleScriptUrl  = "https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec"
$FallbackCsvPath  = if ($PSScriptRoot) { "$PSScriptRoot\inventory-fallback.csv" } else { "$env:TEMP\inventory-fallback.csv" }
# =========================================================

# ---- One-time remote-access setup (safe to run every time, skips if already done) ----
# This also enables WinRM on this machine so you never have to visit it again for
# future remote commands - a nice side effect of running this once via USB.
function Set-RemoteAccessPrereqs {
    try {
        $profile = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($profile -and $profile.NetworkCategory -eq "Public") {
            Set-NetConnectionProfile -InterfaceAlias $profile.InterfaceAlias -NetworkCategory Private -ErrorAction SilentlyContinue
            Write-Host "  - Network profile set to Private" -ForegroundColor DarkGray
        }
    } catch { }

    try {
        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v ForceGuest /t REG_DWORD /d 0 /f | Out-Null
        Write-Host "  - ForceGuest policy disabled" -ForegroundColor DarkGray
    } catch { }

    try {
        $winrm = Get-Service WinRM -ErrorAction SilentlyContinue
        if ($winrm -and $winrm.Status -ne "Running") {
            Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  - WinRM enabled (this PC can now be managed remotely too)" -ForegroundColor DarkGray
        }
    } catch { }
}

Write-Host "Checking remote-access prerequisites..." -ForegroundColor DarkGray
Set-RemoteAccessPrereqs

function Get-MonitorInfo {
    # Monitor serial/model live in root\wmi, encoded as arrays of char codes (need decoding)
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        $result = foreach ($m in $monitors) {
            $mfg    = ($m.ManufacturerName  | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ""
            $model  = ($m.UserFriendlyName  | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ""
            $serial = ($m.SerialNumberID    | Where-Object {$_ -ne 0} | ForEach-Object {[char]$_}) -join ""
            "$mfg | $model | SN:$serial"
        }
        return ($result -join " ;; ")
    } catch {
        return "Not available"
    }
}

function Get-PeripheralInfo {
    # Best-effort: most USB mice/keyboards do NOT expose a real serial number.
    # We capture whatever Windows does report (model/description + device ID with VID/PID).
    try {
        $kb = Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue |
              ForEach-Object { "$($_.Description) [$($_.DeviceID)]" }
        $mouse = Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue |
              ForEach-Object { "$($_.Description) [$($_.DeviceID)]" }
        $defaultPrinter = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Default -eq $true }

        $printerInfo = "No default printer set"
        if ($defaultPrinter) {
            # Serial numbers are NOT exposed by Windows for printers via standard WMI.
            # This only has a chance of working for directly USB-connected printers,
            # and even then many printer models still don't report one over USB.
            # Network/shared/WSD printers have no serial visible to Windows at all.
            $usbSerial = "N/A (not exposed via network/driver)"
            if ($defaultPrinter.PortName -match "^USB") {
                try {
                    $pnp = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -like "*$($defaultPrinter.Name)*" -or $_.DeviceID -match "PRINTENUM" } |
                           Select-Object -First 1
                    if ($pnp -and $pnp.DeviceID -match "\\(.+)$") {
                        $usbSerial = $matches[1]
                    }
                } catch { }
            }
            $printerInfo = "$($defaultPrinter.Name) | Model/Driver:$($defaultPrinter.DriverName) | Port:$($defaultPrinter.PortName) | SN:$usbSerial"
        }

        return @{
            Keyboard = ($kb -join " ;; ")
            Mouse    = ($mouse -join " ;; ")
            Printers = $printerInfo
        }
    } catch {
        return @{ Keyboard = "Error"; Mouse = "Error"; Printers = "Error" }
    }
}

# ---- Core system info ----
$cs      = Get-CimInstance Win32_ComputerSystem
$bios    = Get-CimInstance Win32_BIOS
$os      = Get-CimInstance Win32_OperatingSystem
$cpu     = Get-CimInstance Win32_Processor | Select-Object -First 1
$disks   = Get-CimInstance Win32_DiskDrive | ForEach-Object {
              "$($_.Model) | SN:$($_.SerialNumber) | $([math]::Round($_.Size/1GB,1))GB"
           }
$ram_gb  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$ip      = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
            Select-Object -First 1 -ExpandProperty IPAddress)

$peripherals = Get-PeripheralInfo

$inventory = [PSCustomObject]@{
    Timestamp     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Hostname      = $env:COMPUTERNAME
    IPAddress     = $ip
    Manufacturer  = $cs.Manufacturer
    Model         = $cs.Model
    SerialNumber  = $bios.SerialNumber
    CPU           = $cpu.Name
    RAM_GB        = $ram_gb
    Storage       = ($disks -join " ;; ")
    WindowsVersion= "$($os.Caption) ($($os.Version))"
    Monitor       = Get-MonitorInfo
    Keyboard      = $peripherals.Keyboard
    Mouse         = $peripherals.Mouse
    Printers      = $peripherals.Printers
}

# ---- Try uploading to Google Sheet, fall back to local CSV ----
try {
    $json = $inventory | ConvertTo-Json -Compress
    $response = Invoke-RestMethod -Uri $GoogleScriptUrl -Method Post -Body $json -ContentType "application/json" -TimeoutSec 45

    if ($response.status -eq "updated") {
        Write-Host "Existing entry UPDATED for $($response.hostname) (row $($response.row)) - old data replaced." -ForegroundColor Cyan
    } elseif ($response.status -eq "added") {
        Write-Host "NEW entry ADDED for $($response.hostname) (row $($response.row))." -ForegroundColor Green
    } else {
        Write-Host "Uploaded to Google Sheet: $($inventory.Hostname)" -ForegroundColor Green
    }
} catch {
    Write-Host "Upload failed ($($_.Exception.Message)) - saving to local CSV instead." -ForegroundColor Yellow
    $exists = Test-Path $FallbackCsvPath
    $inventory | Export-Csv -Path $FallbackCsvPath -NoTypeInformation -Append:$exists
}

# Always return the object too (useful when run via Invoke-Command against many machines)
$inventory
