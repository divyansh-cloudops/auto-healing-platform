
# Auto-Healing Platform - Docker Monitor with Gmail Alerts

$containerName = "auto-healing-app"
$logFile = Join-Path $PSScriptRoot "recovery.log"
$checkIntervalSeconds = 10

function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp | $Message" | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host "$timestamp | $Message"
}

function Send-EmailAlert {
    param(
        [string]$Subject,
        [string]$Body
    )

    $from = $env:ALERT_EMAIL_FROM
    $to = $env:ALERT_EMAIL_TO
    $appPassword = $env:ALERT_EMAIL_APP_PASSWORD

    if ([string]::IsNullOrWhiteSpace($from) -or
        [string]::IsNullOrWhiteSpace($to) -or
        [string]::IsNullOrWhiteSpace($appPassword)) {
        Write-Log "ERROR: Gmail credentials missing. Email not sent."
        return $false
    }

    $smtp = $null
    $mail = $null

    try {
        $securePassword = ConvertTo-SecureString $appPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential(
            $from, $securePassword
        )

        $smtp = New-Object System.Net.Mail.SmtpClient("smtp.gmail.com", 587)
        $smtp.EnableSsl = $true
        $smtp.UseDefaultCredentials = $false
        $smtp.Credentials = $credential.GetNetworkCredential()
        $smtp.Timeout = 60000

        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = New-Object System.Net.Mail.MailAddress($from)
        $mail.To.Add($to)
        $mail.Subject = $Subject
        $mail.Body = $Body

        $smtp.Send($mail)
        Write-Log "INFO: Email sent: $Subject"
        return $true
    }
    catch {
        Write-Log "ERROR: Email failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($mail) { $mail.Dispose() }
        if ($smtp) { $smtp.Dispose() }
    }
}

Write-Log "Auto-Healing Monitor Started for $containerName"

# Send one startup test email
Send-EmailAlert `
    -Subject "[Auto-Healing] Monitor Started" `
    -Body "The Auto-Healing monitor started at $(Get-Date). Container: $containerName"

while ($true) {
    try {
        $status = docker inspect --format '{{.State.Status}}' $containerName 2>$null
        $inspectExitCode = $LASTEXITCODE

        if ($inspectExitCode -ne 0) {
            Write-Log "ERROR: Container not found or Docker unavailable: $containerName"
        }
        elseif ($status -ne "running") {
            Write-Log "WARNING: Container state is $status. Attempting restart."

            Send-EmailAlert `
                -Subject "[Auto-Healing ALERT] Container stopped" `
                -Body "Container '$containerName' state is '$status' at $(Get-Date). Attempting recovery."

            docker start $containerName
            $startExitCode = $LASTEXITCODE

            if ($startExitCode -eq 0) {
                Write-Log "RECOVERY: Container start command succeeded."

                Send-EmailAlert `
                    -Subject "[Auto-Healing RECOVERY] Container started" `
                    -Body "Container '$containerName' start command succeeded at $(Get-Date)."
            }
            else {
                Write-Log "ERROR: Container start failed."

                Send-EmailAlert `
                    -Subject "[Auto-Healing ERROR] Container start failed" `
                    -Body "Could not start '$containerName' at $(Get-Date). Check Docker and recovery.log."
            }
        }
        else {
            $health = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' $containerName 2>$null

            Write-Log "STATUS: Container=$status; Health=$health"

            if ($health -eq "unhealthy") {
                Write-Log "WARNING: Container is unhealthy. Attempting restart."

                Send-EmailAlert `
                    -Subject "[Auto-Healing ALERT] Container unhealthy" `
                    -Body "Container '$containerName' is unhealthy at $(Get-Date). Attempting recovery."

                docker restart $containerName
                $restartExitCode = $LASTEXITCODE

                if ($restartExitCode -eq 0) {
                    Write-Log "RECOVERY: Container restart command succeeded."

                    Send-EmailAlert `
                        -Subject "[Auto-Healing RECOVERY] Container restarted" `
                        -Body "Container '$containerName' restart command succeeded at $(Get-Date)."
                }
                else {
                    Write-Log "ERROR: Container restart failed."

                    Send-EmailAlert `
                        -Subject "[Auto-Healing ERROR] Container restart failed" `
                        -Body "Could not restart '$containerName' at $(Get-Date). Check Docker and recovery.log."
                }
            }
        }
    }
    catch {
        Write-Log "ERROR: Monitor exception: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $checkIntervalSeconds
}
