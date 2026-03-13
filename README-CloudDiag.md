# Azure Migrate - Cloud Shell Diagnostic Analyzer

## What It Does

Checks the **Azure side** of your Azure Migrate configuration after an issue is reproduced. Read-only — makes no changes.

| Check | What It Looks For |
|---|---|
| Migrate project | Does the project exist and are resources healthy |
| Appliance registration | OffAzure resources, provisioning state, agent status |
| Private endpoints | Connection status (Approved/Pending/Rejected) |
| Private DNS zones | Required zones exist, VNet linked, A records present |
| NSG rules | Outbound deny rules blocking port 443 |
| Key Vault | Firewall rules blocking appliance access |
| Storage accounts | Network rules, infrastructure encryption conflicts |
| Azure Policy | Policies enforcing requireInfrastructureEncryption that break Migrate |
| Activity log | Errors in last 24h with pattern-matched guidance |

## Prerequisites

- **Azure Cloud Shell (PowerShell)** or local PowerShell with Az modules installed
- **Reader** role (minimum) on the subscription containing the Migrate project
- Know the **Resource Group name** where your Azure Migrate project lives

## How to Run

### Option 1: Azure Cloud Shell (Recommended)

1. Go to [https://shell.azure.com](https://shell.azure.com)
2. Select **PowerShell**
3. Upload the script:
   ```
   Click the Upload/Download button (↑) → Upload → select Invoke-AzMigrateCloudDiag.ps1
   ```
4. Run it:
   ```powershell
   ./Invoke-AzMigrateCloudDiag.ps1
   ```

### Option 2: Local PowerShell

1. Install Az modules (if not already):
   ```powershell
   Install-Module Az -Scope CurrentUser -Force
   ```
2. Run the script:
   ```powershell
   .\Invoke-AzMigrateCloudDiag.ps1
   ```

## What It Asks

1. **Resource Group name** — the RG containing your Azure Migrate project
2. **Private Endpoints?** — Yes or No
3. **VNet Resource Group** — (only if using Private Endpoints and it's in a different RG)

## Reading the Output

- **[PASS]** = Check passed, no issues
- **[FAIL]** = Issue found — action and doc link provided
- **[WARN]** = Potential issue — review recommended
- **[INFO]** = Informational, no action needed

The script ends with a numbered **action plan** for all failures and a saved `.txt` report file.

## Safe to Run

- **Read-only** — only uses `Get-*` cmdlets, never writes to Azure
- **No policy violations** — does not create, modify, or delete any resources
- **Minimum permission** — Reader role is sufficient
