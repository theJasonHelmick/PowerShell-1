Try {
    if ( ! $IsWindows ) {
        $PSDefaultParameterValues["it:pending"] = $true
    }
    Describe "CimInstance cmdlet tests" {
        BeforeAll {
            if ( ! $IsWindows ) { return }
            $instance = get-ciminstance cim_computersystem
        }
        It "CimClass property should not be null" {
            # we can't use equals here as on windows cimclassname
            # is win32_computersystem, but that's not likely to be the
            # case on non-Windows systems
            $instance.cimClass.CimClassName | should match _computersystem
        }
        It "Property access should be case insensitive" {
            foreach($property in $instance.psobject.properties.name) {
                $pUpper = $property.ToUpper()
                $pLower = $property.ToLower()
                [string]$pLowerValue = $pinstance.$pLower -join ","
                [string]$pUpperValue = $pinstance.$pUpper -join ","
                $pLowerValue | should be $pUpperValue
            }
        }
        
    }
}
finally {
    $PSDefaultParameterValues.Remove("it:pending")
}
