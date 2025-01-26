$branchPattern = [Regex]::new('(?<=ref: refs/heads/)\S+(?=\s+HEAD)')
$shaPattern = [Regex]::new('\b[0-9a-f]{40}\b')

class BranchInfo {
    [string] $SHA
    [string] $Name

    BranchInfo($sha, $name) {
        $this.SHA = $sha
        $this.Name = $name
    }
}

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

function Get-DefaultBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0 )]
        [string]$Url
    )
    $output = git ls-remote --symref $Url HEAD
    [BranchInfo]::new($shaPattern.Match($output).Value, $branchPattern.Match($output).Value)
}

function Get-OutdatedRemotes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0 )]
        $project,

        [Parameter(Mandatory = $true, Position = 1 )]
        $masterBranch
    )

    $project.dst | ? {
        $remoteName = $_.name
        $remoteUrl = $_.url

        Write-Host "`t$remoteName " -ForegroundColor Cyan -NoNewline
        $branchRemote = Get-DefaultBranch $remoteUrl

        if ($branchRemote.SHA -eq $masterBranch.SHA) {
            Write-Host "[OK]" -ForegroundColor Green
        }
        else {
            Write-Host "[MISSMATCH]" -ForegroundColor Red
            Write-Host "Master SHA: $($masterBranch.SHA)" -ForegroundColor Yellow
            Write-Host "Remote SHA: $($branchRemote.SHA)" -ForegroundColor Yellow
            $_
        }
    }


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
    $branch = Get-DefaultBranch $_.url
    # deprecated - SHA validation will be done against the master branch and remotes
    if (![string]::IsNullOrWhiteSpace($sha)) {
        if ($sha -eq $branch.SHA) {
            Write-Host "Validating SHA [OK]"
            return
        }
        else {
            Write-Host "Validating SHA [MISSMATCH]"
            Write-Host "Master SHA: $($branch.SHA)" -ForegroundColor Yellow
            Write-Host "Config SHA: $sha" -ForegroundColor Yellow
        }
    }
    # end deprecated

    Write-Host "Getting outdated remotes" -ForegroundColor Yellow
    $remotes = Get-OutdatedRemotes -Project $_ -MasterBranch $branch
    if (!$remotes) {
        Write-Host "No remotes to update" -ForegroundColor Green
        return
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

        git checkout $branch.Name

        Write-Host "Pulling  . . ." -ForegroundColor Yellow
        git pull origin $branch.Name
    }
    else {
        Write-Host "Repository does not exists" -ForegroundColor Red
        Write-Host "Clonning . . ." -ForegroundColor Yellow
        git clone $_.url $_.name
    }

    Write-Host "Master SHA: $($branch.SHA) [$($branch.Name)]" -ForegroundColor Yellow

    Set-Location $rootDirectoryPath
    Set-Location $repoPath
    Write-Host "Current Location $(Get-CurrentLocation)" -ForegroundColor Gray

    Write-Host "Validating remotes" -ForegroundColor Cyan
    $remotes | % {
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