#!/usr/bin/env pwsh
<#
Create a SealedSecret for Alertmanager SMTP and commit it to the repo.

This script prompts you for the SMTP password securely, creates a temporary
Kubernetes Secret YAML, fetches the SealedSecrets controller public cert,
creates a SealedSecret, commits it to `argocd/apps/monitoring/alertmanager-smtp-sealedsecret.yaml`
and removes temporary files.

Requirements:
- `kubectl` in PATH and configured to target your cluster
- `kubeseal` in PATH
- `git` configured for the repo

Run locally (do NOT paste your password into chat):
  pwsh .\scripts\create_sealedsecret.ps1
#>

Set-StrictMode -Version Latest

function Check-Cmd($cmd) {
    $null = Get-Command $cmd -ErrorAction SilentlyContinue
    return $?
}

if (-not (Check-Cmd kubectl)) {
    Write-Error "kubectl not found in PATH. Install and configure kubectl first."; exit 1
}
if (-not (Check-Cmd kubeseal)) {
    Write-Error "kubeseal not found in PATH. Install kubeseal from https://github.com/bitnami-labs/sealed-secrets"; exit 1
}

$ns = 'monitoring'
$outDir = 'argocd/apps/monitoring'
$secretYaml = Join-Path $PSScriptRoot 'secret.yaml'
$pubCert = Join-Path $PSScriptRoot 'pub-cert.pem'
$sealedFile = Join-Path (Resolve-Path $outDir) 'alertmanager-smtp-sealedsecret.yaml'

Write-Host 'Creating SealedSecret for Alertmanager SMTP (input hidden)'

$secure = Read-Host 'Enter SMTP password' -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

# Create temporary secret YAML using kubectl; pass from-literal as single argument
$fromLiteral = "--from-literal=smtp_password=$plain"
& kubectl create secret generic alertmanager-smtp-secret $fromLiteral --namespace $ns --dry-run=client -o yaml | Out-File -Encoding utf8 $secretYaml
if ($LASTEXITCODE -ne 0) { Write-Error 'kubectl create secret failed'; exit 1 }

Write-Host 'Fetching SealedSecrets controller public cert...'
& kubeseal --controller-namespace kube-system --fetch-cert | Out-File -Encoding ascii $pubCert
if (-not (Test-Path $pubCert)) { Write-Error 'Failed to fetch controller cert'; Remove-Item -Force $secretYaml -ErrorAction SilentlyContinue; exit 1 }

Write-Host 'Sealing secret...'
Get-Content $secretYaml -Raw | & kubeseal --cert $pubCert -o yaml | Out-File -Encoding utf8 $sealedFile
if (-not (Test-Path $sealedFile)) { Write-Error 'Failed to create SealedSecret'; Remove-Item -Force $secretYaml,$pubCert -ErrorAction SilentlyContinue; exit 1 }

Write-Host "SealedSecret written to: $sealedFile"

if (Check-Cmd git) {
    Write-Host 'Staging and committing sealed secret to git (you may be prompted for credentials)'
    & git add $sealedFile
    & git commit -m "chore(monitoring): add SealedSecret for alertmanager SMTP" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host 'No commit made (maybe nothing to commit)'} else { Write-Host 'Committed sealed secret' }
    & git push origin main
    if ($LASTEXITCODE -ne 0) { Write-Host 'Push failed or skipped; please push manually if needed.' } else { Write-Host 'Pushed sealed secret to origin/main' }
} else {
    Write-Host 'git not found; sealed secret created but not committed.'
}

Write-Host 'Cleaning temporary files...'
Remove-Item -Force $secretYaml,$pubCert -ErrorAction SilentlyContinue

Write-Host 'Done. ArgoCD should pick up the SealedSecret and create the Secret in the cluster.'
