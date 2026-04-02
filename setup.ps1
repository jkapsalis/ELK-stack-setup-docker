# setup.ps1
# ──────────────────────────────────────────────────────────────────
# Run ONCE after the stack is up to set the kibana_system password.
# Usage:  .\setup.ps1
# ──────────────────────────────────────────────────────────────────

# ── Load .env if present ──────────────────────────────────────────
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $name  = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

# ── Defaults ──────────────────────────────────────────────────────
$elasticPassword = if ($env:ELASTIC_PASSWORD) { $env:ELASTIC_PASSWORD } else { "changeme" }
$kibanaPassword  = if ($env:KIBANA_PASSWORD)  { $env:KIBANA_PASSWORD  } else { "changeme" }
$esUrl           = "http://localhost:9200"

# ── Wait for Elasticsearch ────────────────────────────────────────
Write-Host "⏳  Waiting for Elasticsearch to be ready ..." -ForegroundColor Cyan

$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("elastic:$elasticPassword")
    )
}

$ready = $false
$attempts = 0
while (-not $ready -and $attempts -lt 30) {
    try {
        $response = Invoke-RestMethod `
            -Uri "$esUrl/_cluster/health" `
            -Headers $headers `
            -ErrorAction Stop
        if ($response.status -in @("green", "yellow")) {
            $ready = $true
        }
    } catch {
        $attempts++
        Write-Host "   ... still waiting (attempt $attempts/30)" -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}

if (-not $ready) {
    Write-Host "  Elasticsearch did not become ready in time. Check: docker compose logs elasticsearch" -ForegroundColor Red
    exit 1
}
Write-Host " Elasticsearch is up." -ForegroundColor Green

# ── Set kibana_system password ────────────────────────────────────
Write-Host "  Setting kibana_system password ..." -ForegroundColor Cyan

$body = @{ password = $kibanaPassword } | ConvertTo-Json

try {
    Invoke-RestMethod `
        -Method POST `
        -Uri "$esUrl/_security/user/kibana_system/_password" `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body `
        -ErrorAction Stop | Out-Null
    Write-Host "kibana_system password set." -ForegroundColor Green
} catch {
    Write-Host " Failed to set kibana_system password: $_" -ForegroundColor Red
    exit 1
}

# ── Done ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host " ELK Stack is ready!" -ForegroundColor Green
Write-Host " Kibana  → http://localhost:5601" -ForegroundColor White
Write-Host " Elastic → http://localhost:9200" -ForegroundColor White
Write-Host " Login   → elastic / $elasticPassword" -ForegroundColor White
Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan
