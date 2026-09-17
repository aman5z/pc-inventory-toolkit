# Lab PC Inventory Toolkit

Collects: hostname, IP, manufacturer, model, serial number, CPU, RAM, storage
(model/serial/size per drive), Windows version, monitor (manufacturer/model/serial),
keyboard/mouse (model + device ID — see limitation below), and printers.

## ⚠️ Peripheral serial number reality check
- **Monitors**: serial number IS usually available (via `WmiMonitorID`) — included automatically.
- **USB keyboards/mice**: most consumer models do **not** expose a real serial number
  over USB HID, even to Windows itself — this isn't a script limitation, it's how the
  hardware reports itself. The script captures model/description and the device's
  VID/PID identifier instead, which is often enough to distinguish models but not
  individual units.
- **Printers**: name, driver, and port are captured; a true hardware serial requires
  vendor-specific queries and isn't reliably available for network/USB printers via WMI.

## Part 1 — Set up the Google Sheet backend (one-time, ~5 minutes)

1. Create a new Google Sheet (any name, e.g. "Lab PC Inventory").
2. Extensions → Apps Script.
3. Delete the default code, paste in the contents of `Code.gs`.
4. Click **Deploy → New deployment**.
5. Type: **Web app**.
   - Execute as: **Me**
   - Who has access: **Anyone** (needed so the lab PCs can POST without a login prompt)
6. Deploy → copy the **Web app URL** it gives you (ends in `/exec`).
7. Paste that URL into `Collect-Inventory.ps1`, replacing `$GoogleScriptUrl`.
8. Test it: open the URL in a browser — you should see "Inventory collector is live."

## Part 2 — Choose how you'll run it

### Option A — Remote pull (recommended, no USB needed)
For any machine where you've already enabled WinRM (per your earlier fix):

```powershell
$hosts = Get-Content .\hosts.txt
$cred  = Get-Credential          # .\admin / Gaesous180

$data = Invoke-Command -ComputerName $hosts -Credential $cred `
        -FilePath .\Collect-Inventory.ps1 -ErrorAction SilentlyContinue

$data | Export-Csv .\all-labs-inventory-backup.csv -NoTypeInformation
```

This uploads every machine straight to your Google Sheet in one shot, AND keeps a
local CSV backup on your admin PC regardless. No physical visit needed for any
machine that already has WinRM enabled.

### Option B — USB stick (for machines without WinRM yet, or as a walk-around backup)

1. Copy these 2 files to the root of a USB drive:
   - `Collect-Inventory.ps1`
   - `Run-Inventory.bat`
2. Plug into a lab PC, open the drive, **double-click `Run-Inventory.bat`**.
3. It runs, uploads to your Sheet (or saves locally to `inventory-fallback.csv`
   on the USB drive if there's no internet on that machine), then closes.

**Note on "autorun":** Windows disabled true automatic execution from USB drives
years ago (security measure against USB malware) — this can't be re-enabled safely,
and doing so would also be a real security risk for a shared lab environment.
Double-click is one click away from automatic and is the standard, safe approach
IT toolkits use today.

If you want something closer to automatic later, once every machine already has
WinRM enabled it stops mattering — you'll just run inventory collection remotely
from your admin PC (Option A) with zero physical visits at all.

## Part 3 — Offline fallback
If a machine has no internet/network access when the script runs, it automatically
writes to `inventory-fallback.csv` next to the script instead of failing silently.
Collect these CSVs later and either:
- Paste rows into the Google Sheet manually, or
- Import each CSV into a "master" local Excel file as a fallback record.
