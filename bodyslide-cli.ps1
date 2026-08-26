[CmdletBinding(PositionalBinding = $false)]
param([Parameter(ValueFromRemainingArguments = $true)][string[]] $CliArgs)

$ErrorActionPreference = 'Stop'
$script:ExitUsage = 2
$script:ExitData = 3
$script:ExitEngine = 4

function Show-Help {
@'
BodySlide CLI - CMD frontend for BodySlide and Outfit Studio

USAGE
  bodyslide-cli help
  bodyslide-cli doctor [--app-dir PATH] [--engine PATH]
  bodyslide-cli list outfits|groups|presets [--app-dir PATH] [--filter TEXT] [--json]
  bodyslide-cli build (--outfit NAME ... | --group NAME ... | --filter TEXT)
                      [--preset NAME_OR_XML] [--target-dir PATH] [--tri]
                      [--regex] [--app-dir PATH] [--engine PATH] [--dry-run]

EXAMPLES
  bodyslide-cli list outfits --app-dir "D:\MO2\mods\BodySlide\CalienteTools\BodySlide"
  bodyslide-cli build --outfit "CBBE Body" --preset "CBBE Curvy" --tri --target-dir "D:\output"
  bodyslide-cli build --group "CBBE" --filter armor --preset "CBBE Curvy"

NOTES
  --app-dir must be the CalienteTools\BodySlide folder containing SliderSets.
  Build uses the upstream engine's native command-line build mode. Outfit names
  can be repeated; group and filter selections may be combined.
'@
}

function Fail([string] $Message, [int] $Code = 1) {
    [Console]::Error.WriteLine("ERROR: $Message")
    exit $Code
}

function Parse-Options([string[]] $InputArgs) {
    $result = [ordered]@{ Positionals = [Collections.Generic.List[string]]::new() }
    $multi = @('outfit', 'group')
    for ($i = 0; $i -lt $InputArgs.Count; $i++) {
        $token = $InputArgs[$i]
        if (-not $token.StartsWith('--')) {
            $result.Positionals.Add($token)
            continue
        }
        $name = $token.Substring(2).ToLowerInvariant()
        if ($name -in @('tri','regex','json','dry-run')) {
            $result[$name] = $true
            continue
        }
        if ($name -notin @('app-dir','engine','filter','preset','target-dir','outfit','group')) {
            Fail "Unknown option: $token" $script:ExitUsage
        }
        if ($i + 1 -ge $InputArgs.Count) { Fail "Missing value after $token" $script:ExitUsage }
        $i++
        if ($name -in $multi) {
            if (-not $result.Contains($name)) { $result[$name] = [Collections.Generic.List[string]]::new() }
            $result[$name].Add($InputArgs[$i])
        } else {
            $result[$name] = $InputArgs[$i]
        }
    }
    return $result
}

function Resolve-AppDir($Options, [bool] $Required = $true) {
    $candidates = [Collections.Generic.List[string]]::new()
    if ($Options.Contains('app-dir')) { $candidates.Add($Options['app-dir']) }
    if ($env:BODYSLIDE_APP_DIR) { $candidates.Add($env:BODYSLIDE_APP_DIR) }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    if ($Required) { Fail 'BodySlide app directory not found. Pass --app-dir PATH or set BODYSLIDE_APP_DIR.' $script:ExitData }
    return $null
}

function Resolve-Engine($Options, [string] $AppDir) {
    $candidates = [Collections.Generic.List[string]]::new()
    if ($Options.Contains('engine')) { $candidates.Add($Options['engine']) }
    if ($env:BODYSLIDE_ENGINE) { $candidates.Add($env:BODYSLIDE_ENGINE) }
    $candidates.Add((Join-Path $PSScriptRoot 'dist\engine\BodySlideCLI-engine.exe'))
    foreach ($name in @('BodySlide x64.exe','BodySlide.exe','BodySlideCLI-engine.exe')) {
        $candidates.Add((Join-Path $AppDir $name))
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-XmlFiles([string] $Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Directory -File -Recurse | Where-Object { $_.Extension -in @('.xml','.osp') })
}

function Read-NamedNodes([IO.FileInfo[]] $Files, [string] $Kind) {
    $items = [Collections.Generic.List[object]]::new()
    foreach ($file in $Files) {
        try {
            [xml] $doc = Get-Content -LiteralPath $file.FullName -Raw
            $nodes = switch ($Kind) {
                'outfits' { @($doc.SelectNodes('//SliderSet')) }
                'groups'  { @($doc.SelectNodes('//Group')) }
                'presets' { @($doc.SelectNodes('//Preset')) }
            }
            foreach ($node in $nodes) {
                $name = switch ($Kind) {
                    'outfits' { if ($node.name) { $node.name } elseif ($node.SetName) { $node.SetName } else { $node.GetAttribute('name') } }
                    default { $node.GetAttribute('name') }
                }
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $items.Add([pscustomobject]@{ name = [string]$name; file = $file.FullName })
                }
            }
        } catch {
            [Console]::Error.WriteLine("WARNING: Could not parse '$($file.FullName)': $($_.Exception.Message)")
        }
    }
    return @($items | Sort-Object name,file -Unique)
}

function Invoke-List([string] $Kind, $Options) {
    if ($Kind -notin @('outfits','groups','presets')) { Fail 'list requires outfits, groups, or presets.' $script:ExitUsage }
    $appDir = Resolve-AppDir $Options
    $subdir = switch ($Kind) { 'outfits' {'SliderSets'} 'groups' {'SliderGroups'} 'presets' {'SliderPresets'} }
    $dir = Join-Path $appDir $subdir
    $items = Read-NamedNodes (Get-XmlFiles $dir) $Kind
    if ($Options.Contains('filter')) { $needle = $Options['filter']; $items = @($items | Where-Object name -Like "*$needle*") }
    if ($Options.Contains('json')) { $items | ConvertTo-Json -Depth 3 } else { $items | ForEach-Object { $_.name } }
    [Console]::Error.WriteLine("$($items.Count) $Kind found in $dir")
}

function Invoke-Doctor($Options) {
    $appDir = Resolve-AppDir $Options $false
    $problems = 0
    Write-Output "BodySlide CLI: $PSScriptRoot"
    if (-not $appDir) { Write-Output 'App directory: NOT FOUND'; $problems++ }
    else {
        Write-Output "App directory: $appDir"
        foreach ($name in @('SliderSets','SliderGroups','SliderPresets')) {
            $path = Join-Path $appDir $name
            $count = @(Get-XmlFiles $path).Count
            Write-Output ("{0}: {1} file(s)" -f $name,$count)
            if ($name -eq 'SliderSets' -and $count -eq 0) { $problems++ }
        }
        $engine = Resolve-Engine $Options $appDir
        if ($engine) { Write-Output "Engine: $engine" } else { Write-Output 'Engine: NOT FOUND'; $problems++ }
    }
    if ($problems) { exit $script:ExitData }
    Write-Output 'Status: READY'
}

function Invoke-Build($Options) {
    if (-not $Options.Contains('outfit') -and -not $Options.Contains('group') -and -not $Options.Contains('filter')) {
        Fail 'build requires at least one --outfit, --group, or --filter.' $script:ExitUsage
    }
    $appDir = Resolve-AppDir $Options
    $engine = Resolve-Engine $Options $appDir
    if (-not $engine) { Fail "No BodySlide engine found in '$appDir'. Pass --engine PATH." $script:ExitEngine }
    $engineArgs = [Collections.Generic.List[string]]::new()
    if ([IO.Path]::GetFileName($engine) -ieq 'BodySlideCLI-engine.exe') { $engineArgs.Add('--appdir'); $engineArgs.Add($appDir) }
    if ($Options.Contains('outfit')) { $engineArgs.Add('--build'); $engineArgs.Add(($Options['outfit'] -join '|')) }
    if ($Options.Contains('group')) { $engineArgs.Add('--groupbuild'); $engineArgs.Add(($Options['group'] -join ',')) }
    if ($Options.Contains('filter')) { $engineArgs.Add('--filter'); $engineArgs.Add($Options['filter']) }
    if ($Options.Contains('regex')) { $engineArgs.Add('--regexfilter') }
    if ($Options.Contains('preset')) { $engineArgs.Add('--preset'); $engineArgs.Add($Options['preset']) }
    if ($Options.Contains('target-dir')) { $engineArgs.Add('--targetdir'); $engineArgs.Add($Options['target-dir']) }
    if ($Options.Contains('tri')) { $engineArgs.Add('--trimorphs') }
    Write-Output ('Engine: ' + $engine)
    Write-Output ('Arguments: ' + (($engineArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '))
    if ($Options.Contains('dry-run')) { Write-Output 'Dry run: no files were built.'; return }
    Push-Location $appDir
    try { & $engine @engineArgs; $code = $LASTEXITCODE } finally { Pop-Location }
    if ($null -eq $code) { $code = 0 }
    if ($code -ne 0) { Fail "BodySlide engine exited with code $code." $code }
}

try {
    if (-not $CliArgs -or $CliArgs.Count -eq 0) { Show-Help; exit $script:ExitUsage }
    $command = $CliArgs[0].ToLowerInvariant()
    $rest = if ($CliArgs.Count -gt 1) { @($CliArgs[1..($CliArgs.Count - 1)]) } else { @() }
    if ($command -in @('help','-h','--help','/?')) { Show-Help; exit 0 }
    $options = Parse-Options $rest
    switch ($command) {
        'doctor' { Invoke-Doctor $options }
        'list' {
            if ($options.Positionals.Count -ne 1) { Fail 'list requires exactly one kind: outfits, groups, or presets.' $script:ExitUsage }
            Invoke-List $options.Positionals[0].ToLowerInvariant() $options
        }
        'build' { Invoke-Build $options }
        default { Fail "Unknown command: $command" $script:ExitUsage }
    }
} catch {
    Fail $_.Exception.Message 1
}
