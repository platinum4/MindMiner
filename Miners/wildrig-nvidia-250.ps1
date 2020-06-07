<#
MindMiner  Copyright (C) 2018-2020  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

if ([Config]::ActiveTypes -notcontains [eMinerType]::AMD) { exit }
if (![Config]::Is64Bit) { exit }

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$Cfg = ReadOrCreateMinerConfig "Do you want use to mine the '$Name' miner" ([IO.Path]::Combine($PSScriptRoot, $Name + [BaseConfig]::Filename)) @{
	Enabled = $true
	BenchmarkSeconds = 90
	ExtraArgs = $null
	Algorithms = @(
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "aergo" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "anime" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "bcd" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "bitcore" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "blake2b-btcc" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "blake2b-glt" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "bmw512" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "c11" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "dedal" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "exosis" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "geek" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "glt-astralhash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "glt-globalhash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "glt-hex" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "glt-jeonghash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "glt-padihash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "glt-pawelhash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "hex" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "hmq1725" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "honeycomb" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "kawpow"; BenchmarkSeconds = 120 }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "lyra2tdc" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "lyra2v3" } # teamred faster
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "lyra2vc0ban" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "mtp" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "mtp-tcr" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "phi" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "polytimos" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "progpow-ethercore" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "progpow-sero" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "progpowz" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "renesis" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "sha256q" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "sha256t" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "sha256csm" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "skein2" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "skunkhash" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "sonoa" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "timetravel" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "tribus" }
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "wildkeccak" }
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x16r" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x16rv2" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x16rt" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "veil" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x16s" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x17" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x17r" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x17r-protocol2" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x18" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x20r" } # t-rex faster
		[AlgoInfoEx]@{ Enabled = $false; Algorithm = "x21s" } # t-rex faster
		# [AlgoInfoEx]@{ Enabled = $true; Algorithm = "x22i" } # not even work
		# [AlgoInfoEx]@{ Enabled = $true; Algorithm = "x25x" } # not even work
		[AlgoInfoEx]@{ Enabled = $true; Algorithm = "xevan" }
)}

if (!$Cfg.Enabled) { return }

$Cfg.Algorithms | ForEach-Object {
	if ($_.Enabled) {
		$Algo = Get-Algo($_.Algorithm)
		if ($Algo) {
			# find pool by algorithm
			$Pool = Get-Pool($Algo)
			if ($Pool) {
				if ($_.Algorithm -match "veil") { $_.Algorithm = "x16rt" }
				$extrargs = Get-Join " " @($Cfg.ExtraArgs, $_.ExtraArgs)
				$hosts = [string]::Empty
				$Pool.Hosts | ForEach-Object {
					$hosts = Get-Join " " @($hosts, "-o $_`:$($Pool.PortUnsecure) -u $($Pool.User) -p $($Pool.Password)")
				}
				[MinerInfo]@{
					Pool = $Pool.PoolName()
					PoolKey = $Pool.PoolKey()
					Priority = $Pool.Priority
					Name = $Name
					Algorithm = $Algo
					Type = [eMinerType]::nVidia
					TypeInKey = $true
					API = "xmrig"
					URI = "https://github.com/andru-kun/wildrig-multi/releases/download/0.25.0/wildrig-multi-windows-0.25.0.7z"
					Path = "$Name\wildrig.exe"
					ExtraArgs = $extrargs
					Arguments = "-a $($_.Algorithm) $hosts -R $($Config.CheckTimeout) --opencl-platform=$([Config]::nVidiaPlatformId) --api-port=4028 --donate-level=1 $extrargs"
					Port = 4028
					BenchmarkSeconds = if ($_.BenchmarkSeconds) { $_.BenchmarkSeconds } else { $Cfg.BenchmarkSeconds }
					RunBefore = $_.RunBefore
					RunAfter = $_.RunAfter
					Fee = 1
				}
			}
		}
	}
}