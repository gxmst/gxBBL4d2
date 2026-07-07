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

# Remove any stale output first so a FAILED pack can't leave the previous VPK
# sitting there and get mistaken for a fresh build (and then installed).
if (Test-Path -LiteralPath $OutputVpk) {
	Remove-Item -LiteralPath $OutputVpk -Force
}

& $VpkExe $AddonDir

# vpk.exe returns non-zero on failure — treat that as fatal instead of trusting
# a leftover file. Combined with the pre-delete above, this guarantees we only
# ever report/install a VPK that THIS run actually produced.
if ($LASTEXITCODE -ne 0) {
	throw "vpk.exe failed with exit code $LASTEXITCODE"
}

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
