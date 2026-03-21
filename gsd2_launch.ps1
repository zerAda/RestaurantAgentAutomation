#!/usr/bin/env pwsh
# =============================================================================
# GSD 2 — Master Launch Script (Ralphé v3.3.0)
# Launches 7 Claude Code CLI instances in separate terminals
# Usage: .\gsd2_launch.ps1 [instance_name]
# Examples:
#   .\gsd2_launch.ps1          # Shows menu
#   .\gsd2_launch.ps1 all      # Launches all 7 instances
#   .\gsd2_launch.ps1 n8n      # Launch n8n instance only
#   .\gsd2_launch.ps1 strapi   # Launch Strapi instance only
# =============================================================================

$PROJECT_ROOT = "C:\Users\mon pc\Desktop\ralphé_final_patch\ralphe"
$PLANNING_ROOT = "$PROJECT_ROOT\.planning"

# GSD 2 Instance Definitions
$instances = @{
    "project" = @{
        name     = "GSD2-PROJECT: Full Stack Interconnections"
        dir      = "$PLANNING_ROOT\gsd2_project"
        cwd      = $PROJECT_ROOT
        color    = "Cyan"
        priority = 0
        cmd      = "claude --dangerously-skip-permissions"
    }
    "n8n" = @{
        name     = "GSD2-N8N: Workflow Automation Layer"
        dir      = "$PLANNING_ROOT\gsd2_n8n"
        cwd      = $PROJECT_ROOT
        color    = "Green"
        priority = 1
        cmd      = "claude --dangerously-skip-permissions"
    }
    "strapi" = @{
        name     = "GSD2-STRAPI: CMS & API Layer"
        dir      = "$PLANNING_ROOT\gsd2_strapi"
        cwd      = "$PROJECT_ROOT\inventory-cms"
        color    = "Blue"
        priority = 2
        cmd      = "claude --dangerously-skip-permissions"
    }
    "admin" = @{
        name     = "GSD2-ADMIN: Admin Dashboard"
        dir      = "$PLANNING_ROOT\gsd2_admin"
        cwd      = "$PROJECT_ROOT\admin-dashboard"
        color    = "Magenta"
        priority = 3
        cmd      = "claude --dangerously-skip-permissions"
    }
    "kiosk" = @{
        name     = "GSD2-KIOSK: Kiosk Application"
        dir      = "$PLANNING_ROOT\gsd2_kiosk"
        cwd      = "$PROJECT_ROOT\kiosk-app"
        color    = "Yellow"
        priority = 4
        cmd      = "claude --dangerously-skip-permissions"
    }
    "infra" = @{
        name     = "GSD2-INFRA-SEC: Infrastructure & Security"
        dir      = "$PLANNING_ROOT\gsd2_infra_security"
        cwd      = $PROJECT_ROOT
        color    = "Red"
        priority = 5
        cmd      = "claude --dangerously-skip-permissions"
    }
    "llm" = @{
        name     = "GSD2-LLM: AI/LLM Optimization"
        dir      = "$PLANNING_ROOT\gsd2_llm"
        cwd      = $PROJECT_ROOT
        color    = "DarkCyan"
        priority = 6
        cmd      = "claude --dangerously-skip-permissions"
    }
}

function Show-Menu {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          GSD 2 — RALPHÉ v3.3.0 MULTI-AGENT SYSTEM          ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  [0] project  → Full Stack Interconnections                 ║" -ForegroundColor White
    Write-Host "║  [1] n8n      → Workflow Automation (92 workflows)          ║" -ForegroundColor Green
    Write-Host "║  [2] strapi   → Strapi CMS & API Layer                      ║" -ForegroundColor Blue
    Write-Host "║  [3] admin    → Admin Dashboard (React/Vite)                ║" -ForegroundColor Magenta
    Write-Host "║  [4] kiosk    → Kiosk Application (React/Vite)              ║" -ForegroundColor Yellow
    Write-Host "║  [5] infra    → Infrastructure & Security (DevSecOps)       ║" -ForegroundColor Red
    Write-Host "║  [6] llm      → LLM/AI Optimization (Ollama + Whisper)     ║" -ForegroundColor DarkCyan
    Write-Host "║  [all]        → Launch ALL 7 instances simultaneously       ║" -ForegroundColor White
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\gsd2_launch.ps1 [n8n|strapi|admin|kiosk|project|infra|llm|all]" -ForegroundColor Gray
    Write-Host ""
}

function Launch-Instance {
    param($key)
    
    $inst = $instances[$key]
    if (-not $inst) {
        Write-Host "Unknown instance: $key" -ForegroundColor Red
        return
    }

    Write-Host "▶ Launching: $($inst.name)" -ForegroundColor $inst.color
    
    # Ensure output directory exists
    New-Item -ItemType Directory -Force -Path $inst.dir | Out-Null
    
    # Build the claude command with context file
    # Claude Code reads CLAUDE.md from the working directory automatically
    # We copy the instance CLAUDE.md to the cwd if different from dir
    $claudeMdSource = "$($inst.dir)\CLAUDE.md"
    $claudeMdTarget = "$($inst.cwd)\CLAUDE.md"
    
    # Build the launch command
    # Opens a new PowerShell window for each instance
    $launchScript = @"
Set-Location '$($inst.cwd)'
Write-Host '═══════════════════════════════════════════' -ForegroundColor Cyan
Write-Host '  $($inst.name)' -ForegroundColor Cyan
Write-Host '  Working dir: $($inst.cwd)' -ForegroundColor Gray
Write-Host '  Context:     $claudeMdSource' -ForegroundColor Gray
Write-Host '═══════════════════════════════════════════' -ForegroundColor Cyan
Write-Host ''

# Create output directory for this instance
New-Item -ItemType Directory -Force -Path '$($inst.dir)' | Out-Null

# Launch claude with the instance-specific context
# Pass the CLAUDE.md path as context via --context flag or by copying it
$($inst.cmd) --context '$claudeMdSource' 2>&1
if (`$LASTEXITCODE -ne 0) {
    # Fallback: copy CLAUDE.md to cwd and run without --context flag
    Copy-Item '$claudeMdSource' '.\.gsd2_context.md' -Force
    Write-Host 'Note: Using .gsd2_context.md as context' -ForegroundColor Yellow
    claude --dangerously-skip-permissions
}
"@

    Start-Process powershell -ArgumentList @(
        "-NoExit",
        "-Command",
        $launchScript
    ) -WindowStyle Normal
    
    Write-Host "  ✓ Terminal launched for: $($inst.name)" -ForegroundColor $inst.color
    Start-Sleep -Milliseconds 500
}

function Launch-InstanceWithContext {
    param($key)
    
    $inst = $instances[$key]
    if (-not $inst) {
        Write-Host "Unknown instance: $key" -ForegroundColor Red
        return
    }

    Write-Host "▶ Launching: $($inst.name)" -ForegroundColor $inst.color
    
    # Ensure output directory exists
    New-Item -ItemType Directory -Force -Path $inst.dir | Out-Null
    
    $claudeMdSource = "$($inst.dir)\CLAUDE.md"
    $instName = $inst.name
    $instCwd  = $inst.cwd
    $instColor = $inst.color
    
    # The most reliable approach: cd to the instance dir (which has CLAUDE.md)
    # and set the project root via CLAUDE_PROJECT_DIR env var  
    $launchCmd = "Set-Location '$instCwd'; `$env:GSD2_INSTANCE='$key'; claude --dangerously-skip-permissions"
    
    Start-Process powershell -ArgumentList @(
        "-NoExit",
        "-Command",
        "Set-Location '$instCwd'; Write-Host '── GSD2: $key ──' -ForegroundColor $instColor; claude --dangerously-skip-permissions"
    ) -WindowStyle Normal
    
    Write-Host "  ✓ Launched: $key → $instCwd" -ForegroundColor $inst.color
    Start-Sleep -Milliseconds 800
}

# ─── Main Entry Point ─────────────────────────────────────────────────────────

$target = $args[0]

if (-not $target) {
    Show-Menu
    exit 0
}

if ($target -eq "all") {
    Write-Host ""
    Write-Host "🚀 Launching ALL 7 GSD 2 instances..." -ForegroundColor Cyan
    Write-Host ""
    
    # Launch in priority order with small delays
    foreach ($key in @("project", "n8n", "strapi", "admin", "kiosk", "infra", "llm")) {
        Launch-InstanceWithContext -key $key
        Start-Sleep -Milliseconds 1000
    }
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  ✅ All 7 GSD 2 instances launched!                         ║" -ForegroundColor Green
    Write-Host "║  Each instance has its own terminal window.                 ║" -ForegroundColor Green
    Write-Host "║  Run 'make integrity' in each terminal to start Phase A.    ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
} else {
    if ($instances.ContainsKey($target)) {
        Launch-InstanceWithContext -key $target
    } else {
        Write-Host "Unknown instance: '$target'" -ForegroundColor Red
        Show-Menu
    }
}
