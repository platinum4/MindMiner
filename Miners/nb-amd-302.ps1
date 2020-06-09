<#
MindMiner  Copyright (C) 2019-2020  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

if ([Config]::ActiveTypes -notcontains [eMinerType]::AMD) { exit }
if (![Config]::Is64Bit) { exit }

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$Cfg = [BaseConfig]::ReadOrCreate([IO.Path]::Combine($PSScriptRoot, $Name + [BaseConfig]::Filename), @{
	Enabled = $true
	BenchmarkSeconds = 120
	ExtraArgs = $null
	Algorithms = @(
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "ethash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "eaglesong" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "hns" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "kawpow" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "progpow_sero" }
)})

if (!$Cfg.Enabled) { return }

$Cfg.Algorithms | ForEach-Object {
	if ($_.Enabled) {
		$Algo = Get-Algo($_.Algorithm)
		if ($Algo -and $_.Algorithm -notmatch "bfc") { # https://github.com/NebuTech/NBMiner/issues/154
			# find pool by algorithm
			$Pool = Get-Pool($Algo)
			if ($Pool -and ($Pool.Name -notmatch "mrr" -or ($Pool.Name -match "mrr" -and $_.Algorithm -notmatch "cuckoo_ae" -and $_.Algorithm -notmatch "cuckarood"))) {
				$extrargs = Get-Join " " @($Cfg.ExtraArgs, $_.ExtraArgs)
				$fee = 2
				switch ($_.Algorithm) {
					"ethash" { $fee = 0.65 }
					"tensority" { $fee = 3 }
					default {}
				}
				$stratum = $Pool.Protocol
				$port = $Pool.Port
				if ($Pool.Name -match "nicehash" -and ($_.Algorithm -match "ethash" -or $_.Algorithm -match "cuck")) { $stratum = "nicehash+tcp" }
				$pools = [string]::Empty
				for ($i = 0; $i -lt $Pool.Hosts.Count -and $i -lt 3; $i++) {
					$idx = if ($i -eq 0) { [string]::Empty } else { $i.ToString() }
					$pools = Get-Join " " @($pools, "-o$idx $stratum`://$($Pool.Hosts[$i]):$port -u$idx $($Pool.User):$($Pool.Password)")
				}
				[MinerInfo]@{
					Pool = $Pool.PoolName()
					PoolKey = $Pool.PoolKey()
					Priority = $Pool.Priority
					Name = $Name
					Algorithm = $Algo
					Type = [eMinerType]::AMD
					API = "nbminer"
					URI = "https://github.com/NebuTech/NBMiner/releases/download/v30.2/NBMiner_30.2_Win.zip"
					Path = "$Name\nbminer.exe"
					ExtraArgs = $extrargs
					Arguments = "-a $($_.Algorithm) $pools --api 127.0.0.1:4044 --no-nvml -no-watchdog --platform 2 $extrargs"
					Port = 4044
					BenchmarkSeconds = if ($_.BenchmarkSeconds) { $_.BenchmarkSeconds } else { $Cfg.BenchmarkSeconds }
					RunBefore = $_.RunBefore
					RunAfter = $_.RunAfter
					Fee = $fee
				}
			}
		}
	}
}