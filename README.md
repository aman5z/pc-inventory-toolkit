# Lab PC Inventory Toolkit

PowerShell toolkit for collecting hardware/peripheral inventory from 100+
standalone (non-domain, workgroup) Windows PCs and syncing it to a Google
Sheet, with an offline CSV fallback. Includes a self-elevating one-click
launcher for USB-based collection, and a combined setup+collect mode that
also enables WinRM remote management on each machine as a side effect.

Collects: hostname, IP address, manufacturer, model, BIOS serial number,
CPU, RAM, storage (model/serial/size per drive), Windows version, monitor
(manufacturer/model/serial), keyboard/mouse (model + device ID - see
limitation below), and the default printer (name/driver/port).

Each upload is upserted into the Sheet by BIOS serial number - rerunning
the collector on the same machine updates its existing row instead of
creating a duplicate.

## ⚠️ Before you push this repo anywhere
This toolkit is built for a specific lab's local admin account. Before
committing/pushing:
- Do **not** hardcode real passwords into any script you commit. Use
  `Get-Credential` (prompts interactively) instead, or keep a local
  `config.ps1` that is excluded via `.gitignore`.
- Do **not** commit your real Google Apps Script URL if the deployment is
  set to "Anyone" access - anyone with that URL can POST fake rows into
  your live inventory sheet. Replace it with a placeholder in the
  committed version and keep the real one in an untracked config file.
- Consider excluding `hosts.txt` / `inventory-fallback.csv` if you'd
  rather not expose your lab's naming scheme or collected hardware data
  publicly.

## ⚠️ Peripheral serial number reality check
- **Monitors**: serial number IS usually available (via `WmiMonitorID`) - included automatically.
- **USB keyboards/mice**: most consumer models do **not** expose a real serial number
  over USB HID, even to Windows itself - this isn't a script limitation, it's how the
  hardware reports itself. The script captures model/description and the device's
  VID/PID identifier instead, which is often enough to distinguish models but not
  individual units.
- **Printers**: only the **default printer** is captured (name, driver, port). A real
  hardware serial is only attempted for directly USB-connected printers, and even then
  many models don't report one. Network/shared/WSD printers have no serial visible to
  Windows at all - this will correctly show `N/A (not exposed via network/driver)`.

## Part 1 - Set up the Google Sheet backend (one-time, ~5 minutes)

1. Create a new Google Sheet (any name, e.g. "Lab PC Inventory") with a tab
   named to match `SHEET_NAME` in `Code.gs` (default: `INVENTORY`).
2. Extensions → Apps Script.
3. Delete the default code, paste in the contents of `Code.gs`.
4. Click **Deploy → New deployment** → type: **Web app**.
   - Execute as: **Me**
   - Who has access: **Anyone** (needed so the lab PCs can POST without a login prompt)
5. Deploy → copy the **Web app URL** it gives you (ends in `/exec`).
6. Paste that URL into `Collect-Inventory.ps1`, replacing `$GoogleScriptUrl`.
7. Test it: open the URL in a browser - you should see "Inventory collector is live."
8. **Whenever you edit `Code.gs` later**, use **Deploy → Manage deployments →
   edit → New version** to update the *same* URL - don't create a brand new
   deployment, or your script's saved URL will go stale.

## Part 2 - Choose how you'll run it

### Option A - Remote pull (fastest, no physical visit needed)
For any machine where WinRM is already enabled (either from a prior visit,
or because it was set up via Option B below, which enables WinRM as a
side effect):

```powershell
$hosts = Get-Content .\hosts.txt
$cred  = Get-Credential          # prompts for username/password interactively

$data = Invoke-Command -ComputerName $hosts -Credential $cred `
        -FilePath .\Collect-Inventory.ps1 -ErrorAction SilentlyContinue

$data | Export-Csv .\all-labs-inventory-backup.csv -NoTypeInformation
```

This uploads every machine straight to your Google Sheet in one shot, AND keeps a
local CSV backup on your admin PC regardless. No physical visit needed for any
machine that already has WinRM enabled.

### Option B - USB stick, one-click (for machines without WinRM yet)

1. Copy these 2 files to the root of a USB drive:
   - `Collect-Inventory.ps1`
   - `Run-Inventory.bat`
2. Plug into a lab PC, open the drive, **double-click `Run-Inventory.bat`**.
3. Click **Yes** on the UAC prompt (the launcher self-elevates automatically).
4. It silently fixes the local prerequisites for future remote management
   (network profile → Private, disables ForceGuest, enables WinRM), then
   collects inventory and uploads it to your Sheet (or saves locally to
   `inventory-fallback.csv` if there's no internet on that machine).

Because this also enables WinRM, **every machine only needs this one visit,
ever** - future commands/re-collection on that machine can go through
Option A instead.

**Note on "autorun":** Windows disabled true automatic execution from USB drives
years ago (security measure against USB malware) - this can't be re-enabled safely.
One double-click + one UAC "Yes" is the closest and safest equivalent.

## Part 3 - Offline fallback
If a machine has no internet/network access when the script runs, it automatically
writes to `inventory-fallback.csv` next to the script instead of failing silently.
Collect these CSVs later and either:
- Paste rows into the Google Sheet manually, or
- Import each CSV into a "master" local Excel file as a fallback record.

Note: if an upload appears to "fail" with a timeout error but the row still
shows up in your Sheet, that's a slow Apps Script response, not a real
failure - the write already succeeded server-side before the client gave up
waiting. The script's timeout is set generously (45s) to minimize this.
