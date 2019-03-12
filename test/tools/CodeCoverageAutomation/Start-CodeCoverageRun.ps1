# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
[CmdletBinding()]
param(
    # not uploading to coveralls
    # [Parameter(Mandatory = $true, Position = 0)] $coverallsToken,
    [Parameter(Mandatory = $true, Position = 0)] $codecovToken,
    [Parameter(Position = 2)] $azureLogDrive = "L:\",
    [Parameter()][String]$BaseFolder = "${env:Temp}\CC",
    [switch] $SuppressQuiet,
    [switch] $Norun,
    [switch] $NoUpload
)

Import-Module -Force "${PSScriptRoot}/CodeCoverage.psm1"

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference    = 'Stop'
$oldProgressPreference    = $ProgressPreference
$ProgressPreference       = 'SilentlyContinue'
$outputLogPattern         = "$BaseFolder\CodeCoverageOutput*"
$elevatedLog              = "$BaseFolder\TestResults_Elevated.xml"
$unelevatedLog            = "$BaseFolder\TestResults_Unelevated.xml"
$testPath                 = "${BaseFolder}\tests"
$testToolsPath            = "${testPath}\tools"
$openCoverTargetDirectory = "$BaseFolder\OpenCoverToolset"
$psBinPath                = "${BaseFolder}\CodeCoverage"

If ( $PSBoundParameters['Debug'] ) {
    Wait-Debugger
}

try {
    Write-LogPassThru -Message "START COVERAGE RUN" -Banner

    Initialize-Environment -baseFolder $BaseFolder -OutputLog $outputLogPattern -NoRun:$Norun
    Export-LogArchive -log $elevatedLog,$unelevatedLog,outputLogPattern

    # get the artifact that contains all the files we need
    Receive-Package -BaseFolder $BaseFolder


    Write-LogPassThru -Message "Install and import OpenCover module"

    # install opencover
    ##### use updated OpenCover.psm1
    ##### DO NOT CHECK THIS IN
    Copy-Item C:\tmp\OpenCover.psm1 $BaseFolder\OpenCover -force
    #####
    Import-Module "$BaseFolder\OpenCover" -Force
    Install-OpenCover -TargetDirectory $openCoverTargetDirectory -force
    Write-LogPassThru -Message "OpenCover installed."

    $commitId = Get-CommitId -psexe "${psBinPath}\pwsh.exe"

    try {
        $Status = "SUCCEEDED"
        # now optionally invoke opencover, this will invoke both non-elevated and elevated passes
        if ( $NoRun ) {
            $Status = "SKIPPED"
        }
        else {
            Write-LogPassThru -Message "STARTING TEST EXECUTION" -Banner
            $openCoverParams = @{
                OutputLog = $outputLogPattern;
                TestPath = $testPath;
                OpenCoverPath = "$openCoverTargetDirectory\OpenCover";
                PowerShellExeDirectory = "$psBinPath";
                PesterLogElevated = $elevatedLog;
                PesterLogUnelevated = $unelevatedLog;
                TestToolsModulesPath = "$testToolsPath\Modules";
            }
            Write-LogPassThru -message "Invoking OpenCover" -Data $openCoverParams
            if($SuppressQuiet) {
                $openCoverParams.Add('SuppressQuiet', $true)
            }
            Invoke-OpenCover @openCoverParams | Out-String -Stream | Where-Object {$_} | Write-LogPassThru
        }
    }
    catch {
        $Status = "FAILED"
        ("ERROR: " + $_.ScriptStackTrace) | Write-LogPassThru
        $_ 2>&1 | out-string -Stream | Foreach-Object { "ERROR: $_" } | Write-LogPassThru
    }
    Write-LogPassThru -Message "TEST EXECUTION ${Status}" -Banner

    # OpenCover will merge xml results which takes forever,
    # so we create a number of output logs and let CodeCov.io do the merging
    $logs = Get-LogFile -PathPattern $outputLogPattern
    if ( $NoUpload ) {
        Write-LogPassThru -Message ("Not uploading {0} logs" -f @($logs).count)
    }
    else {
        Send-CoverageData -Log $logs -CommitId $commitId -Token $codecovToken
    }
}
catch
{
    Write-LogPassThru -Message "ERROR: $_"
    Write-LogPassThru -Message $_.ScriptStackTrace
}
finally
{
    # the powershell execution should be done, be sure that there are no PowerShell test executables running because
    # they will cause subsequent coverage runs to behave poorly. Make sure that the path is properly formatted, and
    # we need to use like rather than match because on Windows, there will be "\" as path separators which would need
    # escaping for -match
    $ResolvedPSBinPath = (Resolve-Path ${psbinpath} -ea Ignore ).Path
    if ( $ResolvedPSBinPath ) {
        $PowerShells = Get-Process | Where-Object { $_.Path -like "*${ResolvedPSBinPath}*" }
        $PowerShells | Stop-Process -Force -ErrorAction Continue
    }

    ## See if Azure log directory is mounted
    if ( Test-Path $azureLogDrive ) {
        Copy-ToAzureDrive -Location $azureLogDrive
    }

    ## Disable the cleanup till we stabilize.
    #Remove-Item -recurse -force -path $BaseFolder
    $ErrorActionPreference = $oldErrorActionPreference
    $ProgressPreference = $oldProgressPreference
    Write-LogPassThru -Message "COMPLETE" -Banner
}
