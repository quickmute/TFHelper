# TFHelper
Some powershell invoke-restmethod wrapper to be used against your Terraform Cloud account

## ChangeLog
### 3.0.0 (2026/04/05)
- Add state management cmdlets
- Cleaned up consistent passing in of token, org, and hostname
- Moved all functions to sub folder and added psmodule files
### 2.0.0 (2025/01/11)
- Add Modules cmdlets
  - Get List
  - Delete
  - Import
  - Clean
- Add Runs cmdlets
  - Cancel
  - Policy Check
  - Override Policy (soft sentinel)
  - Get Plan ID
  - Get Plan URL
  - Get Plan Content
- Add Workspace cmdlets
  - Get Id
  - 
