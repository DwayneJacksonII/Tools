# Azure Migrate Appliance - Connectivity Troubleshooter

## Invoke-AzMigrateConnectivityCheck.ps1

### BLUF

Run on the Azure Migrate appliance. Prompts for your deployment scenario, tests every required Azure URL (DNS → TCP → HTTPS), and tells you exactly which endpoints are blocked by firewall or proxy.

### What It Does

1. **Prompts** for cloud (Commercial/Gov), scenario (VMware Agentless/Agent-based Legacy/Modern), appliance type (Assessment/Replication), private link (Yes/No), and optional custom URLs from error messages
2. **Detects** proxy (WinHTTP, system/IE, env vars, PAC, .NET), SSL inspection, TLS 1.2 status, Windows Firewall, network config
3. **Tests** DNS resolution, TCP port 443, and HTTPS request for every required Azure Migrate endpoint — the same calls the appliance makes during registration/discovery
4. **Validates** Private Link DNS (checks privatelink URLs resolve to private IPs)
5. **Reports** pass/fail per endpoint with root cause (DNS / firewall block / TLS / proxy) and the wildcard firewall rule needed
6. **Saves** full report to a `.txt` file for sharing with network team or Support

### Prerequisites

| Requirement | Details |
|---|---|
| PowerShell | 5.1+ (built into Windows 10 / Server 2016+) |
| OS | Windows (same OS the appliance runs on) |
| Permissions | Local Admin recommended (for firewall/proxy checks) |
| Network | Run from the appliance itself, or any machine on the same network |

### How to Run

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Invoke-AzMigrateConnectivityCheck.ps1
```

Answer the 5 prompts, press Enter, wait 2-5 minutes.

### Reading the Output

| Result | Meaning | Likely Cause |
|---|---|---|
| **PASS** | DNS + TCP + HTTPS all succeeded | Endpoint is fully reachable |
| **FAIL (DNS)** | Hostname cannot be resolved | DNS server issue, DNS filtering, or Private DNS zone missing |
| **FAIL (TCP BLOCKED)** | DNS resolved but TCP/443 timed out | Firewall/NSG blocking outbound 443 |
| **FAIL (HTTPS)** | TCP connected but HTTPS failed | SSL inspection, proxy auth, TLS mismatch |

### Custom URL Testing

If you have a specific failing URL from an error message (e.g., auto-update manifest), paste it when prompted:

```
Do you have any specific URLs from error messages that you want to test?
URL: https://de995fbb-...-agent.uga.disc.privatelink.prod.migration.windowsazure.us/
  Added: de995fbb-...-agent.uga.disc.privatelink.prod.migration.windowsazure.us
```

### Output Files

```
AzMigrate-ConnectivityReport_YYYYMMDD_HHmmss.txt
```

Saved in the same folder as the script.

### Safety

- **Read-only** — makes no changes to the system
- Only local change: sets TLS 1.2 for the current PowerShell session (reverts when window closes)
- Writes only the `.txt` report file locally

---

## MigrateTroubleshooter.ps1

### BLUF

Quick 3-step test for a single URL. Paste the failing URL from an error message, run it, get instant DNS/TCP/HTTPS diagnosis.

### What It Does

Tests one specific URL in 3 steps:

| Step | Test | Pass | Fail |
|---|---|---|---|
| **[1/3]** | DNS resolution + private vs public IP check | Hostname resolves | DNS zone missing or not linked |
| **[2/3]** | TCP port 443 connection (5s timeout) | Port is open | Firewall/NSG blocking |
| **[3/3]** | HTTPS GET request | Endpoint reachable (even 401/403/404 = network OK) | SSL inspection, proxy, or TLS issue |

### Prerequisites

| Requirement | Details |
|---|---|
| PowerShell | 5.1+ |
| OS | Windows |
| Permissions | No admin required |

### How to Run

1. Edit **line 16** — replace the URL with the one from your error message:

```powershell
$url = "https://YOUR-FAILING-URL-HERE/"
```

2. Run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\MigrateTroubleshooter.ps1
```

### Example Output

```
=== Azure Migrate URL Connectivity Test ===
Testing: https://de995fbb-...-agent.uga.disc.privatelink.prod.migration.windowsazure.us/

[1/3] DNS Resolution ... RESOLVED -> 10.0.1.5
      Private IP detected (Private Link DNS is working)
[2/3] TCP connection to ...:443 ... CONNECTED
[3/3] HTTPS request ... HTTP 404 (endpoint reachable, network OK)

=== Test Complete ===
```

Or if blocked:

```
[1/3] DNS Resolution ... FAILED
      Cause: DNS cannot resolve this hostname.
      The private DNS zone 'privatelink.prod.migration.windowsazure.us'
      likely does not exist, is not linked to the VNet, or is missing the A record.
```

### When to Use This vs the Full Script

| Situation | Use |
|---|---|
| Need to test all required URLs for your scenario | `Invoke-AzMigrateConnectivityCheck.ps1` |
| Have a specific URL from an error message to test quickly | `MigrateTroubleshooter.ps1` |
| Customer sent you an error with a URL — need a fast answer | `MigrateTroubleshooter.ps1` |

### Safety

- **Read-only** — no files written, no system changes
- Only sets TLS 1.2 for the current PowerShell session
