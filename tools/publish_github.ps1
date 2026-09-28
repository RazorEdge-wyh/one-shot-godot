param(
	[Parameter(Mandatory = $true)][string]$User,
	[string]$Repo = "one-shot-godot",
	[string]$Token = $env:GITHUB_TOKEN,
	[string]$TokenFile = "$env:USERPROFILE\.gh_token",
	[string]$Description = "ONE SHOT 一弹到底 —— 一发子弹、反弹换色的 3D 弹球解谜小游戏（Godot 4.6）",
	[string]$AuthorName = "王越豪",
	[switch]$Private
)

# 用 GitHub REST API 直接把工程推上去（没装 git 也能用）。
# 所有文件压成"一个提交"；仓库已存在时以本地为准覆盖式更新。
#
# 用法：
#   powershell -File tools/publish_github.ps1 -User 你的GitHub用户名
#   token 从 $env:GITHUB_TOKEN 或 %USERPROFILE%\.gh_token 读取，不写在命令行里。

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$api = "https://api.github.com"

if (-not $Token) {
	if (Test-Path $TokenFile) {
		$Token = (Get-Content $TokenFile -Raw).Trim()
	} else {
		throw "没有找到 token。请设置 `$env:GITHUB_TOKEN，或把 token 写到 $TokenFile"
	}
}

$curl = "curl.exe"
$common = @("-sS", "--ssl-no-revoke", "--max-time", "120",
	"-H", "Authorization: Bearer $Token",
	"-H", "Accept: application/vnd.github+json",
	"-H", "X-GitHub-Api-Version: 2022-11-28",
	"-H", "User-Agent: one-shot-publisher")
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Invoke-Api {
	param([string]$Method, [string]$Path, $Body = $null)
	$url = "$api$Path"
	$tmp = [System.IO.Path]::GetTempFileName()
	if ($null -ne $Body) {
		$jsonFile = [System.IO.Path]::GetTempFileName()
		[System.IO.File]::WriteAllText($jsonFile, ($Body | ConvertTo-Json -Depth 12 -Compress), $utf8)
		& $curl @common -X $Method -H "Content-Type: application/json" --data-binary "@$jsonFile" -o $tmp -w "%{http_code}" $url | Out-Null
		Remove-Item $jsonFile -Force -ErrorAction SilentlyContinue
	} else {
		& $curl @common -X $Method -o $tmp -w "%{http_code}" $url | Out-Null
	}
	$text = if (Test-Path $tmp) { [System.IO.File]::ReadAllText($tmp, $utf8) } else { "" }
	Remove-Item $tmp -Force -ErrorAction SilentlyContinue
	$obj = $null
	if ($text.Trim().Length -gt 0) {
		try { $obj = $text | ConvertFrom-Json } catch { $obj = $null }
	}
	return [pscustomobject]@{ Text = $text; Json = $obj }
}

Write-Host "== 校验 token ==" -ForegroundColor Cyan
$me = Invoke-Api "GET" "/user"
if (-not $me.Json -or -not $me.Json.login) { throw "token 无效或权限不足：$($me.Text)" }
$login = $me.Json.login
$uid = $me.Json.id
Write-Host "   登录为 $login"

Write-Host "== 创建 / 复用仓库 $User/$Repo ==" -ForegroundColor Cyan
$create = Invoke-Api "POST" "/user/repos" @{
	name        = $Repo
	description = $Description
	private     = [bool]$Private
	auto_init   = $false
	has_issues  = $true
	has_wiki    = $false
}
if ($create.Text -match "already exists") {
	Write-Host "   仓库已存在，将更新内容"
} elseif (-not $create.Json -or -not $create.Json.full_name) {
	throw "创建仓库失败：$($create.Text)"
} else {
	Write-Host "   已创建：$($create.Json.html_url)"
}

# 空仓库上 Git Data API 会返回 409 "Git Repository is empty"，
# 所以先用 Contents API 塞一个占位文件，把初始提交和默认分支建出来。
$ref = Invoke-Api "GET" "/repos/$User/$Repo/git/ref/heads/main"
if (-not $ref.Json -or -not $ref.Json.object) {
	Write-Host "== 初始化空仓库（建立初始提交）==" -ForegroundColor Cyan
	$seed = [Convert]::ToBase64String($utf8.GetBytes("one-shot`n"))
	$init = Invoke-Api "PUT" "/repos/$User/$Repo/contents/.one-shot-init" @{
		message = "chore: 初始化仓库"
		content = $seed
	}
	if (-not $init.Json -or -not $init.Json.commit) { throw "初始化仓库失败：$($init.Text)" }
}

$repoInfo = Invoke-Api "GET" "/repos/$User/$Repo"
$branch = if ($repoInfo.Json -and $repoInfo.Json.default_branch) { $repoInfo.Json.default_branch } else { "main" }
$ref = Invoke-Api "GET" "/repos/$User/$Repo/git/ref/heads/$branch"
$parents = @()
if ($ref.Json -and $ref.Json.object -and $ref.Json.object.sha) {
	$parents = @($ref.Json.object.sha)
	Write-Host "   分支 $branch 现有提交：$($ref.Json.object.sha.Substring(0, 7))"
}

Write-Host "== 收集文件 ==" -ForegroundColor Cyan
$skip = @('\\\.godot\\', '\\\.git\\', '\\\.shots\\', '\\build\\', '\\\.gh_token')
$files = Get-ChildItem -Path $root -Recurse -File | Where-Object {
	$p = $_.FullName
	-not ($skip | Where-Object { $p -match $_ })
}
Write-Host "   共 $($files.Count) 个文件"

Write-Host "== 上传 blob ==" -ForegroundColor Cyan
$entries = @()
$i = 0
foreach ($f in $files) {
	$i++
	$rel = $f.FullName.Substring($root.Length + 1).Replace("\", "/")
	$b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f.FullName))
	$r = Invoke-Api "POST" "/repos/$User/$Repo/git/blobs" @{ content = $b64; encoding = "base64" }
	if (-not $r.Json -or -not $r.Json.sha) { throw "上传失败：$rel -> $($r.Text)" }
	$entries += @{ path = $rel; mode = "100644"; type = "blob"; sha = $r.Json.sha }
	if ($i % 20 -eq 0) { Write-Host "   $i / $($files.Count)" }
}

Write-Host "== 生成 tree ==" -ForegroundColor Cyan
$tree = Invoke-Api "POST" "/repos/$User/$Repo/git/trees" @{ tree = $entries }
if (-not $tree.Json -or -not $tree.Json.sha) { throw "创建 tree 失败：$($tree.Text)" }

Write-Host "== 生成 commit ==" -ForegroundColor Cyan
$msg = "ONE SHOT 一弹到底：一发子弹、反弹换色的 3D 弹球解谜小游戏`n`n" +
"作者：王越豪（湖南科技大学），学习作品。`n" +
"Godot 4.6；字体/音效/模型来自 Kenney.nl（CC0）；6 关均由 tools/solve.gd 扫描验证可解，tools/verify.gd 端到端 6/6 通过。"
$commit = Invoke-Api "POST" "/repos/$User/$Repo/git/commits" @{
	message = $msg
	tree    = $tree.Json.sha
	parents = $parents
	author  = @{ name = $AuthorName; email = "$uid+$login@users.noreply.github.com" }
}
if (-not $commit.Json -or -not $commit.Json.sha) { throw "创建 commit 失败：$($commit.Text)" }

Write-Host "== 更新分支 $branch ==" -ForegroundColor Cyan
if ($parents.Count -gt 0) {
	$upd = Invoke-Api "PATCH" "/repos/$User/$Repo/git/refs/heads/$branch" @{ sha = $commit.Json.sha; force = $false }
	if (-not $upd.Json -or -not $upd.Json.object) { throw "更新分支失败：$($upd.Text)" }
} else {
	$new = Invoke-Api "POST" "/repos/$User/$Repo/git/refs" @{ ref = "refs/heads/$branch"; sha = $commit.Json.sha }
	if (-not $new.Json -or -not $new.Json.object) { throw "创建分支失败：$($new.Text)" }
}

Write-Host ""
Write-Host "完成：https://github.com/$User/$Repo" -ForegroundColor Green
