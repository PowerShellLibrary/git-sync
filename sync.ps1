$branchPattern = [Regex]::new('(?<=ref: refs/heads/)\S+(?=\s+HEAD)')
$script:SyncFailures = [System.Collections.Generic.List[string]]::new()

class BranchInfo {
    [string] $SHA
    [string] $Name
    [bool] $IsEmpty

    BranchInfo() {
        $this.IsEmpty = $true
    }

    BranchInfo($sha, $name) {
        $this.SHA = $sha
        $this.Name = $name
        $this.IsEmpty = $false
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

function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Context,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$SilentOutput
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $details = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if (!$SilentOutput -and $output.Count -gt 0) {
        $output | ForEach-Object { Write-Host $_ }
    }

    if ($exitCode -ne 0) {
        $failure = "Git failed while $Context (exit code $exitCode): git $($Arguments -join ' ')"
        Write-Host $failure -ForegroundColor Red
        if ($details -match '(?i)host key verification failed|remote host identification has changed') {
            Write-Host "SSH host-key verification failed. Check that the pipeline trusts the correct host key for this remote." -ForegroundColor Red
        }
        if (![string]::IsNullOrWhiteSpace($details)) {
            Write-Host $details -ForegroundColor Yellow
        }
        $script:SyncFailures.Add($failure)
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}

function Get-DefaultBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0 )]
        [string]$Url,

        [string]$Context = 'querying the repository default branch'
    )
    $result = Invoke-Git -Context $Context -Arguments @('ls-remote', '--symref', $Url, 'HEAD') -SilentOutput
    if ($result.ExitCode -ne 0) {
        return
    }

    $output = $result.Output -join [Environment]::NewLine
    $branchMatch = $branchPattern.Match($output)
    $headShaMatch = [Regex]::Match($output, '(?m)^([0-9a-f]{40})\s+HEAD\s*$')
    if ($branchMatch.Success -and $headShaMatch.Success) {
        [BranchInfo]::new($headShaMatch.Groups[1].Value, $branchMatch.Value)
    }
    else {
        [BranchInfo]::new()
    }
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
        $branchRemote = Get-DefaultBranch -Url $remoteUrl -Context "checking remote '$remoteName' for project '$($project.name)'"

        if ($null -eq $branchRemote) {
            Write-Host "[UNAVAILABLE]" -ForegroundColor Red
            return
        }

        if ($branchRemote.IsEmpty) {
            Write-Host "[EMPTY]" -ForegroundColor Yellow
            Write-Host "Remote has no default branch; it will be initialized from the source." -ForegroundColor Yellow
            $_
            return
        }

        if ($branchRemote) {
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
    $branch = Get-DefaultBranch -Url $_.url -Context "checking source for project '$($_.name)'"
    if ($null -eq $branch -or $branch.IsEmpty) {
        Write-Host "Could not read the source default branch; skipping this project." -ForegroundColor Red
        return
    }
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
        $result = Invoke-Git -Context "resetting project '$($_.name)'" -Arguments @('reset', '--hard') -SilentOutput
        if ($result.ExitCode -ne 0) { return }
        $result = Invoke-Git -Context "cleaning project '$($_.name)'" -Arguments @('clean', '-f', '-d') -SilentOutput
        if ($result.ExitCode -ne 0) { return }

        Write-Host "Fetching . . ." -ForegroundColor Yellow
        $result = Invoke-Git -Context "fetching project '$($_.name)'" -Arguments @('fetch', '--tags')
        if ($result.ExitCode -ne 0) { return }

        $result = Invoke-Git -Context "checking out '$($branch.Name)' for project '$($_.name)'" -Arguments @('checkout', $branch.Name)
        if ($result.ExitCode -ne 0) { return }

        Write-Host "Pulling  . . ." -ForegroundColor Yellow
        $result = Invoke-Git -Context "pulling project '$($_.name)'" -Arguments @('pull', 'origin', $branch.Name)
        if ($result.ExitCode -ne 0) { return }
    }
    else {
        Write-Host "Repository does not exists" -ForegroundColor Red
        Write-Host "Clonning . . ." -ForegroundColor Yellow
        $result = Invoke-Git -Context "cloning project '$($_.name)'" -Arguments @('clone', $_.url, $_.name)
        if ($result.ExitCode -ne 0) { return }
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

        $remoteList = Invoke-Git -Context "listing remotes for project '$($_.name)'" -Arguments @('remote') -SilentOutput
        if ($remoteList.ExitCode -ne 0) { return }
        $remote = $remoteList.Output | ? { $_ -eq $remoteName } | Select-Object -First 1
        if ($remote) {
            Write-Host "[OK]" -ForegroundColor Green
        }
        else {
            Write-Host "[MISSING]" -ForegroundColor Red
            Write-Host "Adding remote" -ForegroundColor Yellow
            $result = Invoke-Git -Context "adding remote '$remoteName' for project '$($_.name)'" -Arguments @('remote', 'add', $remoteName, $remoteUrl)
            if ($result.ExitCode -ne 0) { return }
        }

        Write-Host "Pushing to backup . . ." -ForegroundColor Green
        $null = Invoke-Git -Context "pushing project '$($_.name)' to remote '$remoteName'" -Arguments @('push', '-u', $remoteName, '--all', '--force')
    }
}
Set-Location $rootDirectoryPath
Set-Location ..

if ($script:SyncFailures.Count -gt 0) {
    Write-Host "Synchronization completed with $($script:SyncFailures.Count) failed Git operation(s):" -ForegroundColor Red
    $script:SyncFailures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    throw "Repository synchronization failed with $($script:SyncFailures.Count) Git operation(s)."
}