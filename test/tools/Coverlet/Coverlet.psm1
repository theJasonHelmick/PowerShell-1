# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
$script:psRepoPath = [string]::Empty
if ($null -ne (Get-Command -Name 'git' -ErrorAction Ignore)) {
    $script:psRepoPath = git rev-parse --show-toplevel
}
$script:PathSeparator = [io.path]::PathSeparator


function Invoke-Coverlet {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [parameter()]$OutputLog = "$home/Documents/Coverage.json",
        [parameter()]$TestPath = "${script:psRepoPath}/test/powershell",
        [parameter()]$BaseDirectory = "${script:psRepoPath}",
        [parameter()]$CoverletPath = "$HOME/Coverlet.Console/coverlet.console",
        [parameter()]$PowerShellExePath = "$(psoutput)",
        [parameter()]$PesterLogElevated = "$HOME/Documents/TestResultsElevated.xml",
        [parameter()]$PesterLogUnelevated = "$HOME/Documents/TestResultsUnelevated.xml",
        [parameter()]$PesterLogFormat = "NUnitXml",
        [parameter()]$TestToolsModulesPath = "${script:psRepoPath}/test/tools/Modules",
        [switch]$SuppressQuiet
    )

    $elevationMessage = $null
    if ( ! (Test-Elevation -message ([ref]$elevationMessage))) {
        throw $elevationMessage
    }

    $message = $null
    # check the various arguments
    $neededPaths = $CoverletPath, $PowerShellExePath, $BaseDirectory, $TestPath
    if ( -not (Test-FilePath -neededPath $neededPaths -message ([ref]$message))) {
        throw $message
    }

    # create the path variable for our run
    $newPath = Get-TestEnvPath -BaseDirectory $BaseDirectory

    # on Windows we set execution policy, this is not supported on other platforms
    if ( $IsWindows ) {
        $ExecPolicy = "Set-ExecutionPolicy Bypass -Force -Scope Process;"
    }
    else {
        $ExecPolicy = ""
    }

    # PSModulePath
    $PSModulePathElements  = @(Join-Path (split-path "${PowerShellExePath}") "Modules")
    $PSModulePathElements += "${TestToolsModulesPath}"
    $newPSModulePath = $PSModulePathElements -join $script:PathSeparator

    # Pester Setup
    [array]$pesterArgs = "-Path","${TestPath}"
    if ( $IsWindows ) {
        $Tag = "RequireAdminOnWindows"
    }
    else {
        $Tag = "RequireSudoOnUnix"
    }


    # Common test args
    $targetArgScript = (
        "$ExecPolicy",
        ('Set-Item env:PATH "{0}"' -f $newPath),
        ('Set-Item env:PSModulePath "{0}"' -f $newPSModulePath)
        )

    # Coverlet script for elevated execution
    $CoverletCommand = "${CoverletPath} ${PowerShellExePath} --target ${PowerShellExePath}"
    # ELEVATED TESTS ARE RUN FIRST
    $pesterArgsElevated = .{ $pesterArgs; "-Tag @('$Tag')";"-OutputFile ${PesterLogElevated}" }
    $testArgs = @{
        Coverlet = ${CoverletCommand}
        TargetScript = ${targetArgScript}
        Elevated = $true
        PesterCommand = "Invoke-Pester " + ($pesterArgsElevated -join " ")
        PowerShellExePath = $PowerShellExePath
        Merge = $false
        }
    foreach ( $parm in "WhatIf","Confirm","Verbose","Inquire" ) {
        if ( $PSBoundParameters[$parm] ) {
            $testArgs[$parm] = $true
        }
    }
    Invoke-CoverageTest @testArgs

    # Coverlet script for unelevated execution, which merges the previous results
    $CoverletCommand = "${CoverletPath} ${PowerShellExePath} --target ${PowerShellExePath}"
    # UNELEVATED TESTS
    $pesterArgsUnelevated = .{ $pesterArgs; "-excludeTag @('$Tag')"; "-OutputFile ${PesterLogUnelevated}"}
    $testArgs = @{
        Coverlet = ${CoverletCommand}
        TargetScript = ${targetArgScript}
        Elevated = $false
        PesterCommand = "Invoke-Pester " + ($pesterArgsUnelevated -join " ")
        PowerShellExePath = $PowerShellExePath
        Merge = $true
        }
    foreach ( $parm in "WhatIf","Confirm","Verbose","Inquire" ) {
        if ( $PSBoundParameters[$parm] ) {
            $testArgs[$parm] = $true
        }
    }
    Invoke-CoverageTest @testArgs

}

function Invoke-CoverageTest {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [string]$PowerShellExePath,
        [switch]$Elevated,
        [string]$Coverlet,
        [string[]]$TargetScript,
        [string]$PesterCommand,
        [switch]$Merge
    )

    $tempPath = [io.path]::GetTempPath()

    $elevatedWorkerScriptPath   = Join-Path $tempPath "CoverletWorkerElevated.ps1"
    $elevatedDriverScriptPath   = Join-Path $tempPath "CoverletDriverElevated.ps1"
    $elevatedCoverletResultPath = Join-Path $tempPath "Coverage.Elevated.json"
    $unelevatedWorkerScriptPath   = Join-Path $tempPath "CoverletWorkerUnelevated.ps1"
    $unelevatedDriverScriptPath   = Join-Path $tempPath "CoverletDriverUnelevated.ps1"
    $unelevatedCoverletResultPath = Join-Path $tempPath "Coverage.Unelevated.json"

    if ( $Elevated ) {
        $workerScriptPath = $elevatedWorkerScriptPath
        $driverScriptPath = $elevatedDriverScriptPath
        $coverletResultPath = $elevatedCoverletResultPath
    }
    else {
        $workerScriptPath = $unelevatedWorkerScriptPath
        $driverScriptPath = $unelevatedDriverScriptPath
        $coverletResultPath = $unelevatedCoverletResultPath
    }

    # how we will run the driver script
    $runner = Get-ElevatorExe -Elevated:$Elevated
    # construct the driver script
    $powershellExe = $PowerShellExePath
    if ( $IsWindows ) {
        $powershellExe = "PowerShell"
    }
    if ( $runner -match "runas" ) {
        "Set-Location $(Split-Path $PowerShellExePath)",
        "$runner ""${PowerShellExe} -c $workerScriptPath""" | out-file -encoding ascii $driverScriptPath
    }
    else {
        "Set-Location $(Split-Path $PowerShellExePath)",
        "$runner ${powerShellExe} -c $workerScriptPath" | out-file -encoding ascii $driverScriptPath

    }

    # construct the coverlet scipt
    [string[]]$commandElements = $TargetScript
    $commandElements += $PesterCommand
    $encodedCommand = Convert-ScriptToBase64 ($commandElements -join ";")

    $output = "--output $coverletResultPath"
    if ( $merge ) {
        if ( $elevated ) {
            $output = "--merge-with $unelevatedCoverletResultPath --output $coverletResultPath"
        }
        else {
            $output = "--merge-with $elevatedCoverletResultPath --output $coverletResultPath"
        }
    }

    "$Coverlet ${output} --targetargs ""-EncodedCommand $encodedCommand""" |
        out-file -encoding Ascii $workerScriptPath

    # Actually invoke the script
    if ( $PSCmdlet.ShouldProcess("$workerScriptPath $driverScriptPath")) {
        & $driverScriptPath
    }
}

# utility to convert the command to a base64 encoded string
function Convert-ScriptToBase64 {
    param ( [string]$script )
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    $base64targetArgs = [convert]::ToBase64String($bytes)
    return $base64targetArgs
}

# a handy tool to extract the encoded command from the created script file
function Get-EncodedCommand {
    param ( $file )
    $d = Get-Content -Raw -Read 0 $file
    $s = $d -replace ".*-EncodedCommand " -replace '".*'
    $bytes = [convert]::FromBase64String($s)
    $script = [text.Encoding]::Unicode.GetString($bytes)
    return $script
}

# get the test binary paths from the 3 test binaries
function Get-TestEnvPath {
    param ( $BaseDirectory )
    # fix up path
    $PathElements  = $env:PATH -split $script:PathSeparator
    foreach ( $exe in "TestExe","TestService","WebListener" ) {
        $toolPath = Join-Path $BaseDirectory "test/tools/${exe}/bin"
        if ( Test-Path $toolPath ) {
            $PathElements += $toolPath
        }
        else {
            throw "Could not find '$toolPath'"
        }
    }
    $newPath = ${PathElements} -join $script:PathSeparator
    return $newPath
}

# get the proper utility which manages elevation
# on Windows, we actually reduce elevation, on Linux/MacOS we use sudo
function Get-ElevatorExe {
    param ( [switch]$Elevated )
    $elevator = ""
    if ( $IsWindows ) {
        if ( ! $Elevated ) {
            $elevator = "runas /trustleve:0x20000"
        }
    }
    else {
        if ( $Elevated ) {
            $elevator = "sudo"
        }
    }
    return $elevator
}

# on Windows we need to run as an elevated user, on Linux/MacOS we run
# as a regular user
function Test-Elevation {
    param ([ref]$message)
    # check for elevation
    $IsElevated = $false
    if ( $IsWindows ) {
        $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        $isElevated = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    elseif ( (id -u) -eq 0 ) {
            $IsElevated = $true
    }
    if ( -not $IsElevated -and $IsWindows ) {
        $message.Value = "Please run from an elevated PowerShell (Windows user must be elevated)"
    }
    elseif ( $IsElevated -and -not $IsWindows ){
        $message.Value = "Please run from an non-elevated PowerShell (Linux/MacOS user must not be elevated)"
    }
    else {
        $message.Value = "Elevation is proper for the platform"
        $IsElevated = $true
    }
    return $IsElevated
}

function Test-FilePath {
    param ([string[]]$NeededPath, [ref]$message)
    foreach ($path in $NeededPath) {
        if ( -not (Test-Path $path)) {
            $message.value = "'$path' not found"
            return $false
        }
    }
    return $true
}

Export-ModuleMember -Function Invoke-Coverlet,Get-EncodedCommand