<#
.SYNOPSIS
    Loads and merges configuration for Claude Code Toast.
.DESCRIPTION
    Reads defaults.json from the project config folder, then deep-merges
    any user overrides from %LOCALAPPDATA%\ClaudeCodeToast\config.json.
    Returns a merged hashtable.
#>

function Merge-Hashtable {
    param(
        [hashtable]$Base,
        [hashtable]$Override
    )
    $result = $Base.Clone()
    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $result[$key] = Merge-Hashtable -Base $result[$key] -Override $Override[$key]
        } else {
            $result[$key] = $Override[$key]
        }
    }
    return $result
}

function ConvertTo-HashtableRecursive {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $ht = @{}
            foreach ($prop in $InputObject.PSObject.Properties) {
                $ht[$prop.Name] = ConvertTo-HashtableRecursive -InputObject $prop.Value
            }
            return $ht
        }
        return $InputObject
    }
}

function Get-ClaudeToastConfig {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    $defaultsPath = Join-Path $scriptRoot "config\defaults.json"
    $userConfigPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\config.json"

    # Load defaults
    if (Test-Path $defaultsPath) {
        $defaults = Get-Content $defaultsPath -Raw | ConvertFrom-Json | ConvertTo-HashtableRecursive
    } else {
        # Fallback: try installed location
        $installedDefaults = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\config\defaults.json"
        if (Test-Path $installedDefaults) {
            $defaults = Get-Content $installedDefaults -Raw | ConvertFrom-Json | ConvertTo-HashtableRecursive
        } else {
            Write-Warning "No defaults.json found. Using hardcoded defaults."
            $defaults = @{ enabled = $true; notifications = @{} }
        }
    }

    # Load user overrides
    if (Test-Path $userConfigPath) {
        $userConfig = Get-Content $userConfigPath -Raw | ConvertFrom-Json | ConvertTo-HashtableRecursive
        $config = Merge-Hashtable -Base $defaults -Override $userConfig
    } else {
        $config = $defaults
    }

    # Resolve icon path
    if (-not $config.ContainsKey("iconPath") -or -not $config["iconPath"]) {
        $config["iconPath"] = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\claude-icon.png"
    } else {
        $config["iconPath"] = [System.Environment]::ExpandEnvironmentVariables($config["iconPath"])
    }

    return $config
}
