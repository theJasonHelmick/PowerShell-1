param ( [type]$t = [psobject])

function GetTypes ( $assembly, [string]$namespace ) {
    try {
    $assembly.GetTypes() |?{$_.ispublic}| ?{($_.namespace -eq $namespace) -and $_.IsPublic }
    }
    catch { wait-debugger }
}

function GetNamespaces ( $assembly ) {
    $assembly.GetTypes() | ?{$_.ispublic}|%{ $h = @{}} { if (! $h[$_.namespace] ) { $_.namespace }; $h[$_.namespace]++} | sort-object
}

function VisitTypes ($types) {
    foreach ($type in $types) { VisitType $type }
}

function VisitFields ( $fields ) {
    foreach ( $field in $fields ) { VisitField $field }
}

function VisitMethods ( $methods ) {
    foreach ( $method in $methods ) { VisitMethod $method }
}

function VisitProperties ( $properties ) {
    foreach ( $property in $properties ) { VisitProperty $property }
}

function VisitEvents ( $events ) {
    foreach ( $event in $events ) { VisitEvent $event }
}

function VisitField ( $f ) {
}

function VisitMethod ( $m ) {
    "    " + $m.Name
}

function VisitProperty ( $p ) {
}

function VisitEvent ( $e ) {
}

function Repair-Keyword ( $name ) 
{
    $cSharpKeywords = "abstract","as","base","bool","break","byte","case","catch","char","checked","class","const",
        "continue","decimal","default","delegate","do","double","else","enum","event","explicit","extern","false",
        "finally","fixed","float","for","foreach","goto","if","implicit","in","int","interface","internal","is",
        "lock","long","namespace","new","null","object","operator","out","override","params","private","protected",
        "public","readonly","ref","return","sbyte","sealed","short","sizeof","stackalloc","static","string","struct",
        "switch","this","throw","true","try","typeof","uint","ulong","unchecked","unsafe","ushort","using","virtual",
        "void","volatile","while"
    if ( $cSharpKeywords -contains $name ) { return "@${name}" } else { return "${name}" }
}

function VisitAttribute ( $attribute ) { }

function EmitAttributes ( $t )
{
    foreach ( $attribute in $t.GetCustomAttributes($false) ) { VisitAttribute $attribute }
}
function GetTypeString ( $t ) {
    if ( $t.IsInterface ) { return "interface" }
    elseif ( $t.IsClass ) { return "class" }
    elseif ( $t.IsEnum -and $type.IsValueType ) { return "enum" }
    elseif ( ! $t.IsEnum -and $type.IsValueType ) { return "struct" }
    else { wait-debugger }
}
# show the type data - name, attributes, etc
function GetName ( $t ) { 
    if ( $t.IsGenericType ) {
        $str = $t.Name -replace "``1"
        $str
    }
    else {
        $t.Name 
    }
} # handles generics
function GetBaseClass ( $t ) { } # handles generics
function GetConstraints ( $t ) { } # handles generics

function EmitEnum ( $t ) {
    $enumName = $t.Name
    $a = @()
    #$attr = "  [System.Runtime.InteropServices.LayoutKind.StructLayoutAttribute"
    #if ( $t.IsLayoutSequential ) { $a += "System.Runtime.InteropServices.LayoutKind.Sequential" }
    #$attr += if ( $a.Count -gt 0 ) { "(" + ($a -join ",") + ")]" } else { "]" }
    #$attr
    $fmt = "  public enum {0}"
    $underlyingTypeName = [enum]::GetUnderlyingType($t).Name
    if ( $underlyingTypeName -ne "Int32" ) { $fmt += " : {1}" } else { $underlyingTypeName = $null }
    $fmt += " {{"
    $fmt -f $enumName,$underlyingTypeName
    $names = [enum]::GetNames($t) | sort-object 
    foreach ( $name in $names ) { "    ${name} = {0}," -f ($t::"${name}").value__ }
    "  }"
}

function GetImplementedInterfaces ( $t ) {
    if ( ! $t.ImplementedInterfaces ) { return }
    " : " + ( $t.ImplementedInterfaces.FullName -join ", ")
}

function EmitInterface ( $t ) {
    $dec = "  public partial interface {0}" -f $t.Name
    $dec += GetImplementedInterfaces $t
    $dec += " {"
    $dec
    VisitMethods ($t.GetMethods("Public,Instance,Static,DeclaredOnly"))

}

function ShowTypeData ( $t )
{
    $typeString = GetTypeString $t
    switch ( $typeString ) {
        "enum" { EmitEnum $t; return }
        "interface" { EmitInterface $t; return }
        default { break }
    }
    
    EmitAttributes $t
    $dec = "  "
    $dec += if ( $t.IsPublic -or $t.IsNestedPublic ) { "public " } elseif ( $t.IsNestedAssembly ) { "internal " } elseif ( $t.IsNestedFamily ) { "protected " } else { "whoops: " + $t.name }
    $dec += if ( $t.IsSealed -and ! $t.IsValueType ) { "sealed " } # all value types are sealed, no need to mention it
    $dec += (GetTypeString $t) + " "
    $dec += GetName $t
    $dec += GetBaseClass $t
    $dec += GetConstraints $t
    $dec
}

function EmitType ( $t ) {
    ShowTypeData $t
    VisitFields $t.Fields
    VisitMethods ($t.GetMethods("Public,Instance,Static,DeclaredOnly") | ?{$_.IsConstructor})
    VisitProperties ($t.GetProperties("Public,Instance,Static,DeclaredOnly"))
    VisitEvents ($t.GetEvents("Public,Instance,DeclaredOnly"))
    VisitMethods ($t.GetMethods("Public,Instance,Static,DeclaredOnly") | ?{! $_.IsConstructor})
    VisitTypes ($t.GetNestedTypes()|?{$_.IsNestedPublic})
}

function VisitType ( $t ) {
    Write-Progress -id 1 -parent 0 "visiting type $t"
    if ( $t.IsNested ) { write-warning "$t is nested" }
    EmitType $t
}

function VisitAssembly ( $assembly ) {
    $namespaces = GetNamespaces $assembly 
    foreach ($namespace in $namespaces) {
        Write-Progress -id 0 "visit namespace $namespace"
        VisitNamespace -assembly $assembly -namespace $namespace
    }
}

function VisitNamespace ( $assembly, $namespace ) {
    $types = (GetTypes -assembly $assembly -namespace $namespace)
    VisitTypes $types
}

#wait-debugger
$assembly = $t.assembly
VisitAssembly -assembly $assembly
