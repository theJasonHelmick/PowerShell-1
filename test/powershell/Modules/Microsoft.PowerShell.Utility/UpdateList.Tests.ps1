Describe "UpdateList Tests" -Tag CI {
    BeforeEach {
        # Create an object with a property that we can manipulate
        $obj = "a string"
        $obj = add-member -passthru -in $obj noteproperty zzz ([collections.arraylist](1,2))
    }

    It "Add 1 element, check value passed on by update-list" {
        $result = $obj | update-list -property zzz -add 3 | % { $_.zzz }
        $result.Count | Should be 3
        $obj.zzz.Count | Should be 3
    }

    It "Remove 1 element previously added, ignore value passed on, verify correct collection updated" {
        [void]($obj | update-list -property zzz -remove 3)
        $obj.zzz.Count | Should be 2
    }

    It "Remove 1 element from the original collection, check value passed on (in a different way than above)" {
        $result = $obj | update-list -property zzz -remove 1
        $result.zzz.Count | Should be 1
        $obj.zzz.Count | Should be 1
    }

    It "Remove 1 more element to empty the collection" {
        [void]($obj | update-list -property zzz -remove 1,2)
        $obj.zzz.Count | Should be 0
    }

    It "Add something to make sure the collection is still there." {
        [void](update-list -property zzz -in $obj -add 3)
        $obj.zzz.Count | Should be 3
    }

    It "Add multiple elements, and different types" {
        [void](update-list -property zzz -in $obj -add "42", ([char]'a'), 0x20)
        $obj.zzz.Count | Should be 5
        $obj.zzz[2] | Should be "42"
        $obj.zzz[3] | Should be ([char]'a')
        $obj.zzz[4] | Should be 0x20
    }

    It "Remove multiple elements, and different types" {
        [void](update-list -property zzz -in $obj -add "42", ([char]'a'), 0x20)
        [void](update-list -property zzz -in $obj -remove 3, ([char]'a'))
        $obj.zzz.count | Should be 4
        $obj.zzz[2] | Should be "42"
        $obj.zzz[3] | Should be 0x20
    }

    It "Remove something that isn't there" {
        [void](update-list -property zzz -in $obj -remove 1000)
        $obj.zzz.count | Should be 2
    }

    It "Test replace" {
        [void](update-list -property zzz -in $obj -replace 10,20,30)
        $obj.zzz.count | Should be 3
        $obj.zzz[0] | Should be 10
        $obj.zzz[1] | Should be 20
        $obj.zzz[2] | Should be 30
    }

    It "Test PSListModifier directly" {
        $mod = [System.Management.Automation.PSListModifier]::new((@{Add=3,4}))
        $list = [collections.arraylist](1,2)
        $mod.ApplyTo($list)
        $list.Count | Should be 4
        $list[2] | Should be 3
    }

    It "remove more" {
        $mod = [System.Management.Automation.PSListModifier]::new((@{Add=3,4; Remove=1,2}))
        $list = [collections.arraylist](1,2)
        $mod.ApplyTo($list)
        $list.Count | Should be 2
        $list[1] | Should be 4
    }

    It "remove array" {
        $mod = [System.Management.Automation.PSListModifier]::new((@{Replace=40,50}))
        $list = [collections.arraylist](1,2)
        $mod.ApplyTo($list)
        $list.Count | Should be 2
        $list[1] | Should be 50
    }

    It "Test parameter binding of the generic type" {
        function foo {
            param([System.Management.Automation.PSListModifier[int]]$p)	
        }
        { foo (Update-List -Add 42 -Remove 55) } | Should Not Throw
        { foo @{Add=42; Remove=55} } | Should Not Throw
    }

    Context "Error Conditions" {
        It "Test constructor of PSListModifier with bad modifier" {
            { $mod = [System.Management.AutomationPSListModifier]::New(@{Garbage=42}) } | should throw
        }

        It "Test exception when providing bad data" {
            $obj = "a string"
            $obj = add-member -passthru -in $obj noteproperty zzz @{abc=42}
            [void](update-list -property zzz -in $obj -Add 52 -ev errorobject -ea silentlycontinue)
            $errorobject[0].exception.gettype() | Should be ([system.management.automation.PSInvalidOperationException])
        }

        It "Null input produces an error" {
            $null | update-list -property zzz -ea silentlycontinue -ev errorobject
            $errorobject[0].exception.gettype().name | Should be "ParameterBindingValidationException"
        }
        
        It "An incorrect property name produces an error" {
            $obj = "a string"
            $obj = add-member -passthru -in $obj noteproperty zzz @{abc=42}
            $obj | update-list -property WRONGPROPERTY -ea silentlycontinue -ev errorobject
            $errorobject.FullyQualifiedErrorId | should be "MemberDoesntExist,Microsoft.PowerShell.Commands.UpdateListCommand"
        }
        
        It "A missing property with an object produces an error" {
            update-list -property zzz -ea silentlycontinue -ev errorobject
            $errorobject.FullyQualifiedErrorId | Should be "MissingInputObjectParameter,Microsoft.PowerShell.Commands.UpdateListCommand"
        }
    }
}