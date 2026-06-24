param(
	[string]$VpkExe = "",
	[string]$L4D2Path = "F:\SteamLibrary\steamapps\common\Left 4 Dead 2",
	[switch]$Install
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AddonDir = Join-Path $Root "gxLdBot"
$OutputVpk = Join-Path $Root "gxldbot.vpk"

if (-not (Test-Path -LiteralPath $AddonDir)) {
	throw "Addon folder not found: $AddonDir"
}

if ([string]::IsNullOrWhiteSpace($VpkExe)) {
	$candidates = @(
		(Join-Path $L4D2Path "bin\vpk.exe"),
		"F:\SteamLibrary\steamapps\common\Left 4 Dead 2\bin\vpk.exe",
		"C:\Program Files (x86)\Steam\steamapps\common\Left 4 Dead 2\bin\vpk.exe"
	)

	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) {
			$VpkExe = $candidate
			break
		}
	}
}

if (-not (Test-Path -LiteralPath $VpkExe)) {
	throw "vpk.exe not found. Pass -VpkExe or set -L4D2Path."
}

Write-Host "Packing $AddonDir"
& $VpkExe $AddonDir

if (-not (Test-Path -LiteralPath $OutputVpk)) {
	throw "Expected output not found: $OutputVpk"
}

Write-Host "Built $OutputVpk"

if ($Install) {
	$AddonsDir = Join-Path $L4D2Path "left4dead2\addons"
	if (-not (Test-Path -LiteralPath $AddonsDir)) {
		throw "L4D2 addons folder not found: $AddonsDir"
	}

	$InstalledVpk = Join-Path $AddonsDir "gxldbot.vpk"
	Copy-Item -LiteralPath $OutputVpk -Destination $InstalledVpk -Force
	Write-Host "Installed $InstalledVpk"
	Write-Host "Restart L4D2 or reload the map before testing script changes."
}
