<#
MindMiner  Copyright (C) 2019-2020  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

if ([Config]::ActiveTypes -notcontains [eMinerType]::CPU) { exit }
if (![Config]::Is64Bit) { exit }

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$Cfg = ReadOrCreateMinerConfig "Do you want use to mine the '$Name' miner" ([IO.Path]::Combine($PSScriptRoot, $Name + [BaseConfig]::Filename)) @{
	Enabled = $true
	BenchmarkSeconds = 60
	ExtraArgs = $null
	Algorithms = @(
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "argon2d_dynamic" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "argon2id_chukwa2" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cpupower" }		
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cryptonight_cache" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cryptonight_ccx" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cryptonight_xhv" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cryptonight_upx" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "cryptonight_heavyx" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "m7mv2" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "minotaur" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "panthera" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "randomarq" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "randomepic" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "randomkeva" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "randomsfx" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "randomwow" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "randomx" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "randomxl" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "tellor" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "verushash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yescrypt" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yescryptr16" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yescryptr32" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "yescryptr8" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespower" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespower2b" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespoweric" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespoweriots" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespoweritc" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespowerlitb" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespowerltncg" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespowerr16" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespowerres" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespowersugar" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "yespowerurx" }
)}

if (!$Cfg.Enabled) { return }

$Cfg.Algorithms | ForEach-Object {
	if ($_.Enabled) {
		$Algo = Get-Algo($_.Algorithm)
		if ($Algo) {
			# find pool by algorithm
			$Pool = Get-Pool($Algo)
			if ($Pool) {
				$extrargs = Get-Join " " @($Cfg.ExtraArgs, $_.ExtraArgs)
				$nicehash = "--nicehash false"
				if ($Pool.Name -match "nicehash") {
					$nicehash = "--nicehash true"
				}
				$fee = 0.85
				if ($_.Algorithm -match "minotaur") { $fee = 2 }
				elseif ($_.Algorithm -match "m7mv2" -or $_.Algorithm -match "yespowerurx" -or $_.Algorithm -match "yespoweritc") { $fee = 0 }
				[MinerInfo]@{
					Pool = $Pool.PoolName()
					PoolKey = $Pool.PoolKey()
					Priority = $Pool.Priority
					Name = $Name
					Algorithm = $Algo
					Type = [eMinerType]::CPU
					API = "srbm2"
					URI = "https://github.com/doktor83/SRBMiner-Multi/releases/download/0.5.4/SRBMiner-Multi-0-5-4-win64.zip"
					Path = "$Name\SRBMiner-MULTI.exe"
					ExtraArgs = $extrargs
					Arguments = "--algorithm $($_.Algorithm) --pool $($Pool.Hosts[0]):$($Pool.PortUnsecure) --wallet $($Pool.User) --password $($Pool.Password) --tls false --api-enable --api-port 4045 --miner-priority 1 --disable-gpu --retry-time $($Config.CheckTimeout) $nicehash $extrargs"
					Port = 4045
					BenchmarkSeconds = if ($_.BenchmarkSeconds) { $_.BenchmarkSeconds } else { $Cfg.BenchmarkSeconds }
					RunBefore = $_.RunBefore
					RunAfter = $_.RunAfter
					Fee = $fee
				}
			}
		}
	}
}
