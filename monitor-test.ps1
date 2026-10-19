
$containerName = "auto-healing-app-test"

Write-Host "Auto-Healing Monitor Started..."

while ($true) {
    $status = docker inspect --format '{{.State.Status}}' $containerName 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Container not found. Waiting..."
    }
    elseif ($status -ne "running") {
        Write-Host "Container is $status. Restarting..."
        docker start $containerName
    }
    else {
        $health = docker inspect --format '{{.State.Health.Status}}' $containerName 2>$null

        if ($health -eq "unhealthy") {
            Write-Host "Container unhealthy! Recovering..."
            docker restart $containerName
        }
        else {
            Write-Host "Container status: $status | Health: $health"
        }
    }

    Start-Sleep -Seconds 10
}
