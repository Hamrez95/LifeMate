[CmdletBinding()]
param(
  [string]$App,
  [switch]$All,
  [switch]$List,
  [switch]$Health,
  [switch]$Run,
  [ValidateSet('Debug','Release')][string]$Build,
  [ValidateSet('APK','AAB')][string]$Format = 'APK',
  [switch]$Install,
  [switch]$Release,
  [ValidateSet('patch','minor','major')][string]$Bump = 'patch',
  [string]$Version,
  [switch]$DispatchWorkflow,
  [ValidateSet('Android','Chrome')][string]$Target = 'Android',
  [ValidateSet('dev','staging','production','internal')][string]$Environment = 'dev',
  [switch]$Clean,
  [switch]$OpenArtifacts,
  [switch]$Logs,
  [switch]$NoOpen,
  [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Script:ConfigPath = Join-Path $PSScriptRoot 'lifemate.apps.json'
$Script:Interactive = -not $NonInteractive -and -not ($List -or $Health -or $Run -or $Build -or $Install -or $Release -or $DispatchWorkflow -or $Clean -or $OpenArtifacts -or $Logs)
$Script:NoColor = $NonInteractive -or [Console]::IsOutputRedirected
$Script:ReportRoot = Join-Path $Script:Root 'artifacts\_reports'

function Write-Ui([string]$Message, [ValidateSet('Info','Success','Warn','Error','Step')][string]$Kind = 'Info') {
  $prefix = @{ Info='[i]'; Success='[ok]'; Warn='[!]'; Error='[x]'; Step='[>]'}[$Kind]
  if ($Script:NoColor) { Write-Host "$prefix $Message"; return }
  $color = @{ Info='Cyan'; Success='Green'; Warn='Yellow'; Error='Red'; Step='Magenta'}[$Kind]
  Write-Host "$prefix $Message" -ForegroundColor $color
}
function Write-Title([string]$Text) { if (-not $Script:NoColor) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan } else { Write-Host "`n=== $Text ===" } }
function Invoke-External([string]$File, [string[]]$Arguments, [string]$WorkingDirectory = $Script:Root) {
  Write-Ui "Running: $File $($Arguments -join ' ')" Step
  Push-Location $WorkingDirectory
  try { & $File @Arguments; if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE." } }
  finally { Pop-Location }
}
function Get-CommandPath([string]$Name) { $c = Get-Command $Name -ErrorAction SilentlyContinue; if ($c) { $c.Source } }
function Test-Tool([string]$Name) { [bool](Get-CommandPath $Name) }
function Get-Config { if (-not (Test-Path $Script:ConfigPath)) { throw "Missing configuration: $Script:ConfigPath" }; Get-Content $Script:ConfigPath -Raw | ConvertFrom-Json }
function Get-PubspecVersion([object]$Item) {
  $path = Join-Path (Join-Path $Script:Root $Item.path) $Item.versionFile
  $match = Select-String -Path $path -Pattern '^version:\s*(.+)$' | Select-Object -First 1
  if (-not $match) { return 'unknown' }; $match.Matches[0].Groups[1].Value.Trim()
}
function Get-Apps {
  $config = Get-Config; $items = @()
  foreach ($property in $config.apps.psobject.Properties) {
    $item = $property.Value; $item | Add-Member -NotePropertyName Name -NotePropertyValue $property.Name -Force
    $item | Add-Member -NotePropertyName Exists -NotePropertyValue (Test-Path (Join-Path $Script:Root $item.path)) -Force
    $item | Add-Member -NotePropertyName Version -NotePropertyValue $(if ($item.Exists) { Get-PubspecVersion $item } else { 'missing' }) -Force
    $items += $item
  }
  # Discovery deliberately reports unconfigured Flutter hosts, but does not guess build commands for them.
  $known = @($items | ForEach-Object path)
  Get-ChildItem $Script:Root -Recurse -Filter pubspec.yaml -File | Where-Object { $_.FullName -notmatch '[\\/]sources[\\/]' } | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($Script:Root, $_.DirectoryName).Replace('\','/')
    if ($relative -notin $known -and (Test-Path (Join-Path $_.DirectoryName 'lib')) -and (Test-Path (Join-Path $_.DirectoryName 'android'))) {
      $items += [pscustomobject]@{ Name=$relative.Replace('/','-'); path=$relative; technology='Flutter (discovered; configure first)'; versionFile='pubspec.yaml'; Exists=$true; Version=((Select-String -Path $_.FullName -Pattern '^version:\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value.Trim()); android=$true; formats=@(); tagPrefix="$($relative.Replace('/','-'))-v"; buildNumberStrategy='Unconfigured'; workflow=$null }
    }
  }
  $items
}
function Get-SelectedApps {
  $apps = Get-Apps
  if ($All) { return @($apps | Where-Object { $_.technology -eq 'Flutter' }) }
  if ($App) { $found = @($apps | Where-Object Name -eq $App); if (!$found) { throw "Unknown app '$App'. Use -List to see available apps." }; return $found }
  if ($Script:Interactive) { return Select-AppsInteractive $apps }
  throw 'Specify -App <name> or -All.'
}
function Get-Git([string[]]$Arguments) { (& git -C $Script:Root @Arguments 2>$null) }
function Get-GitState {
  if (-not (Test-Tool git)) { return [pscustomobject]@{ Available=$false } }
  $branch = (Get-Git @('branch','--show-current')).Trim(); $status = @(Get-Git @('status','--porcelain')); $upstream = (Get-Git @('rev-parse','--abbrev-ref','--symbolic-full-name','@{upstream}')).Trim()
  $ahead = 0; $behind = 0
  if ($upstream) { $counts = (Get-Git @('rev-list','--left-right','--count',"HEAD...$upstream")).Trim().Split("`t ", [StringSplitOptions]::RemoveEmptyEntries); if ($counts.Count -eq 2) { $ahead=[int]$counts[0]; $behind=[int]$counts[1] } }
  [pscustomobject]@{ Available=$true; Branch=$branch; Dirty=($status.Count -gt 0); Changes=$status.Count; Upstream=$upstream; Ahead=$ahead; Behind=$behind }
}
function Get-Devices {
  if (-not (Test-Tool adb)) { return @() }
  @(& adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '\S+\s+(device|offline|unauthorized)' } | ForEach-Object { $p=$_.Trim() -split '\s+'; [pscustomobject]@{ Id=$p[0]; Status=$p[1] } })
}
function Get-LastTag([object]$Item) {
  if (-not (Test-Tool git)) { return 'Git unavailable' }
  $tags = @((Get-Git @('ls-remote','--tags','--refs','origin',"$($Item.tagPrefix)*")) | ForEach-Object {
    if ($_ -match 'refs/tags/(.+)$') {
      $tag = $Matches[1]
      $suffix = $tag.Substring($Item.tagPrefix.Length)
      if ($suffix -match '^(\d+)\.(\d+)\.(\d+)(.*)$') {
        [pscustomobject]@{ Tag=$tag; Major=[int]$Matches[1]; Minor=[int]$Matches[2]; Patch=[int]$Matches[3]; Stable=([string]::IsNullOrEmpty($Matches[4])) }
      }
    }
  } | Where-Object { $_ })
  if ($tags.Count) { return ($tags | Sort-Object Major,Minor,Patch,Stable -Descending | Select-Object -First 1).Tag }
  'none'
}
function Show-Apps {
  Write-Title 'Apps'
  $apps=Get-Apps; $apps | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Path=$_.path; Technology=$_.technology; Version=$_.Version; Android=$(if($_.android){'Yes'}else{'No'}); Prerequisite=$(if(Test-Tool flutter){'Flutter ready'}else{'Flutter missing'}); LastTag=(Get-LastTag $_) } } | Format-Table -AutoSize
}
function Show-Health {
  Write-Title 'Project Health'
  $state=Get-GitState
  if ($state.Available) { [pscustomobject]@{ Branch=$state.Branch; WorkingTree=$(if($state.Dirty){"Dirty ($($state.Changes) changes)"}else{'Clean'}); Upstream=$state.Upstream; Ahead=$state.Ahead; Behind=$state.Behind } | Format-List } else { Write-Ui 'Git is required: install Git for Windows.' Error }
  $tools=@('git','gh','java','flutter','node','adb','sdkmanager') | ForEach-Object { [pscustomobject]@{ Tool=$_; Status=$(if(Test-Tool $_){'Available'}else{'Missing'}); Path=(Get-CommandPath $_) } }; $tools | Format-Table -AutoSize
  $sdk = if($env:ANDROID_SDK_ROOT){$env:ANDROID_SDK_ROOT}elseif($env:ANDROID_HOME){$env:ANDROID_HOME}else{'Not configured'}; Write-Host "Android SDK: $sdk"
  $devices=@(Get-Devices); if($devices.Count){$devices|Format-Table -AutoSize}else{Write-Ui 'No Android device/emulator found. Start one or connect a device, then accept its adb authorization.' Warn}
  Get-Apps | ForEach-Object { [pscustomobject]@{App=$_.Name; LastRemoteTag=(Get-LastTag $_); Workflow=$_.workflow} } | Format-Table -AutoSize
  if (Test-Tool gh) { $auth = & gh auth status 2>&1; if ($LASTEXITCODE -eq 0) { Write-Ui 'GitHub CLI is authenticated.' Success; foreach($item in Get-Apps | Where-Object workflow) { $run=& gh run list --workflow $item.workflow --limit 1 --json status,conclusion,url,displayTitle 2>$null | ConvertFrom-Json; if($run){$run|Select-Object @{N='App';E={$item.Name}},status,conclusion,url|Format-Table -AutoSize} } } else { Write-Ui 'GitHub CLI is installed but not logged in. Run: gh auth login' Warn } } else { Write-Ui 'GitHub Actions status needs GitHub CLI (gh); it is not installed.' Warn }
}
function Assert-Flutter([object]$Item, [switch]$RequireAndroid) { if (-not (Test-Tool flutter)) { throw 'Flutter is not available. Install the version pinned by CI (3.44.0) and add it to PATH.' }; if ($RequireAndroid -and -not $Item.android) { throw "Android is not configured for $($Item.Name)." } }
function Get-BuildNumber([object]$Item) { if ($Item.buildNumberStrategy -eq 'GitCommitCount') { return [int](Get-Git @('rev-list','--count','HEAD')).Trim() }; throw "This app uses $($Item.buildNumberStrategy) in CI. The local tool will not invent a release build number; use -DispatchWorkflow." }
function Prepare-App([object]$Item) {
  Assert-Flutter $Item -RequireAndroid:($Target -eq 'Android')
  if ($Item.requiresGeneratedAndroid -and $Target -eq 'Android') {
    if (-not (Test-Tool bash)) { throw "CocoonMate Android preparation requires Git Bash (bash). Install Git for Windows with Git Bash, then retry." }
    foreach ($name in @('SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY','LIFEMATE_API_BASE_URL')) { if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { throw "CocoonMate Android preparation requires public runtime variable $name. Set it in your current session; the console will not guess service endpoints." } }
    Write-Ui "Preparing CocoonMate's generated Android host using $($Item.prepareScript)." Step
    $oldEnvironment = $env:LIFEMATE_RELEASE_ENVIRONMENT; $env:LIFEMATE_RELEASE_ENVIRONMENT = if ($Environment -eq 'production') { 'production' } else { 'nonproduction' }
    try { Invoke-External 'bash' @($Item.prepareScript,'prepare') $Script:Root } finally { $env:LIFEMATE_RELEASE_ENVIRONMENT = $oldEnvironment }
  }
  Invoke-External 'flutter' @('pub','get') (Join-Path $Script:Root $Item.path)
}
function Copy-Artifact([object]$Item,[string]$BuildType,[string]$ArtifactFormat,[string]$Source,[int]$BuildNumber) {
  if (-not (Test-Path $Source)) { throw "Expected output was not found: $Source" }; $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'; $safeVersion=($Item.Version -replace '[^0-9A-Za-z._-]','_'); $destination=Join-Path $Script:Root "artifacts\$($Item.Name)\$safeVersion"; New-Item -ItemType Directory -Path $destination -Force | Out-Null
  $file="$($Item.Name)-v$safeVersion+$BuildNumber-$($BuildType.ToLowerInvariant())-$stamp.$($ArtifactFormat.ToLowerInvariant())"; $target=Join-Path $destination $file; Copy-Item $Source $target -Force
  $report=[pscustomobject]@{app=$Item.Name; version=$Item.Version; buildNumber=$BuildNumber; buildType=$BuildType; format=$ArtifactFormat; environment=$Environment; builtAt=(Get-Date).ToString('o'); artifact=$target}; New-Item -ItemType Directory -Path $Script:ReportRoot -Force | Out-Null; $report | ConvertTo-Json | Add-Content (Join-Path $Script:ReportRoot 'build-history.jsonl'); return $report
}
function Build-App([object]$Item,[string]$BuildType,[string]$ArtifactFormat) {
  Prepare-App $Item; $number=Get-BuildNumber $Item; $mode=$BuildType.ToLowerInvariant(); $args=@('build',$(if($ArtifactFormat -eq 'AAB'){'appbundle'}else{'apk'}),"--$mode","--build-name=$($Item.Version.Split('+')[0])","--build-number=$number")
  Write-Ui "Building $($Item.Name) ($BuildType / $ArtifactFormat). This repository has no app-local dev/staging/production mapping, so no runtime environment variables are injected." Step
  $started=Get-Date; Invoke-External 'flutter' $args (Join-Path $Script:Root $Item.path)
  $source=if($ArtifactFormat -eq 'AAB'){Join-Path $Script:Root "$($Item.path)\build\app\outputs\bundle\release\app-release.aab"}else{Join-Path $Script:Root "$($Item.path)\build\app\outputs\flutter-apk\app-$mode.apk"}; $report=Copy-Artifact $Item $BuildType $ArtifactFormat $source $number
  Write-Ui "Success: $($report.artifact) ($( [math]::Round(((Get-Date)-$started).TotalSeconds,1) )s)" Success; if(-not $NoOpen){Start-Process explorer.exe "/select,`"$($report.artifact)`""}; $report
}
function Select-Device { $devices=@(Get-Devices|Where-Object Status -eq 'device'); if(!$devices){throw 'No authorized Android device found. Connect one, enable USB debugging, then run adb devices.'}; if($devices.Count -eq 1 -or $NonInteractive){return $devices[0]}; $devices|Format-Table -AutoSize; $n=Read-Host 'Device number'; if($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt $devices.Count){throw 'Invalid device selection.'}; $devices[[int]$n-1] }
function Run-App([object]$Item) {
  Prepare-App $Item
  if ($Target -eq 'Chrome') { Write-Ui "Launching $($Item.Name) in Chrome." Step; Invoke-External 'flutter' @('run','-d','chrome') (Join-Path $Script:Root $Item.path); return }
  $device=Select-Device; Write-Ui "Launching $($Item.Name) on $($device.Id)." Step; Invoke-External 'flutter' @('run','-d',$device.Id) (Join-Path $Script:Root $Item.path)
}
function Install-App([object]$Item) { $device=Select-Device; $candidate=Get-ChildItem (Join-Path $Script:Root "artifacts\$($Item.Name)") -Recurse -Filter '*.apk' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if(!$candidate){throw "No managed APK found for $($Item.Name). Build one first."}; Invoke-External 'adb' @('-s',$device.Id,'install','-r',$candidate.FullName); Write-Ui "Installed $($candidate.Name) on $($device.Id)." Success }
function Get-NextVersion([string]$Base,[string]$Kind) { if($Base -notmatch '^(\d+)\.(\d+)\.(\d+)$'){throw "Tag version '$Base' is not a stable SemVer version."}; $a=[int]$Matches[1];$b=[int]$Matches[2];$c=[int]$Matches[3]; switch($Kind){'major'{"$($a+1).0.0"};'minor'{"$a.$($b+1).0"};default{"$a.$b.$($c+1)"}} }
function Start-Release([object]$Item) {
  if(-not(Test-Tool git)){throw 'Git is required.'}; Write-Ui 'Fetching remote branch and tags (read-only sync).' Step; Invoke-External 'git' @('-C',$Script:Root,'fetch','origin','--tags','--prune')
  $state=Get-GitState; if($state.Dirty){throw 'Working tree is not clean. Commit, stash, or discard your own changes before a release.'}; if($state.Behind -gt 0){throw "Local branch is $($state.Behind) commit(s) behind $($state.Upstream). Update it before a release."}
  $last=Get-LastTag $Item; $base=if($last -eq 'none'){'0.0.0'}else{$last.Substring($Item.tagPrefix.Length) -replace '-.*$',''}; $next=if($Version){$Version}else{Get-NextVersion $base $Bump}; if($next -notmatch '^\d+\.\d+\.\d+$'){throw 'Custom version must be stable SemVer: X.Y.Z.'}; $tag="$($Item.tagPrefix)$next"; $remote=& git -C $Script:Root ls-remote --tags origin "refs/tags/$tag"; if($remote){throw "Remote tag $tag already exists. Suggested next version: $(Get-NextVersion $next 'patch')"}
  Write-Title 'Release confirmation required'; Write-Host "App: $($Item.Name)`nLast remote tag: $last`nProposed version/tag: $next / $tag`nBuild number: $(Get-BuildNumber $Item)`nActions: update pubspec, test/build, commit, tag, push."; if($NonInteractive){throw 'Release is intentionally interactive; rerun without -NonInteractive to confirm.'}; if((Read-Host 'Type RELEASE to continue') -ne 'RELEASE'){Write-Ui 'Release cancelled; no files or Git state changed.' Warn;return}
  $pubspec=Join-Path (Join-Path $Script:Root $Item.path) $Item.versionFile; $content=Get-Content $pubspec -Raw; $build=Get-BuildNumber $Item; $updated=[regex]::Replace($content,'(?m)^version:\s*.+$',"version: $next+$build",1); Set-Content -Path $pubspec -Value $updated -NoNewline; try { Build-App $Item 'Release' 'APK' | Out-Null; Invoke-External 'git' @('-C',$Script:Root,'add','--',$pubspec); Invoke-External 'git' @('-C',$Script:Root,'commit','-m',"release($($Item.Name)): $next"); Invoke-External 'git' @('-C',$Script:Root,'tag','-a',$tag,'-m',"$($Item.Name) $next"); if((Read-Host 'Type PUSH to push commit and tag') -ne 'PUSH'){Write-Ui "Commit and local tag created, but not pushed: $tag" Warn;return}; Invoke-External 'git' @('-C',$Script:Root,'push','origin',$state.Branch); Invoke-External 'git' @('-C',$Script:Root,'push','origin',$tag); Write-Ui "Release pushed: $tag" Success } catch { Write-Ui "Release stopped: $($_.Exception.Message). Inspect Git status; do not create a duplicate tag." Error; throw }
}
function Dispatch-App([object]$Item) { if(-not(Test-Tool gh)){throw 'GitHub CLI is required. Install gh and run gh auth login.'}; if(-not $Item.workflow){throw "No configured workflow for $($Item.Name)."}; $args=@('workflow','run',$Item.workflow); foreach($p in $Item.workflowInputs.psobject.Properties){$value=$p.Value; if($p.Name -eq 'release_type'){$value=$Bump}; if($p.Name -eq 'environment' -and $Environment -eq 'dev'){$value='internal'}; $args += @('-f',"$($p.Name)=$value")}; Invoke-External 'gh' $args; Write-Ui "Workflow dispatched: $($Item.workflow). Use -Health to see its latest run." Success }
function Show-Artifacts { $root=Join-Path $Script:Root 'artifacts'; if(Test-Path $root){Get-ChildItem $root -Recurse -File | Select-Object Name,DirectoryName,Length,LastWriteTime | Format-Table -AutoSize}else{Write-Ui 'No local artifacts have been created.' Warn} }
function Safe-Clean([object[]]$Items) { $targets=@(); foreach($item in $Items){$path=Join-Path $Script:Root "$($item.path)\build";if(Test-Path $path){$targets+=$path}}; if(!$targets){Write-Ui 'No generated build directories found.' Info;return}; Write-Host "Only these generated directories will be removed:`n$($targets -join "`n")"; if($NonInteractive -or (Read-Host 'Type CLEAN to continue') -ne 'CLEAN'){Write-Ui 'Clean cancelled.' Warn;return}; foreach($target in $targets){Remove-Item -LiteralPath $target -Recurse -Force}; Write-Ui 'Generated build directories removed. Artifacts and source files were preserved.' Success }
function Select-AppsInteractive([object[]]$Apps) { $Apps | ForEach-Object -Begin {$i=0} -Process {$i++;Write-Host "$i) $($_.Name) — $($_.technology) $($_.Version)"}; Write-Host 'A) All'; $choice=Read-Host 'Select app number(s), comma-separated, or A'; if($choice -eq 'A'){return @($Apps|Where-Object technology -eq 'Flutter')}; $selected=@(); foreach($n in $choice.Split(',')){if($n.Trim() -notmatch '^\d+$' -or [int]$n.Trim() -lt 1 -or [int]$n.Trim() -gt $Apps.Count){throw 'Invalid app selection.'};$selected+=$Apps[[int]$n.Trim()-1]};$selected }
function Show-Console { Clear-Host; $state=Get-GitState; Write-Host 'Lifemate Dev Console' -ForegroundColor Cyan; Write-Host "Tool 1.0.0  |  Branch: $($state.Branch)  |  Apps: $((Get-Apps).Count)  |  Tree: $(if($state.Dirty){'dirty'}else{'clean'})"; Write-Host ''; @('1) Apps','2) Project Health','3) Run app','4) Build Debug','5) Build Release','6) Build APK/AAB','7) Install APK','8) Artifacts & build reports','9) Version & tag','10) GitHub Actions','11) Safe clean','0) Exit') | ForEach-Object {Write-Host $_}; }
function Start-Menu { while($true){Show-Console; $choice=Read-Host 'Choose'; switch($choice){'1'{Show-Apps;pause}'2'{Show-Health;pause}'3'{Get-SelectedApps|ForEach-Object{Run-App $_};pause}'4'{Get-SelectedApps|ForEach-Object{Build-App $_ 'Debug' 'APK'};pause}'5'{Get-SelectedApps|ForEach-Object{Build-App $_ 'Release' 'APK'};pause}'6'{$f=Read-Host 'APK or AAB';Get-SelectedApps|ForEach-Object{Build-App $_ 'Release' $f.ToUpperInvariant()};pause}'7'{Get-SelectedApps|ForEach-Object{Install-App $_};pause}'8'{Show-Artifacts;pause}'9'{Get-SelectedApps|ForEach-Object{Start-Release $_};pause}'10'{Get-SelectedApps|ForEach-Object{Dispatch-App $_};pause}'11'{Safe-Clean (Get-SelectedApps);pause}'0'{return}default{Write-Ui 'Unknown menu option.' Warn;Start-Sleep -Seconds 1}}} }

try { if($Script:Interactive){Start-Menu}elseif($List){Show-Apps}elseif($Health){Show-Health}elseif($OpenArtifacts){$p=Join-Path $Script:Root 'artifacts';if(Test-Path $p){Start-Process explorer.exe $p}else{Write-Ui 'No artifact folder exists yet.' Warn}}elseif($Logs){if(Test-Path $Script:ReportRoot){Get-Content (Join-Path $Script:ReportRoot 'build-history.jsonl')}else{Write-Ui 'No build reports found.' Warn}}else{$targets=Get-SelectedApps;if($Run){$targets|ForEach-Object{Run-App $_}}elseif($Build){$targets|ForEach-Object{Build-App $_ $Build $Format}}elseif($Install){$targets|ForEach-Object{Install-App $_}}elseif($Release){$targets|ForEach-Object{Start-Release $_}}elseif($DispatchWorkflow){$targets|ForEach-Object{Dispatch-App $_}}elseif($Clean){Safe-Clean $targets}else{Show-Apps}} } catch { Write-Ui $_.Exception.Message Error; if($VerbosePreference -eq 'Continue') { Write-Error $_.ScriptStackTrace }; exit 1 }

