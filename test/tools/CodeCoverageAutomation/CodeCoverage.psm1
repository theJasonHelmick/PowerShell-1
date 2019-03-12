# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

# Read the XML and create a dictionary for FileUID -> file full path.
function Get-FileTable()
{
    $files = $script:covData | Select-Xml './/File'
    foreach($file in $files)
    {
        $script:fileTable[$file.Node.uid] = $file.Node.fullPath
    }
}

# Get sequence points for a particular file
function Get-SequencePointsForFile([string] $fileId)
{
    $lineCoverage = [System.Collections.Generic.Dictionary[string,int]]::new()

    $sequencePoints = $script:covData | Select-Xml ".//SequencePoint[@fileid = '$fileId']"

    if($sequencePoints.Count -gt 0)
    {
        foreach($sp in $sequencePoints)
        {
            $visitedCount = [int]::Parse($sp.Node.vc)
            $lineNumber = [int]::Parse($sp.Node.sl)
            $lineCoverage[$lineNumber] += [int]::Parse($visitedCount)
        }

        return $lineCoverage
    }
}

#### Convert the OpenCover XML output for CodeCov.io JSON format as it is smaller.
function ConvertTo-CodeCovJson
{
    param(
        [string] $Path,
        [string] $DestinationPath
    )

    $Script:fileTable = [ordered]@{}
    $Script:covData = [xml] (Get-Content -ReadCount 0 -Raw -Path $Path)
    $totalCoverage = [PSCustomObject]::new()
    $totalCoverage | Add-Member -MemberType NoteProperty -Name "coverage" -Value ([PSCustomObject]::new())

    ## Populate the dictionary with file uid and file names.
    Get-FileTable
    $keys = $Script:fileTable.Keys
    $progress=0
    foreach($f in $keys)
    {
        Write-Progress -Id 1 -Activity "Converting to JSON" -Status 'Converting' -PercentComplete ($progress * 100 / $keys.Count)
        $fileCoverage = Get-SequencePointsForFile -fileId $f
        $fileName = $Script:fileTable[$f]
        $previousFileCoverage = $totalCoverage.coverage.${fileName}

        ##Update the values for the lines in the file.
        if($null -ne $previousFileCoverage)
        {
            foreach($lineNumber in $fileCoverage.Keys)
            {
                $previousFileCoverage[$lineNumber] += [int]::Parse($fileCoverage[$lineNumber])
            }
        }
        else ## the file is new, so add the values as a new NoteProperty.
        {
            $totalCoverage.coverage | Add-Member -MemberType NoteProperty -Value $fileCoverage -Name $fileName
        }

        $progress++
    }

    Write-Progress -Id 1 -Completed -Activity "Converting to JSON"

    $totalCoverage | ConvertTo-Json -Depth 5 -Compress | Out-File $DestinationPath -Encoding ascii
}

function Write-LogPassThru
{
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position = 0, ParameterSetName="banner")]
        [string[]] $Message,
		[Parameter(Mandatory=$false)][hashtable] $Data,
        [Parameter(Mandatory=$false)]$Path = "C:\tmp\CCLog.txt", # DO NOT CHECK IN "$env:Temp\CodeCoverageRunLogs.txt",
		[Parameter()][switch]$HostOnly,
		[Parameter(ParameterSetName="banner")][switch]$Banner
    )

    PROCESS {
		if ( $banner ) {
			$message | %{ $l = 0 } { if ( $l -lt $_.length ) { $l = $_.length } } { $l += 8 }
			$message = $message | %{ "*" * $l } { "*** $_ ***" } { "*" * $l }
		}
        foreach ( $m in $Message ) {
            $formattedMessage = "{0:d} - {0:t} : {1}" -f ([datetime]::now), "$m"
			if ( $HostOnly ) {
				Write-Verbose -verbose $formattedMessage
			}
			else {
				Add-Content -Path $Path -Value $formattedMessage -PassThru -Force
			}
        }
		if ( $Data -ne $null ) {
			$pad = $data.keys | %{ $l = 0 } { if ( $_.length -gt $l ) { $l = $_.length } } { $l }
			foreach ( $key in $data.keys ) {
				$fmtStr = "{0:d} - {0:t} : {1,-${pad}} = {2}" 
				$formattedMessage = $fmtStr -f ([datetime]::now), $key, $data.$key
				if ( $HostOnly ) {
					Write-Verbose -verbose $formattedMessage
				}
				else {
					Add-Content -Path $Path -Value $formattedMessage -PassThru -Force
				}	
			}
		}
    }
}

function Copy-ToAzureDrive {
	param ( [Parameter(Mandatory=$true,Position=0)][string]$location )

	##Create yyyy-dd folder
	$monthFolder = "{0:yyyy-MM}" -f [datetime]::Now
	$monthFolderFullPath = New-Item -Path (Join-Path $azureLogDrive $monthFolder) -ItemType Directory -Force
	$windowsFolderPath = New-Item (Join-Path $monthFolderFullPath "Windows") -ItemType Directory -Force
	$destinationPath = Join-Path $env:Temp ("CodeCoverageLogs-{0:yyyy_MM_dd}-{0:hh_mm_ss}.zip" -f [datetime]::Now)

	Compress-Archive -Path $elevatedLogs,$unelevatedLogs,$outputLog -DestinationPath $destinationPath
	Copy-Item $destinationPath $windowsFolderPath -Force -ErrorAction SilentlyContinue

	Remove-Item -Path $destinationPath -Force -ErrorAction SilentlyContinue
}

function Send-CodeCovData
{
    param (
        [Parameter(Mandatory=$true)]$file,
        [Parameter(Mandatory=$true)]$CommitID,
        [Parameter(Mandatory=$false)]$token,
        [Parameter(Mandatory=$false)]$Branch = "master"
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor
        [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Tls11

    $VERSION="64c1150"
    $url="https://codecov.io"

    $query = "package=bash-${VERSION}&token=${token}&branch=${Branch}&commit=${CommitID}&build=&build_url=&tag=&slug=&yaml=&service=&flags=&pr=&job="
    $uri = "$url/upload/v2?${query}"
    $response = Invoke-WebRequest -Method Post -InFile $file -Uri $uri

    if ( $response.StatusCode -ne 200 ) {
        Write-LogPassThru -Message "Upload failed for upload uri: $uploaduri"
        throw "upload failed"
    }
    else {
        Write-LogPassThru -Message "Upload finished for upload uri: $uploaduri"
    }
}

function Initialize-Environment
{

	param ( [string]$BaseFolder, [string]$OutputLog, [switch]$NoRun )
    # START OF THE RUN
    Write-LogPassThru -Message "Initialize Environment" -Banner

    ## Github needs TLS1.2 whereas the defaults for Invoke-WebRequest do not have TLS1.2
    # $script:prevSecProtocol = [System.Net.ServicePointManager]::SecurityProtocol.value__
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor
        [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Tls11

    if ( ! ( Test-Path $BaseFolder) ) {
        $null = New-Item -ItemType Directory -Path $BaseFolder -Force
    }

    Write-LogPassThru -Message "Forcing winrm quickconfig as it is required for remoting tests."
    winrm quickconfig -force

    # first thing to do is to be sure that no processes are running which will cause us issues
    Get-Process pwsh -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop

    ## This is required so we do not keep on merging coverage reports from previous runs.
    # only remove the file if we're actually going to do a run
    if( (Test-Path $outputLog) -and ! $Norun)
    {
        Remove-Item $outputLog -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# all of the code coverage files are part of the 
# CodeCoverage.zip artifact. In that artifact are three zip archives
# CodeCoverage.zip - the build of PowerShell to use
# OpenCover.zip    - the OpenCover Module
# tests.zip        - the test files including the assets and needed sources
#
function Receive-Package
{
    param ( [Parameter(Mandatory=$true,Position=0)]$BaseFolder, [switch]$NoExpand, [switch]$NoClobber )

    Write-LogPassThru -Message "Starting downloads.","Retrieving artifact url"
    $dailyBuildInfo = Invoke-RestMethod "https://dev.azure.com/powershell/powershell/_apis/build/builds?definitions=32"
    $latestWindowsDaily = $dailyBuildInfo.Value | Select-Object -First 1
    $latestBuildId = $latestWindowsDaily.Id
    $artifactUrl = "https://dev.azure.com/powershell/powershell/_apis/build/builds/$latestBuildId/artifacts?artifactName=CodeCoverage"
    $CodeCoverageArtifactUrl = (Invoke-RestMethod $artifactUrl).Resource.downloadUrl

    # download the files to $env:TEMP
    $artifactPath = "${env:TEMP}\ccBuild.${latestBuildId}.zip"
    Write-LogPassThru "downloading $CodeCoverageArtifactUrl to $artifactPath"
	if ( (Test-Path $artifactPath) -and $NoClobber ) {
		Write-LogPassThru "Using existing $artifactPath"
	}
	else {
		try {
			# Webclient.Downloadfile is about 26x faster than Invoke-WebRequest (13 vs 296 seconds)
			# if there's a problem, we'll fall back to Invoke-WebRequest
			$wc = [System.Net.Webclient]::new()
			$wc.DownloadFile($CodeCoverageArtifactUrl, $artifactPath)
		}
		catch {
			$response = Invoke-WebRequest -uri $CodeCoverageArtifactUrl -outFile $artifactPath
		}
	}

	# no file, we can't continue
	if ( ! (Test-Path $artifactPath)) {
		throw "File download failed"
	}

	if ( $NoExpand ) {
		return
	}

    # Extract the various zip files
    $stagingDir = "${env:TEMP}\ccBuild.${latestBuildId}"
    Write-LogPassThru "expanding $artifactPath files into $stagingDir"
    Expand-Archive -Path $artifactPath -DestinationPath $stagingDir -Force

	# TODO: change test archive to the one that includes the assets and sources
    $archiveList = "OpenCover","CodeCoverage","TestPackage"
    foreach ( $archiveName in $archiveList ) {
        # it's a zip file, and the name of the downloaded zip archive is
		# where the interior zip files are laid down
        $archivePath = "${stagingDir}/CodeCoverage/${archiveName}.zip"
		# the extraction of the TestPackage needs to be in the BaseFolder
		if ( $archiveName -eq "TestPackage" ) {
			$target = $BaseFolder
		}
		else {
			$target = "${BaseFolder}/${archiveName}"
		}
		Write-LogPassThru -Message "expanding $archivePath into ${target}"
		Expand-Archive -Path $archivePath -DestinationPath "${target}" -Force
		if ( $archiveName -eq "CodeCoverage" ) {
			# install Pester
			Save-Module -Name Pester -RequiredVersion 4.4.4 -Path "${target}/Modules"
		}
    }

    if ( ! $NoClobber ) {
        foreach ( $i in "${artifactPath}","${stagingDir}" ) {
            try {
                Remove-Item $i -recurse -force
            }
            catch {
                Write-Warning "Could not remove $i"
            }
        }
    }
	Write-LogPassThru -Message "Download and expansion complete"
}

function Export-LogArchive
{
	param ( [Parameter(Mandatory=$true)][string[]]$log )
	# only archive files that exist 
	$logpaths = $log | where-object { test-path $_ }
	if ( ! $logPaths ) {
		Write-LogPassThru -Message "No logs to archive"
	}
	else {
		$DestinationArchive = "TestResults.{0:yyyyMMddhhmm}.zip" -f [datetime]::now
		Write-LogPassThru -Message "Creating test archive $DestinationArchive"
		Compress-Archive -DestinationPath $DestinationArchive -Path $logpaths -EA SilentlyContinue
		# Remove-Item -Path $logpaths -EA SilentlyContinue
	}
}

function Convert-CoverageDataToJson
{
	param ( [Parameter(Mandatory=$true,Position=0)][string[]]$log, [ref]$jsonLog )

	$returnLogList = @()
	foreach ( $logfile in $log ) {
		$jsonLogfile = $logfile + ".json"
		$returnLogList += $jsonLogfile
		Write-LogPassThru -Message "Converting $logfile to $jsonLogfile"
		$null = ConvertTo-CodeCovJson -Path $logfile -DestinationPath $jsonLogfile
	}
	$jsonLog.Value = $returnLogList
}

# upload the logs
function Send-CoverageData {
	param ( 
		[Parameter(Mandatory=$true)][string[]]$jsonLog,
		[Parameter(Mandatory=$true)][string]$commitId,
		[Parameter(Mandatory=$true)][string]$Token,
		[Parameter()][switch]$NoUpload
		)

	# get the commit message
    # $commitInfo = Invoke-RestMethod -Method Get "https://api.github.com/repos/powershell/powershell/git/commits/$commitId"
    # $message = $commitInfo.message -replace "`n", " "

	$logcount = 0
	foreach ( $file in $jsonLog ) {
		if ( $NoUpload ) {
			Write-LogPassThru -Message "Not uploading $file"
		}
		else {
			Write-LogPassThru -Message "Uploading $file to CodeCov"
			try {
				Send-CodeCovData -file $file -CommitID $commitId -token $Token -Branch 'master'
				$logcount++
			}
			catch {
				Write-LogPassThru "ERROR: Could not upload $file ($_)"
			}
			Write-LogPassThru -Message "Upload of $file complete."
		}
	}
	Write-LogPassThru -Message ("{0} log files uploaded to codecov.io" -f $logCount)
}

function Get-LogFile {
	param (
		[Parameter(Mandatory=$true)]$PathPattern
		)

	$logs = Get-ChildItem -Path ${PathPattern} -ErrorAction SilentlyContinue
	return $logs.FullName
}

function Get-CommitId {
	param ([Parameter(Mandatory=$true)]$psexe)

	# grab the commitID, we need this to grab the right sources
	$assemblyLocation = & "$psexe" -noprofile -command { Get-Item ([psobject].Assembly.Location) }
	$productVersion = $assemblyLocation.VersionInfo.productVersion
	$commitId = $productVersion.split(" ")[-1]
	Write-LogPassThru -Message "Using GitCommitId: $commitId"
	return $commitId
}

