# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
$script:psRepoPath = [string]::Empty
if ($null -ne (Get-Command -Name 'git' -ErrorAction Ignore)) {
    $script:psRepoPath = git rev-parse --show-toplevel
}
$script:PathSeparator = [io.path]::PathSeparator

function Get-TestEnvPath
{
    param ( $BaseDirectory )
    # fix up path
    $PathElements  = $env:PATH -split ([io.path]::PathSeparator)
    $PathElements += (Join-Path $BaseDirectory "test/tools/TestExe/bin")
    $PathElements += (Join-Path $BaseDirectory "test/tools/TestService/bin")
    $PathElements += (Join-Path $BaseDirectory "test/tools/WebListener/bin")
    $newPath = ${PathElements} -join ([io.path]::PathSeparator)
    return $newPath
}

function Get-ElevatorExe
{
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

function Test-Elevation
{
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
        $message.Value = "Please run from an elevated PowerShell"
    }
    elseif ( $IsElevated -and -not $IsWindows ){
        $message.Value = "Please run from an non-elevated PowerShell"
    }
    else {
        $message.Value = "Elevation is proper for the platform"
        $IsElevated = $true
    }
    return $IsElevated
}

function Test-Arguments
{
    param ([string[]]$NeededPath, [ref]$message)
    foreach ($path in $NeededPath) {
        if ( -not (Test-Path $path)) {
            $message.value = "'$path' not found"
            return $false
        }
    }
    return $true
}
    
function Invoke-Coverlet
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [parameter()]$OutputLog = "$home/Documents/Coverage.json",
        [parameter()]$TestPath = "${script:psRepoPath}/test/powershell",
        [parameter()]$BaseDirectory = "${script:psRepoPath}",
        [parameter()]$CoverletPath = "$home/Coverlet.Console/coverlet.console",
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
    $neededPaths = $CoverletPath, $PowerShellExePath, $BaseDirectory, $TestPath 
    if ( -not (Test-Arguments -neededPath $neededPaths -message ([ref]$message))) {
        throw $message
    }

    $newPath = Get-TestEnvPath -BaseDirectory $BaseDirectory

    if ( $IsWindows ) {
        $ExecPolicy = "Set-ExecutionPolicy Bypass -Force -Scope Process;"
    }
    else {
        $ExecPolicy = ""
    }

    # PSModulePath
    $PSModulePathElements  = @(Join-Path (split-path "${PowerShellExePath}") "Modules")
    $PSModulePathElements += "${TestToolsModulesPath}"
    $newPSModulePath = $PSModulePathElements -join ([io.path]::PathSeparator)

    # Pester Setup
    [array]$pesterArgs = "-Path","${TestPath}"
    if ( $IsWindows ) {
        $Tag = "RequireAdminOnWindows"
    }
    else {
        $Tag = "RequireSudoOnUnix"
    }

    # Common Coverlet script
    $CoverletCommand = "${CoverletPath} ${PowerShellExePath} --target ${PowerShellExePath}"

    # Common test args
    $targetArgScript = (
        "$ExecPolicy",
        ('Set-Item env:PATH "{0}"' -f $newPath),
        ('Set-Item env:PSModulePath "{0}"' -f $newPSModulePath)
        )

    # ELEVATED TESTS
    $pesterArgsElevated = .{ $pesterArgs; "-Tag @('$Tag')";"-OutputFile ${PesterLogElevated}" }
    $testArgs = @{
        Coverlet = ${CoverletCommand}
        TargetScript = ${targetArgScript}
        Elevated = $true
        PesterCommand = "Invoke-Pester " + ($pesterArgsElevated -join " ")
        PowerShellExePath = $PowerShellExePath
        }
    Invoke-CoverageTest @testArgs

    # UNELEVATED TESTS
    $pesterArgsUnelevated = .{ $pesterArgs; "-excludeTag @('$Tag')"; "-OutputFile ${PesterLogUnelevated}"}
    $testArgs = @{
        Coverlet = ${CoverletCommand}
        TargetScript = ${targetArgScript}
        Elevated = $false
        PesterCommand = "Invoke-Pester " + ($pesterArgsUnelevated -join " ")
        PowerShellExePath = $PowerShellExePath
        }
    Invoke-CoverageTest @testArgs

}

function Convert-ScriptToBase64
{
    param ( [string]$script )
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    $base64targetArgs = [convert]::ToBase64String($bytes)
    return $base64targetArgs
}

function Convert-Base64ToString
{
    param ( $file )
    $d = Get-Content -Raw -Read 0 $file
    $s = $d -replace ".*-EncodedCommand " -replace '"'
    $bytes = [convert]::FromBase64String($s)
    $script = [text.Encoding]::Unicode.GetString($bytes)
    return $script
}
function Invoke-CoverageTest
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [string]$PowerShellExePath,
        [switch]$Elevated,
        [string]$Coverlet,
        [string[]]$TargetScript,
        [string]$PesterCommand
    )

    $tempPath = [io.path]::GetTempPath()

    if ( $Elevated ) {
        $workerScriptPath   = Join-Path $tempPath "CoverletWorkerElevated.ps1"
        $driverScriptPath   = Join-Path $tempPath "CoverletDriverElevated.ps1"
        $coverletResultPath = Join-Path $tempPath "Coverage.Elevated.json"
    }
    else {
        $workerScriptPath   = Join-Path $tempPath "CoverletWorkerUnelevated.ps1"
        $driverScriptPath   = Join-Path $tempPath "CoverletDriverUnelevated.ps1"
        $coverletResultPath = Join-Path $tempPath "Coverage.Unelevated.json"
    }
    # how we will run the driver script
    $runner = Get-ElevatorExe -Elevated:$Elevated
    # construct the driver script
    "Set-Location $(Split-Path $PowerShellExePath)",
    "$runner ${PowerShellExePath} -c $workerScriptPath" | out-file -encoding ascii $driverScriptPath

    # construct the coverlet scipt
    [string[]]$commandElements = $TargetScript
    $commandElements += $PesterCommand
    $encodedCommand = Convert-ScriptToBase64 ($commandElements -join ";")

    "$Coverlet --output $coverletResultPath --targetargs ""-EncodedCommand $encodedCommand""" |
        out-file -encoding Ascii $workerScriptPath

    # Actually invoke the script 
    & $driverScriptPath
}