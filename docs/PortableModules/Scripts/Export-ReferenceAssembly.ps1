param ( [string]$AssemblyName = "System.Management.Automation" )
$assembly = [appdomain]::CurrentDomain.GetAssemblies() | ?{$_.Location -match $AssemblyName}

$TypeTranslation = @{
    "System.Object" = "object"
    "System.Boolean" = "bool"
    "System.UInt32" = "uint"
    "System.String" = "string"
    "System.Int32" = "int"
    "System.Void" = "void"
}

function GetTypeName ( $type )
{
    if ( $type.IsGenericTypeDefinition ) {
        "{0}<{1}>" -f ($type.name -replace "``.*"),($type.GenericTypeParameters.Name -join ",")
    }
    else {
        $type.name
    }
}

function Get-TypeNickname ( [string]$typename )
{
    $typename = $typename -replace "``.*"
    $v = $TypeTranslation["$typename"]
    if ( $v ) { return $v } else { return $typename }
}

function IsStaticClass ( $Type )
{
    if ( $Type.IsAbstract -and $Type.IsSealed ) { "static" }
}

function IsSealedClass ( $Type ) {
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

function EmitProperties ( $t )
{
    foreach ( $Property in $t.GetProperties("Static,Instance,Public")| sort-object Name)
    {
        if ( $Property.PropertyType.IsGenericType ) {
            #wait-debugger
            $propertyArgs = $property.propertytype.GenericTypeArguments | %{ $a = @()}{$a += Get-TypeNickName $_.fullname}{$a -join ","}
            $propertyType = $property.propertytype.fullname -replace "``.*"
            $propertyString = "{0}<{1}>" -f $propertyType,$propertyArgs
        }
        else {
            $propertyString = Get-TypeNickName $property.propertytype.fullname
        }
        $dec = "    public {0} {1} {{" -f $propertyString,$property.name
        if ( $property.GetMethod ) { $dec += " get { return default($propertyString); }" }
        if ( $property.SetMethod ) { $dec += " set { }" }
        $dec += " }" 
        $dec
    }
}

function EmitConstructors ( $t )
{
    foreach ( $constructor in $t.GetConstructors("Public,NonPublic,Instance")) {
        $dec = @()
        if ( $constructor.IsPublic ) { $dec += "    public" }
        elseif ( $constructor.IsFamily ) { $dec += "    protected" }
        $params = $constructor.GetParameters()
        $name = $t.Name -replace "``.*"
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
    }
}

function GetParams ( $method )
{
    $parm = @()
    foreach($p in $method.GetParameters()) {
        $parm += "{0} {1}" -f (Get-TypeNickname $p.parametertype.FullName),$p.name
    }
    return ($parm -join ", ")
}

function GetDefaultReturn ( $method ) {
    if ( $method.ReturnType.Name -ne "void" ) {
        "return default(" + ( Get-TypeNickname $method.ReturnType.FullName ) + ");"
    }
}

function Get-NestedTypes ( $t ) {
    $t.GetNestedTypes("Public,Instance,Static")
}

function EmitMethods ( $t )
{
    $methods = $t.GetMethods("Instance,Static,NonPublic,Public,DeclaredOnly") | sort-object name
    foreach ( $method in $methods ) {
        if ( $method.name -cmatch "^[gs]et_" ) { continue }
        $sig = @()
        if ( $method.IsFamilyOrAssembly ) {
            $sig += "    protected internal"
        }
        elseif ( $method.IsPublic ) {
            $sig += "    public"
        }
        else {
            continue;
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
        $sig += Get-TypeNickname $method.ReturnType.FullName
        $sig += $method.Name + "("
        $sig += GetParams $method
        $sig += ") {"
        $sig += GetDefaultReturn $method
        $sig += "}"
        $sig -join " "
    }
    
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

$Types = $assembly.GetTypes() |?{$_.IsPublic}
$NamespaceTypes = $Types | Group-Object Namespace 
foreach ( $g in $NamespaceTypes ) {
    if ( $g.Name -ne "Microsoft.PowerShell.Cmdletization" ) { continue }
    "namespace {0} {{" -f $g.Name
    foreach ( $t in $g.Group | sort-object Name) {
        $dec = @()
        $dec += "  public"
        $dec += IsAbstract $t
        $dec += IsStaticClass $t
        $dec += IsSealedClass $t
        $dec += GetTypeType $t
        $dec += GetTypeName $t # which includes generics
        $dec += GetBaseType $t
        $dec += "{"
        $typetype = GetTypeType $t
        # "  public {0} {1} {2} {{" -f (IsStaticClass $t), (GetTypeType $t), $t.Name
        $dec -join " "
        switch ( $typetype ) {
            "enum" {
                EmitEnum $t
                break
            }
            "class" {
                EmitConstructors $t
                ""
                EmitProperties $t
                ""
                EmitMethods $t
            }
            default {
                break
            }
        }
        "  }"
    }
    "}"
    # ONLY DO ONE FOR TESTING
    break
}
