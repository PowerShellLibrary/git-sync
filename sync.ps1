function Get-CurrentLocation {
    [CmdletBinding()]
    param ()

    begin {
    }

    process {
        (Get-Item .).FullName
    }

    end {
    }
}

function Get-MasterSHA {
    param (
        $url
    )
    git ls-remote -h $url | ? { $_.Contains("refs/heads/master") } | % { $_.Substring(0, 40) } | Select-Object -First 1
}

Clear-Host
$configuration = Get-Content -Raw -Path .\config.json | ConvertFrom-Json
$rootDirectoryPath = Get-CurrentLocation
$rootDirectoryPath = Join-Path $rootDirectoryPath "repo"
if (!(Test-Path $rootDirectoryPath)) {
    mkdir $rootDirectoryPath
}

$configuration.projects | % {
    Set-Location $rootDirectoryPath
    Write-Host ""
    Write-Host "Processing: '$($_.name)'" -ForegroundColor Red

    $sha = $_.sha
    if (![string]::IsNullOrWhiteSpace($sha)) {
        $shaMaster = Get-MasterSHA $_.url
        if ($sha -eq $shaMaster) {
            Write-Host "Validating SHA [OK]"
            return
        }
        else {
            Write-Host "Validating SHA [MISSMATCH]"
            Write-Host "Master SHA: $shaMaster" -ForegroundColor Yellow
            Write-Host "Config SHA: $sha" -ForegroundColor Yellow
        }
    }

    $repoPath = Join-Path $rootDirectoryPath $_.name
    if (Test-Path $repoPath) {
        Write-Host "Repository folder exists" -ForegroundColor Green

        Set-Location $rootDirectoryPath
        Set-Location $repoPath
        Write-Host "Current Location $(Get-CurrentLocation)" -ForegroundColor Gray

        Write-Host "Reseting status. . ." -ForegroundColor Yellow
        git reset --hard | Out-Null
        git clean -f -d | Out-Null

        Write-Host "Fetching . . ." -ForegroundColor Yellow
        git fetch --tags

        Write-Host "Pulling . . ." -ForegroundColor Yellow
        git pull origin master
    }
    else {
        Write-Host "Repository does not exists" -ForegroundColor Red
        Write-Host "Clonning . . ." -ForegroundColor Yellow
        git clone $_.url
    }

    $shaMaster = Get-MasterSHA $_.url
    Write-Host "Master SHA: $shaMaster" -ForegroundColor Yellow

    Set-Location $rootDirectoryPath
    Set-Location $repoPath
    Write-Host "Current Location $(Get-CurrentLocation)" -ForegroundColor Gray

    Write-Host "Validating remotes" -ForegroundColor Cyan
    $_.dst | % {
        $remoteName = $_.name
        $remoteUrl = $_.url
        Write-Host "`t$remoteName" -ForegroundColor Cyan -NoNewline

        $remotes = git remote
        $remote = $remotes | ? { $_ -eq $remoteName } | Select-Object -First 1
        if ($remote) {
            Write-Host "[OK]" -ForegroundColor Green
        }
        else {
            Write-Host "[MISSING]" -ForegroundColor Red
            Write-Host "Adding remote" -ForegroundColor Yellow
            git remote add $remoteName $remoteUrl
        }

        Write-Host "Pushing to backup . . ." -ForegroundColor Green
        git push -u $remoteName --all --force
    }
}
Set-Location $rootDirectoryPath
Set-Location ..