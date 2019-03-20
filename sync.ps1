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

Clear-Host
$configuration = Get-Content -Raw -Path .\config.json | ConvertFrom-Json
$rootDirectoryPath = Get-CurrentLocation
$rootDirectoryPath = Join-Path $rootDirectoryPath "repo"
if(!(Test-Path $rootDirectoryPath)){
    mkdir $rootDirectoryPath
}

$configuration.projects | % {
    Set-Location $rootDirectoryPath
    Write-Host ""
    Write-Host "Processing: '$($_.name)'" -ForegroundColor Red

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