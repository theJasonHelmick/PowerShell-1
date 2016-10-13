try {
    $defaultParameterValues = $PSDefaultParameterValues.clone()
    if ( ! $IsWindows ) {
        $global:PSDefaultParameterValues['it:skip'] = $true
        $script:SkipTests = $true
    }
    Describe "New-CimSession" {
        BeforeAll {
            if ( $SkipTests ) { return }
            $sessions = @()
        }
        AfterAll {
            if ( $SkipTests ) { return }
            $sessions | remove-cimsession
        }
        It "A cim session can be created" {
            $sessionName = [guid]::NewGuid()
            $session = New-CimSession -ComputerName . -name $sessionName
            $session.Name | Should be $sessionName
            $session.InstanceId  | should BeOfType "System.Guid"
            $sessions += $session 
        }
        It "A cim session can be removed" {
            $sessionName = [guid]::NewGuid()
            $session = New-CimSession -ComputerName . -name $sessionName
            $session.Name | Should be $sessionName
            $session | Remove-CimSession
            Get-CimSession $session.Id -ErrorAction SilentlyContinue| should BeNullOrEmpty
        }
    }
}
finally {
    $global:PSDefaultParameterValues = $defaultParameterValues
}
