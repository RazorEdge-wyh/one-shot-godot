# 下载 CC0 免费素材（Kenney.nl 的 GitHub 镜像 ETdoFresh/kenney.nl，授权见 assets/LICENSE_kenney.txt）
# 用法: pwsh -File tools/fetch_assets.ps1
$ErrorActionPreference = "Stop"
$base = "https://raw.githubusercontent.com/ETdoFresh/kenney.nl/master/"
$root = Split-Path -Parent $PSScriptRoot
$sounds = Join-Path $root "assets\sounds"
$fonts  = Join-Path $root "assets\fonts"
$models = Join-Path $root "assets\models"
New-Item -ItemType Directory -Force -Path $sounds, $fonts, $models | Out-Null

$files = @(
    # ---- 字体 (Kenney Font Package, CC0) ----
    @("kenney_fontpackage/Fonts/Kenney Future.ttf",            "$fonts\KenneyFuture.ttf"),
    @("kenney_fontpackage/Fonts/Kenney Future Narrow.ttf",     "$fonts\KenneyFutureNarrow.ttf"),

    # ---- 发射/能量音 (Kenney Digital Audio, CC0) ----
    @("kenney_digitalaudio/Audio/laser1.ogg",                  "$sounds\shot_1.ogg"),
    @("kenney_digitalaudio/Audio/laser5.ogg",                  "$sounds\shot_2.ogg"),
    @("kenney_digitalaudio/Audio/laser9.ogg",                  "$sounds\shot_3.ogg"),
    @("kenney_digitalaudio/Audio/highUp.ogg",                  "$sounds\ui_confirm.ogg"),
    @("kenney_digitalaudio/Audio/lowDown.ogg",                 "$sounds\fail.ogg"),
    @("kenney_digitalaudio/Audio/pepSound1.ogg",               "$sounds\pep_1.ogg"),
    @("kenney_digitalaudio/Audio/pepSound2.ogg",               "$sounds\pep_2.ogg"),

    # ---- 反弹撞击音 (Kenney Impact Sounds, CC0) ----
    @("kenney_impactsounds/Audio/impactMetal_light_000.ogg",   "$sounds\ricochet_1.ogg"),
    @("kenney_impactsounds/Audio/impactMetal_light_001.ogg",   "$sounds\ricochet_2.ogg"),
    @("kenney_impactsounds/Audio/impactMetal_light_002.ogg",   "$sounds\ricochet_3.ogg"),
    @("kenney_impactsounds/Audio/impactMetal_light_003.ogg",   "$sounds\ricochet_4.ogg"),
    @("kenney_impactsounds/Audio/impactMetal_medium_000.ogg",  "$sounds\ricochet_heavy_1.ogg"),
    @("kenney_impactsounds/Audio/impactMetal_medium_001.ogg",  "$sounds\ricochet_heavy_2.ogg"),
    @("kenney_impactsounds/Audio/impactPlate_light_000.ogg",   "$sounds\block_1.ogg"),
    @("kenney_impactsounds/Audio/impactPlate_light_001.ogg",   "$sounds\block_2.ogg"),

    # ---- 击碎音 (Kenney Impact Sounds, CC0) ----
    @("kenney_impactsounds/Audio/impactGlass_heavy_000.ogg",   "$sounds\break_1.ogg"),
    @("kenney_impactsounds/Audio/impactGlass_heavy_001.ogg",   "$sounds\break_2.ogg"),
    @("kenney_impactsounds/Audio/impactGlass_heavy_002.ogg",   "$sounds\break_3.ogg"),
    @("kenney_impactsounds/Audio/impactGlass_heavy_003.ogg",   "$sounds\break_4.ogg"),

    # ---- UI 音 (Kenney UI Audio, CC0) ----
    @("kenney_uiaudio/Audio/click1.ogg",                       "$sounds\ui_click.ogg"),
    @("kenney_uiaudio/Audio/rollover1.ogg",                    "$sounds\ui_hover.ogg"),

    # ---- 结算音乐 (Kenney Music Jingles, CC0) ----
    @("kenney_musicjingles/Audio/8-Bit jingles/jingles_NES00.ogg", "$sounds\jingle_win.ogg"),
    @("kenney_musicjingles/Audio/8-Bit jingles/jingles_NES10.ogg", "$sounds\jingle_fail.ogg"),

    # ---- 装饰模型 (Kenney Space Kit, CC0) ----
    @("space-kit-1.0/Models/console.obj",                      "$models\console.obj"),
    @("space-kit-1.0/Models/console.mtl",                      "$models\console.mtl"),
    @("space-kit-1.0/Models/consoleScreen.obj",                "$models\consoleScreen.obj"),
    @("space-kit-1.0/Models/consoleScreen.mtl",                "$models\consoleScreen.mtl"),
    @("space-kit-1.0/Models/barrel.obj",                       "$models\barrel.obj"),
    @("space-kit-1.0/Models/barrel.mtl",                       "$models\barrel.mtl"),
    @("space-kit-1.0/Models/barrelLarge.obj",                  "$models\barrelLarge.obj"),
    @("space-kit-1.0/Models/barrelLarge.mtl",                  "$models\barrelLarge.mtl"),
    @("space-kit-1.0/Models/metalStructure.obj",               "$models\metalStructure.obj"),
    @("space-kit-1.0/Models/metalStructure.mtl",               "$models\metalStructure.mtl"),
    @("space-kit-1.0/Models/portal.obj",                       "$models\portal.obj"),
    @("space-kit-1.0/Models/portal.mtl",                       "$models\portal.mtl"),
    @("space-kit-1.0/Models/satelliteDish.obj",                "$models\satelliteDish.obj"),
    @("space-kit-1.0/Models/satelliteDish.mtl",                "$models\satelliteDish.mtl"),
    @("space-kit-1.0/Models/laserSabel.obj",                   "$models\laserSabel.obj"),
    @("space-kit-1.0/Models/laserSabel.mtl",                   "$models\laserSabel.mtl"),
    @("space-kit-1.0/Models/rocksSmall.obj",                   "$models\rocksSmall.obj"),
    @("space-kit-1.0/Models/rocksSmall.mtl",                   "$models\rocksSmall.mtl"),
    @("space-kit-1.0/Models/metalFence.obj",                   "$models\metalFence.obj"),
    @("space-kit-1.0/Models/metalFence.mtl",                   "$models\metalFence.mtl"),
    @("space-kit-1.0/License.txt",                             (Join-Path $root "assets\LICENSE_kenney_spacekit.txt")),
    @("kenney_impactsounds/License.txt",                       (Join-Path $root "assets\LICENSE_kenney_sounds.txt"))
)

$ok = 0; $fail = 0
foreach ($pair in $files) {
    $url = $base + ($pair[0] -replace ' ', '%20')
    $dst = $pair[1]
    curl.exe -sS --ssl-no-revoke --fail --max-time 60 -o $dst $url
    if ($LASTEXITCODE -eq 0 -and (Test-Path $dst) -and (Get-Item $dst).Length -gt 0) {
        $ok++
    } else {
        $fail++
        Write-Host "FAILED: $($pair[0])" -ForegroundColor Red
    }
}
Write-Host "downloaded ok=$ok fail=$fail"
Get-ChildItem $root\assets -Recurse -File | Measure-Object -Property Length -Sum | ForEach-Object { "total assets size: {0:N1} KB" -f ($_.Sum/1KB) }
