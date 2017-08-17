push-location $PsScriptRoot

# build and publish the reference assembly
push-location ReferenceAssembly
$result = dotnet restore 2>&1
if ( $LASTEXITCODE -ne 0 ) {
    throw "restore FAIL: $result"
}

$result = dotnet publish 2>&1
if ( $LASTEXITCODE -ne 0 ) {
    throw "publish FAIL: $result"
}

# build the nuget spec file
# don't proceed if the assembly is missing
# $PackageName = "S ystem.Management.Automation"
$PackageName = "PowerShellStandard.Library"
$PackageVersion = "3.0.0-preview-01"
$DllName = "System.Management.Automation.dll"
$source = "obj\Debug\netstandard2.0\${DllName}"
if ( ! (Test-Path $source) ) {
    throw "assembly $source not found"
    exit
}

$body = '<package xmlns="http://schemas.microsoft.com/packaging/2011/08/nuspec.xsd">',
        ' <metadata>',
        "  <id>$PackageName</id>",
        "  <version>${PackageVersion}</version>",
        '  <title>PowerShellStandard.Library</title>',
        '  <authors>Microsoft</authors>',
        '  <owners>Microsoft</owners>',
        '  <projectUrl>https://msdn.microsoft.com/en-us/mt173057.aspx</projectUrl>',
        '  <requireLicenseAcceptance>false</requireLicenseAcceptance>',
        '  <description>Contains the reference assembly for PowerShell Standard 3</description>',
        '  <copyright>Copyright 2017</copyright>',
        '  <tags>PowerShell, netstandard2, netstandard2.0</tags>',
        '  <references>',
        "   <reference file=""${DllName}"" />",
        '  </references>',
        ' </metadata>',
        ' <files>',
        "  <file src=""${source}"" target=""lib\netstandard2.0"" />",
        ' </files>',
        '</package>'

$nuspecFile = "${packageName}.${PackageVersion}.nuspec"
$nupkgFile = "${packageName}.${PackageVersion}.nupkg"

$body |set-content -encoding Ascii $nuspecFile
if ( ! (test-path "${nuspecFile}")) {
    throw "${nuspecFile} could not be created"
}

# make the package
$result = nuget.exe pack $nuspecFile 2>&1
if ( $LASTEXITCODE -ne 0 ) {
    throw "nuget pack FAIL: $result"
}

# local target for test
$nugetTarget = "c:\nuget"
$packageNameLower = $packageName.ToLower()
$nugetInstalledLocation = "${nugetTarget}\${packageNameLower}"
if ( test-path $nugetInstalledLocation ) {
    remove-item -force -recurse $nugetInstalledLocation
}
$result = nuget.exe add $nupkgFile -source c:\NuGet -expand 2>&1
if ( $LASTEXITCODE -ne 0 ) {
    throw "nuget expand FAIL: $result"
}
pop-location

# build the demo module assembly
push-location Test
$result = dotnet restore 2>&1
if ( $LASTEXITCODE -ne 0 ) {
    throw "restore FAIL: $result"
}

$result = dotnet publish 2>&1
if ( $LASTEXITCODE -ne 0 ) {
    throw "publish FAIL: $result"
}
$moduleDll = "${PWD}\bin\Debug\netstandard2.0\Demo.Cmdlet.dll"

if ( ! (Test-Path ${moduleDll})) {
    throw "Could not find built Demo assembly"
}

# all done with the building
pop-location
pop-location

#### TESTS
Describe "Test cmdlet assembly" {
    It "Should work against the current PowerShell 6" {
        $result = & "$PSHOME/powershell" -noprofile -c "import-module ${moduleDll};get-thing"
        $result | should match "Success!"
    }
    It "Should work against inbox PowerShell" -skip:(!$IsWindows) {
        $ps5 = "${env:WinDir}\System32\windowspowershell\v1.0\powershell.exe"
        $result = & "${ps5}" -noprofile -c "import-module ${moduleDll};get-thing"
        $result | should match "Success!"
    }
}
