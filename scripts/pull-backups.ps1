# Holt die Backups vom Server auf den PC, verschlüsselt sie mit age
# und prüft, ob das Ghost-Backup zu alt ist.
#
#   .\pull-backups.ps1 -Server vps2662496.fastwebserver.de
#   .\pull-backups.ps1 -Server <host> -Dest D:\Backups\homelab -Keep 14
#
# Voraussetzungen:
#   - OpenSSH-Client (ssh/scp) unter Windows
#   - age (winget install FiloSottile.age)
#   - dein Key liegt in %USERPROFILE%\.ssh\id_ed25519 und ist in
#     /home/admin/.ssh/authorized_keys eingetragen
#   - admin hat NOPASSWD-sudo (fuer tar/chown auf dem Server)
#
# Der PC zieht - der Server braucht keinen Zugang zum PC.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$User = "admin",
    [string]$Dest = "D:\Backups\homelab",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
    [int]$Keep = 14,
    [string]$AgeKeyPath = "",
    [string]$NtfyTopic = "",
    [switch]$SkipEncryption
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    if (Test-Path $Dest) { Add-Content -Path (Join-Path $Dest "pull.log") -Value $line }
}

function Notify($msg) {
    if (-not $NtfyTopic) { return }
    try {
        Invoke-RestMethod -Method Post -Uri "https://ntfy.sh/$NtfyTopic" -Body $msg -TimeoutSec 15 | Out-Null
    } catch {
        Log "ntfy fehlgeschlagen: $($_.Exception.Message)"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    if (-not $AgeKeyPath) { $AgeKeyPath = Join-Path $Dest "age.key" }
    if (-not $NtfyTopic) {
        $topicFile = Join-Path $Dest "ntfy.topic"
        if (Test-Path $topicFile) { $NtfyTopic = (Get-Content $topicFile -Raw).Trim() }
    }

    foreach ($cmd in @("ssh", "scp", "tar")) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "$cmd fehlt im PATH" }
    }
    if (-not (Test-Path $KeyPath)) { throw "SSH-Key fehlt: $KeyPath" }

    $remote = "/tmp/homelab-backup-$stamp.tgz"
    $tar = Join-Path $Dest "homelab-$stamp.tgz"
    $sshArgs = @("-i", $KeyPath, "-o", "IdentitiesOnly=yes", "$User@$Server")

    Log "Packe Backups auf $Server ..."
    & ssh @sshArgs "sudo tar czf $remote -C /opt/backups paperless -C /opt/kisium backups && sudo chown ${User}:${User} $remote"
    if ($LASTEXITCODE -ne 0) { throw "tar auf dem Server fehlgeschlagen" }

    Log "Hole Archiv ..."
    & scp -i $KeyPath -o IdentitiesOnly=yes "${User}@${Server}:$remote" $tar
    if ($LASTEXITCODE -ne 0) { throw "scp fehlgeschlagen" }

    & ssh @sshArgs "rm -f $remote" | Out-Null

    $size = (Get-Item $tar).Length
    if ($size -lt 1024) { throw "Archiv zu klein: $size Bytes" }
    Log ("Archiv: {0:N1} MB" -f ($size / 1MB))

    # Ghost-Backup-Alter aus den Dateinamen im Tar pruefen
    $entries = & tar -tzf $tar 2>$null
    $ghost = $entries |
        Where-Object { $_ -match 'ghost-db-(\d{8})-(\d{6})\.sql\.gz$' } |
        ForEach-Object {
            if ($_ -match 'ghost-db-(\d{8})-(\d{6})') {
                [pscustomobject]@{ Stamp = "$($Matches[1])$($Matches[2])"; Name = $_ }
            }
        } |
        Sort-Object Stamp | Select-Object -Last 1

    if (-not $ghost) {
        Notify "Homelab: kein Ghost-Backup im Archiv"
        throw "kein Ghost-Backup im Archiv"
    }

    $ghostDate = [datetime]::ParseExact($ghost.Stamp, "yyyyMMddHHmmss", $null)
    $ageHours = ((Get-Date) - $ghostDate).TotalHours
    Log ("Ghost-Backup: {0} ({1:N1} h alt)" -f $ghost.Name, $ageHours)
    if ($ageHours -gt 26) {
        Notify ("Homelab: Ghost-Backup ist {0:N1} h alt" -f $ageHours)
        throw ("Ghost-Backup zu alt: {0:N1} h" -f $ageHours)
    }

    if ($SkipEncryption) {
        Log "Verschluesselung uebersprungen (-SkipEncryption)"
    } else {
        if (-not (Get-Command age -ErrorAction SilentlyContinue)) {
            throw "age fehlt. Installieren: winget install FiloSottile.age"
        }
        if (-not (Test-Path $AgeKeyPath)) {
            Log "Erzeuge age-Schluessel: $AgeKeyPath"
            & age-keygen -o $AgeKeyPath
            if ($LASTEXITCODE -ne 0) { throw "age-keygen fehlgeschlagen" }
        }
        $recipient = (& age-keygen -y $AgeKeyPath).Trim()
        if (-not $recipient) { throw "age-Public-Key konnte nicht gelesen werden" }
        $enc = "$tar.age"
        & age -r $recipient -o $enc $tar
        if ($LASTEXITCODE -ne 0) { throw "age-Verschluesselung fehlgeschlagen" }
        Remove-Item $tar -Force
        Log "Verschluesselt: $enc"
    }

    # Retention
    Get-ChildItem $Dest -Filter "homelab-*" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Keep |
        ForEach-Object { Log "entferne alt: $($_.Name)"; Remove-Item $_.FullName -Force }

    Log "OK"
} catch {
    Log "FEHLER: $($_.Exception.Message)"
    Notify "Homelab-Backup fehlgeschlagen: $($_.Exception.Message)"
    exit 1
}
