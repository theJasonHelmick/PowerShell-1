param ( [switch]$nugetonly )
push-location ReferenceAssembly

if ( ! $nugetonly )
{
    # build the assembly
    dotnet restore
    dotnet publish
}

$PackageName = "System.Management.Automation"

$source = "obj\Debug\netstandard2.0\System.Management.Automation.dll"

$head = '<package xmlns="http://schemas.microsoft.com/packaging/2011/08/nuspec.xsd">'
$meta = ' <metadata>',
        "  <id>$PackageName</id>",
        '  <version>1.0.0</version>',
        '  <title>Microsoft PowerShell Standard 3 Reference Assemblies</title>',
        '  <authors>Microsoft</authors>',
        '  <owners>Microsoft</owners>',
        '  <projectUrl>https://msdn.microsoft.com/en-us/mt173057.aspx</projectUrl>',
        '  <requireLicenseAcceptance>false</requireLicenseAcceptance>',
        '  <description>Contains the reference assemblies for PowerShell Standard 3</description>',
        '  <copyright>Copyright 2017</copyright>',
        '  <tags>PowerShell reference assembly</tags>',
        '  <references>',
        '   <reference file="System.Management.Automation.dll" />',
        '  </references>',
        ' </metadata>'

#$dependencies = "  <dependencies>",
#    $(sls packagereference *csproj | foreach-object { 
#        $d = $_.line -replace "PackageReference","dependency" 
#        $d = $d -replace "Include=","id="
#        $d = $d -creplace "Version=","version=" 
#        $d
#        }
#        ),
#    '   </dependencies>',
#        ' </metadata>'
#
$files = $source | foreach-object {
    ' <files>'
    }{
    '  <file src="{0}" target="lib\netstandard2.0" />' -f $_
    }{
    '  </files>'
    }

$tail = '</package>'

$nuspecFile = "${packageName}.1.0.0.nuspec"
$nupkgFile = "${packageName}.1.0.0.nupkg"

.{ 
$head
$meta
# $dependencies
$files
$tail
} |set-content -encoding Ascii $nuspecFile

nuget.exe pack $nuspecFile


$nugetTarget = "c:\nuget"
$nugetInstalledLocation = "${nugetTarget}\system.management.automation"
if ( test-path $nugetInstalledLocation ) {
    remove-item -force -recurse $nugetInstalledLocation
}
nuget.exe add $nupkgFile -source c:\NuGet -expand
pop-location

push-location Test
dotnet restore
dotnet build
push-location "bin\Debug\netstandard2.0"
$result = & "$PSHOME/powershell" -noprofile -c "import-module ./Demo.Cmdlet.dll;get-thing"
$result -match "oh yeah!"
pop-location
pop-location
