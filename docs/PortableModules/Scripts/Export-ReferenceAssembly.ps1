param ( [string]$AssemblyName = "System.Management.Automation", [string]$ExclusionFile = "Exclusions.json" )
$assembly = [appdomain]::CurrentDomain.GetAssemblies() | ?{$_.Location -match $AssemblyName}

function Get-Exclusions
{
    param ( $exclusionFile )
    $script:ExcludedItems = get-content $exclusionFile | ConvertFrom-Json
}

function Exclude-Member ( $name ) {
    #$script:namespace
    #$script:CurrentClass
    foreach($member in $ExcludedItems.classmember) {
        if ( $name -eq $member.property -and $script:namespace -eq $member.namespace -and $script:CurrentClass -eq $member.class )
        {
            return $true
        }
    }
    return $false
}

function Exclude-Class ( $name ) {
    foreach ($class in $ExcludedItems.class) {
        if ( $name -eq $class.class -and $script:namespace -eq $class.namespace ) { return $true }
    }
    return $false
}



function GetTypeName ( $type )
{
    if ( $type.IsGenericTypeDefinition -or $type.IsGenericType) {
        $names = $type.GenericTypeParameters.Name
        $tname = Get-TypeNickname $type.fullname
        if ( ! $tname ) { $tname = Get-TypeNickname $type.name }
        if ( ! $names ) { 
            $names = $type.GenericTypeArguments 
        }
        $tname = Get-TypeNickname $tname
        "{0}<{1}>" -f ($tname -replace "``.*"),($names -join ",")
    }
    else {
        $type.name
    }
}

function Get-TypeNickname ( [string]$typename )
{
    $TypeTranslation = @{
        "Object" = "object"
        "Boolean" = "bool"
        "UInt32" = "uint"
        "String" = "string"
        "Int32" = "int"
        "Void" = "void"

        "Object[]" = "object[]"
        "System.Object[]" = "object[]"

        "System.Object" = "object"
        "System.Boolean" = "bool"
        "System.UInt32" = "uint"
        "System.String" = "string"
        "System.Int32" = "int"
        "System.Void" = "void"
    }

    $typename = $typename -replace "\+","."
    $typename = $typename -replace "``.*"
    $v = $TypeTranslation["$typename"]
    if ( $v ) { return $v } else { return $typename }
}

function IsStaticClass ( $Type )
{
    if ( $Type.IsAbstract -and $Type.IsSealed ) { "static" }
}

function IsSealedClass ( $Type ) {
    if ( $Type.IsEnum ) { return }
    if ( $Type.IsSealed -and ! $Type.IsAbstract ) { "sealed" }
}

function IsAbstract ( $Type ) {
    if ( $type.IsAbstract -and ! $Type.IsSealed ) { "abstract" }
}

function GetTypeType ( $type )
{
    if ( $type.IsInterface ) { return "interface" }
    if ( $type.IsClass ) { return "class" }
    if ( $type.IsEnum ) { return "enum" }
}

function EmitEnum ( $t )
{
    $names = [enum]::GetNames($t) | sort-object
    $names | %{
        "    $_ = {0}," -f ($t::"$_").value__
    }
}

function EmitConstants ( $t )
{
    $attrs = [reflection.fieldattributes]"Literal,HasDefault"
    $constants = $t.GetFields("Static,Instance,Public,DeclaredOnly")|
        where-object {$_.Attributes -band $attrs}|
        where-object {$_.FieldType.FullName -eq "system.string"}|
        sort-object Name
    $constantCount = $constants.Count
    foreach ( $constant in $constants )
    {
        if ( $t.IsAbstract -and ! $t.IsSealed ) { $visibility = "protected" } else { $visibility = "public" }
        $fmt = '    {0} const {1} {2} = "{3}";' 
        $fmt -f $visibility,(Get-TypeNickname $constant.FieldType),$constant.Name,$constant.GetValue($null)
        #$const += "const "
        #$const += Get-TypeNickname $constant.FieldType
        #$const += " "
        #$const += $constant.Name
        #$const += " = "
        #$const += '"{0}";' -f $constant.GetValue($null)
        #$const
    }
}
function EmitProperties ( $t )
{
    $properties = $t.GetProperties("Static,Instance,Public,DeclaredOnly")| sort-object Name
    $propertyCount = $properties.Count
    foreach ( $Property in $properties)
    {
        # emit the member only if not excluded
        if ( Exclude-Member $property.name ) { $propertyCount--; continue }
        # check for generic
        if ( $Property.PropertyType.IsGenericType ) {
            #wait-debugger
            $propertyArgs = $property.propertytype.GenericTypeArguments | %{ $a = @()}{$a += Get-TypeNickName $_.fullname}{$a -join ","}
            $propertyType = $property.propertytype.fullname -replace "``.*"
            $propertyString = "{0}<{1}>" -f $propertyType,$propertyArgs
        }
        else {
            $propertyString = Get-TypeNickName $property.propertytype.fullname
        }
        [string]$dec = ""
        # Attributes
        if ( $property.CustomAttributes ) {
            # wait-debugger
            $attributes = $property.CustomAttributes | Sort-Object AttributeType
            foreach($attribute in $attributes) {
                $dec += "    ${attribute}`n" -replace "\(\)","" -creplace " String"," string" -creplace " True","true" -creplace " False","false"
            }
        }
        $dec += "    public {0} {1} {{" -f $propertyString,$property.name
        if ( $property.GetMethod ) { $dec += " get { return default($propertyString); }" }
        if ( $property.SetMethod ) { $dec += " set { }" }
        $dec += " }" 
        $dec
    }
}

function EmitConstructors ( $t )
{
    $constructors = $t.GetConstructors("Public,NonPublic,Instance")
    $constructorCount = $constructors.Count
    foreach ($constructor in $constructors) {
        $dec = ""
        if ( $constructor.IsPublic ) { $dec += "    public " }
        elseif ( $constructor.IsFamily ) { $dec += "    protected " }
        elseif ( ! $constructor.IsFamily -and ! $constructor.IsPublic ) { $constructorCount--; continue } # don't emit

        $name = $t.Name -replace "``.*"
        $params = GetParams $constructor
        $dec += $name 
        $dec += "("
        $dec += $params
        $dec += ") { }"
        $dec

        <#
        $params = $constructor.GetParameters()
        if ( $params.Count -eq 0 ) {
            $dec += $Name + "()"
        }
        else {
            $dec +=  $Name + "("
            $par = @()
            foreach( $param in $params ) {
                $par += "{0} {1}" -f (Get-TypeNickname $param.parametertype.FullName), $param.name
            }
            $dec += $par -join ", "
            $dec += ")"
        }
        $dec += "{ }"
        $dec -join " "
        #>
    }
    if ( $constructorCount -gt 0 ) { "" }
}

function GetParams ( $method )
{
    $parm = @()
    foreach($p in $method.GetParameters()) {
        $paramType = $p.parametertype.FullName
        if ( ! $paramType ) { $paramType = $p.parametertype.Name }
        $pTypeName = Get-TypeNickname $paramType
        if ( $pTypeName -match "&$" ) { $pTypeName = $pTypeName.TrimEnd("&"); $isOut = "out " } else { $isOut = "" }
        if ( $p.ParameterType.IsGenericType )
        {
            $pTypeName += "<" + ($p.ParameterType.GenericTypeArguments -join ",") + ">"
        }
        $parm += "${isout}{0} {1}" -f $pTypeName,$p.name
    }
    return ($parm -join ", ")
}

function GetDefaultReturn ( $method ) {
    if ( $method.ReturnType.Name -ne "void" ) {
        if ( $method.ReturnType.IsGenericType ) {
            "return default(" + ($method.ReturnType.ToString() -replace "``.*") + ");" 
        }
        else {
            "return default(" + ( Get-TypeNickname $method.ReturnType.FullName ) + ");"
        }
    }
}

function Get-NestedTypes ( $t ) {
    $t.GetNestedTypes("Public,Instance,Static")
}

function EmitMethods ( $t )
{
    $methods = $t.GetMethods("Instance,Static,NonPublic,Public,DeclaredOnly") | sort-object name
    $methodCount = $methods.Count
    foreach ( $method in $methods ) {
        if ( $method.name -cmatch "^[gs]et_|^add_|^remove_" ) { $methodCount--; continue }
        $sig = @()
        if ( $method.IsFamilyOrAssembly ) {
            $sig += "    protected internal"
        }
        elseif ( $method.IsPublic ) {
            $sig += "    public"
        }
        elseif ( $method.IsVirtual -and $method.IsFamily ) {
            $sig += "    protected"
        }
        else {
            $methodCount--
            continue; # don't emit
        }
        if ( $method.IsVirtual ) { 
            if ( $t.IsAbstract ) {
                $sig += "virtual" 
            }
            else {
                $sig += "override" 
            }
        }
        if ( $method.IsStatic ) { $sig += "static" }
        $sig += Get-TypeNickname (GetTypeName $method.ReturnType) # .FullName
        $sig += $method.Name + "("
        $sig += GetParams $method
        $sig += ") {"
        $sig += GetDefaultReturn $method
        $sig += "}"
        $sig -join " "
    }
    if ( $methodCount -gt 0 ) { "" }


}

function EmitEvents ( $t )
{
    $events = $t.GetEvents("Instance,Static,NonPublic,Public,DeclaredOnly") | sort-object name
    $isAbstract = $t.IsAbstract
    foreach ( $event in $events ) {
        $eventString = ""
        $eventString = "    public"
        if ( $t.IsAbstract ) { $eventString += " abstract" }
        elseif ( $t.IsStatic ) { $eventString += " static" }
        $eventString += " event"
        $eventString += " " + $event.EventHandlerType.ToString() -replace "``.\[","<" -replace "\]",">"
        $eventString += " " + $event.Name
        $eventString += " { add { } remove { } }"
        $eventString
    }
    if ( $events.Count -gt 0 ) { "" }
}

if ( $assembly.GetType().FullName -ne "System.Reflection.RuntimeAssembly" )
{
    throw "'$AssemblyName' is not a runtime assembly"
}

function GetBaseType ( $type )
{
    $BaseType = $type.BaseType.FullName
    if ( $type.isClass -and $type.isgenerictypedefinition ) { 
        $ttype = $type.GetGenericArguments().Name

        return "where ${ttype} : class" 
    }
    switch ( $BaseType ) {
        "System.Object" { return }
        "System.Enum" { return }
        default { return ": $BaseType" }
    }
}

function Get-TypeAttribute
{
    param ( [Type]$t )
    #[string[]]$t.CustomAttributes | %{ "   $_" }
    #$attrs = $t.GetCustomAttributes($false)
    $attrs = $t.CustomAttributes
    foreach ( $attr in $attrs )
    {
        #switch ( $attr.TypeId )
        switch ( $attr.AttributeType.FullName )
        {
            "System.Management.Automation.ParameterAttribute" {
            }
            "System.Management.Automation.CmdletAttribute" {
                "   {0}`n" -f [string]$attr
                #"   [{0}(""{1}"",""{2}"")]`n" -f $_,$attr.VerbName,$attr.NounName
            }
            "System.AttributeUsageAttribute" {
                "   ${attr}`n"
            }
            "System.CodeDom.Compiler.GeneratedCodeAttribute" {
                "   ${attr}`n"
            }
            "System.ComponentModel.TypeConverterAttribute" {
                "   ${attr}`n"
            }
            "System.ComponentModel.TypeDescriptionProviderAttribute" {
                "   ${attr}`n"
            }
            "System.Diagnostics.DebuggerDisplayAttribute" {
                "   ${attr}`n"
            }
            "System.FlagsAttribute" {
                "   ${attr}`n"
            }
            "System.Management.Automation.OutputTypeAttribute" {
                #"   [$_(new {0}{{{1}}},{2})]`n" -f $attr.ConstructorArguments.ArgumentType,($attr.ConstructorArguments.Value -join ", "), ($attr.NamedArguments -join ", ")
                "  ${attr}`n"
            }
            "System.Management.Automation.Provider.CmdletProviderAttribute" {
                "   ${attr}`n"
            }
            "System.Reflection.DefaultMemberAttribute" {
                "   ${attr}`n"
            }
            "System.Runtime.CompilerServices.ExtensionAttribute" {
                "   ${attr}`n"
            }
            "System.Runtime.Serialization.DataContractAttribute" {
                "   {0}`n" -f (${attr} -replace "\(\)")
            }
            "System.SerializableAttribute" {
                "   ${attr}`n"
            }
            "System.Xml.Serialization.XmlTypeAttribute" {
                "   ${attr}`n"
            }
            default: {
                "DEFAULT ${attr}`n"
            }
        }
    }
}



Get-Exclusions $ExclusionFile


$Types = $assembly.GetTypes() |?{$_.IsPublic}
$NamespaceTypes = $Types | Group-Object Namespace 
foreach ( $g in $NamespaceTypes ) {
    if ( $ExcludedItems.namespace -contains $g.Name ) { Write-Warning ("Skipping "+ $g.Name); continue }
    # if ( $g.Name -ne "Microsoft.PowerShell.Cmdletization" ) { continue }
    Write-Progress -Id 0 $g.Name
    $script:namespace = $g.Name
    "namespace {0} {{" -f $g.Name
    foreach ( $t in $g.Group | sort-object Name) {
        Write-Progress -Parent 0 -Id 1 $t
        $typeName = GetTypeName $t # which includes generics
        $dec = @()
        $dec += Get-TypeAttribute $t
        $dec += "  public"
        $dec += IsAbstract $t
        $dec += IsStaticClass $t
        $dec += IsSealedClass $t
        $dec += GetTypeType $t
        $dec += $typeName
        $dec += GetBaseType $t
        $dec += "{"
        $typetype = GetTypeType $t
        # "  public {0} {1} {2} {{" -f (IsStaticClass $t), (GetTypeType $t), $t.Name
        switch ( $typetype ) {
            "enum" {
                $dec -join " "
                EmitEnum $t
                "  }"
                break
            }
            # handle interface!!!!
            "class" {
                $script:CurrentClass = $typeName
                if ( Exclude-Class $typeName ) { continue }
                #if ( $typeName -eq "VerbsOther" ) { wait-debugger }
                $dec -join " "
                EmitConstants $t
                EmitConstructors $t
                EmitEvents $t
                EmitProperties $t
                EmitMethods $t
                "  }"
                break
            }
            default {
                break
            }
        }
        ""
    }
    "}"
    # ONLY DO ONE FOR TESTING
}
