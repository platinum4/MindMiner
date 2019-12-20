<#
MindMiner  Copyright (C) 2018-2019  Oleg Samsonov aka Quake4
https://github.com/Quake4/MindMiner
License GPL-3.0
#>

$PoolInfo = [PoolInfo]::new()
$PoolInfo.Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName

$configfile = $PoolInfo.Name + [BaseConfig]::Filename
$configpath = [IO.Path]::Combine($PSScriptRoot, $configfile)

$Cfg = ReadOrCreatePoolConfig "Do you want to pass a rig to rent on $($PoolInfo.Name)" $configpath @{
	Enabled = $false
	Key = $null
	Secret = $null
	Region = $null
	DisabledAlgorithms = $null
	Wallets = $null
}

if ($global:HasConfirm -eq $true -and $Cfg -and [string]::IsNullOrWhiteSpace($Cfg.Key) -and [string]::IsNullOrWhiteSpace($Cfg.Secret)) {
	Write-Host "Create Api Key on `"https://www.miningrigrentals.com/account/apikey`" with grant to `"Manage Rigs`" as `"Yes`"." -ForegroundColor Yellow
	$Cfg.Key = Read-Host "Enter `"Key`""
	$Cfg.Secret = Read-Host "Enter `"Secret`""
	# ask wallets
	[Config]::MRRWallets | ForEach-Object {
		if (Get-Question "Do you want to accept payment in '$($_.ToUpper())'") {
			if (!$Cfg.Wallets) { $Cfg.Wallets = @() }
			$Cfg.Wallets += "$_"
		}
	}
	# save config
	[BaseConfig]::Save($configpath, $Cfg)
}

if ($global:AskPools -eq $true -or !$Cfg) { return $null }

$PoolInfo.Enabled = $Cfg.Enabled
if (!$Cfg.Enabled) { return $PoolInfo }
if (!$Cfg.DisabledAlgorithms) { $Cfg.DisabledAlgorithms = @() }

if ([string]::IsNullOrWhiteSpace($Cfg.Key) -or [string]::IsNullOrWhiteSpace($Cfg.Secret)) {
	Write-Host "Fill in the `"Key`" and `"Secret`" parameters in the configuration file `"$configfile`" or disable the $($PoolInfo.Name)." -ForegroundColor Yellow
	return $PoolInfo
}

$servers = Get-Rest "https://www.miningrigrentals.com/api/v2/info/servers"
if (!$servers -or !$servers.success) {
	return $PoolInfo
}

if ([string]::IsNullOrWhiteSpace($Cfg.Region)) {
	$Cfg.Region = "us-central"
	switch ($Config.Region) {
		"$([eRegion]::Europe)" { $Cfg.Region = "eu" }
		"$([eRegion]::China)" { $Cfg.Region = "ap" }
		"$([eRegion]::Japan)" { $Cfg.Region = "ap" }
	}
	if ($Cfg.Region -eq "eu") {
		[string] $locale = "$($Cfg.Region)-$((Get-Host).CurrentCulture.TwoLetterISOLanguageName)"
		if ($servers.data | Where-Object { $_.region -match $locale }) {
			$Cfg.Region = $locale
		}
	}
}
$server = $servers.data | Where-Object { $_.region -match $Cfg.Region } | Select-Object -First 1	

if (!$server -or $server.Length -gt 1) {
	$servers = $servers.data | Select-Object -ExpandProperty region
	Write-Host "Set `"Region`" parameter from list ($(Get-Join ", " $servers)) in the configuration file `"$configfile`" or disable the $($PoolInfo.Name)." -ForegroundColor Yellow
	return $PoolInfo;
}

# check algorithms
$AlgosRequest = Get-Rest "https://www.miningrigrentals.com/api/v2/info/algos"
if (!$AlgosRequest -or !$AlgosRequest.success) {
	return $PoolInfo
}

$Algos = [Collections.Generic.Dictionary[string, PoolAlgorithmInfo]]::new()
$AlgosRequest.data | ForEach-Object {
	$Algo = $_
	$Pool_Algorithm = Get-Algo $Algo.name
	if ($Pool_Algorithm -and $Cfg.DisabledAlgorithms -notcontains $Pool_Algorithm) {
		$Algo.stats.prices.last_10.amount = [decimal]$Algo.stats.prices.last_10.amount
		[decimal] $Price = 0
		if ($Algo.stats.prices.last_10.amount -gt 0) {
			$Price = $Algo.stats.prices.last_10.amount / [MultipleUnit]::ToValueInvariant("1", $Algo.stats.prices.last_10.unit.ToLower().TrimEnd("h*day"))
		}
		else {
			$Price = [decimal]$Algo.suggested_price.amount / [MultipleUnit]::ToValueInvariant("1", $Algo.suggested_price.unit.ToLower().TrimEnd("h*day"))
		}

		$percent = 0;

		$Algo.stats.rented.rigs = [int]$Algo.stats.rented.rigs
		$Algo.stats.available.rigs = [int]$Algo.stats.available.rigs
		if (($Algo.stats.rented.rigs + $Algo.stats.available.rigs) -gt 0) {
			$percent = $Algo.stats.rented.rigs / ($Algo.stats.rented.rigs + $Algo.stats.available.rigs) * 100
		}

		if (![string]::IsNullOrEmpty($Algo.stats.rented.hash.hash) -and ![string]::IsNullOrEmpty($Algo.stats.available.hash.hash)) {
			$rented = [MultipleUnit]::ToValueInvariant($Algo.stats.rented.hash.hash, $Algo.stats.rented.hash.unit -replace "h")
			$avail = [MultipleUnit]::ToValueInvariant($Algo.stats.available.hash.hash, $Algo.stats.available.hash.unit -replace "h")
			if (($rented + $avail) -gt 0) {
				$percent = [Math]::Max($percent, $rented / ($rented + $avail) * 100)
			}
		}

		$info = Get-Join "/" @($(if ($Algo.stats.rented.rigs -eq 0) { "0" } else { "$($Algo.stats.rented.rigs)($($Algo.stats.rented.hash.nice))" }),
			$(if ($Algo.stats.available.rigs -eq 0) { "0" } else { "$($Algo.stats.available.rigs)($($Algo.stats.available.hash.nice))" }))
		$Algos[$Pool_Algorithm] = [PoolAlgorithmInfo] @{
			Name = $PoolInfo.Name
			Algorithm = $Pool_Algorithm
			Profit = 0 # $Profit
			Price = $Price
			Info = $info
			Protocol = "stratum+tcp"
			Hosts = @($server.name)
			Port = $server.port
			PortUnsecure = $server.port
			User = $Algo.name
			Password = $percent
			Priority = [Priority]::None
		}
	}
}

# check rented
try {
	$mrr = [MRR]::new($Cfg.Key, $Cfg.Secret);
	# $mrr.Debug = $true;
	$whoami = $mrr.Get("/whoami")
	if (!$whoami.authed) {
		$whoami = $mrr.Get("/whoami")
		if (!$whoami.authed) {
			Write-Host "MRR: Not authorized! Check Key and Secret." -ForegroundColor Yellow
			return $PoolInfo;
		}
	}
	if ($whoami.permissions.rigs -ne "yes") {
		Write-Host "MRR: Need grant 'Manage Rigs' as 'Yes'." -ForegroundColor Yellow
		return $PoolInfo;
	}

	# balance
	if ($Config.ShowBalance -and $whoami.permissions.withdraw -ne "no") {
		$balance = $mrr.Get("/account/balance")
		$balance | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
			$confirmed = [decimal]$balance.$_.confirmed
			$unconfirmed = [decimal]$balance.$_.unconfirmed
			if ($confirmed -gt 0 -or $unconfirmed -gt 0) {
				$PoolInfo.Balance.Add($_, [BalanceInfo]::new($confirmed, $unconfirmed))
			}
		}
	}

	# check rigs
	$result = $mrr.Get("/rig/mine") | Where-Object { $_.name -match $Config.WorkerName }
	if ($result) {
		$rented_ids = @()
		$disable_ids = @()
		$enabled_ids = @()
		# smaller max
		if ([Config]::Max -eq 100) { [Config]::Max = 50 }
		# rented first
		$result | Sort-Object { [bool]$_.status.rented } -Descending | ForEach-Object {
			$Pool_Algorithm = Get-Algo $_.type
			if ($Pool_Algorithm -and [Config]::ActiveTypes.Length -gt 0 -and $Cfg.DisabledAlgorithms -notcontains $Pool_Algorithm) {
				if ($rented_ids.Length -gt 0) {
					$disable_ids += $_.id
				}
				elseif ((($KnownAlgos.Values | Where-Object { $_.ContainsKey($Pool_Algorithm) } | Select-Object -First 1) | Select-Object -First 1) -ne $null) {
					$enabled_ids += $_.id
				}
				$_.price.type = $_.price.type.ToLower().TrimEnd("h")
				$Profit = [decimal]$_.price.BTC.price / [MultipleUnit]::ToValueInvariant("1", $_.price.type)
				$user = "$($whoami.username).$($_.id)"
				# possible bug - algo unknown, but rented
				if ($rented_ids.Length -eq 0 -and $_.status.rented -and $_.status.hours -gt 0) {
					$rented_ids += $_.id
					# $redir = Ping-MRR $false $server.name $server.port $user $_.id
					$info = [SummaryInfo]::Elapsed([timespan]::FromHours($_.status.hours))
					$redir =  $mrr.Get("/rig/$($_.id)/port")
					$Algos[$Pool_Algorithm] = [PoolAlgorithmInfo]@{
						Name = $PoolInfo.Name
						Algorithm = $Pool_Algorithm
						Profit = $Profit * 0.97
						Info = $info
						Protocol = "stratum+tcp"
						Hosts = @($redir.server)
						Port = $redir.port
						PortUnsecure = $redir.port
						User = $user
						Password = "x"
						Priority = [Priority]::Unique
					}
					if (![Config]::MRRRented) {
						Write-Host "MRR: Rented $Pool_Algorithm for $info`: $($_.name)" -ForegroundColor Yellow
					}
				}
				else {
					$info = [string]::Empty
					if ($Algos.ContainsKey($Pool_Algorithm)) {
						$info = $Algos[$Pool_Algorithm].Info
					}
					$Algos[$Pool_Algorithm] = [PoolAlgorithmInfo]@{
						Name = $PoolInfo.Name
						Algorithm = $Pool_Algorithm
						Profit = $Profit * 0.97
						Info = $info
						Protocol = "stratum+tcp"
						Hosts = @($server.name)
						Port = $server.port
						PortUnsecure = $server.port
						User = $user
						Password = "x"
						Priority = [Priority]::None
					}
				}
			}
			else {
				$disable_ids += $_.id
			}
		}

		$Algos.Values | ForEach-Object {
			$PoolInfo.Algorithms.Add($_)
		}

		[Config]::MRRRented = $rented_ids.Length -gt 0
		
		# on first run skip enable/disable
		if (($KnownAlgos.Values | Measure-Object -Property Count -Sum).Sum -gt 0) {
			# disable
			$dids = @()
			$result | Where-Object { $_.available_status -match "available" -and $disable_ids -contains $_.id } | ForEach-Object {
				$alg = Get-Algo $_.type
				Write-Host "MRR: Disable $alg`: $($_.name)" -ForegroundColor Yellow
				$dids += $_.id
			}
			if ($dids.Length -gt 0) {
				$mrr.Put("/rig/$($dids -join ';')", @{ "status" = "disabled" })
			}
			# enable
			$eids = @()
			$result | Where-Object { $_.available_status -notmatch "available" -and $enabled_ids -contains $_.id -and $disable_ids -notcontains $_.id } | ForEach-Object {
				$alg = Get-Algo $_.type
				Write-Host "MRR: Available $alg`: $($_.name)" -ForegroundColor Yellow
				$eids += $_.id
			}
			if ($eids.Length -gt 0) {
				$mrr.Put("/rig/$($eids -join ';')", @{ "status" = "enabled" })
			}
			# ping 
			$result | Where-Object { !$_.status.rented -and $enabled_ids -contains $_.id -and $disable_ids -notcontains $_.id } | ForEach-Object {
				$alg = Get-Algo $_.type
				$SpeedAdv = $_.hashrate.advertised.hash * [MultipleUnit]::ToValueInvariant("1", $_.hashrate.advertised.type.ToLower().TrimEnd("h"))
				$SpeedCalc = (($KnownAlgos.Values | Foreach-Object { $t = $_[$alg]; if ($t -and $t.Item -and $t.Item.Profit -gt 0) { $t.Item } }) |
					Measure-Object Speed -Sum).Sum
				$warn = if ($SpeedCalc * 0.95 -gt $SpeedAdv -or $SpeedCalc * 1.05 -lt $SpeedAdv) { " ($([MultipleUnit]::ToString($SpeedCalc))H)" } else { [string]::Empty }
				Write-Host "MRR: Online $alg ($([decimal]::Round($SpeedAdv * $Algos[$alg].Profit, 8)) at $($_.hashrate.advertised.nice)H$warn): $($_.name)"
				Ping-MRR $server.name $server.port "$($whoami.username).$($_.id)" $_.id
			}
			# show top 3
			# $Algos.Values | Where-Object { $_.Profit -eq 0 -and [decimal]$_.Password -gt 20 } | Sort-Object { [decimal]$_.Password } -Descending | Select-Object -First 10 | ForEach-Object {
			# 	Write-Host "Check algo $($_.Algorithm) rented: $("{0:N1}" -f [decimal]$_.Password)% $($_.Info)"
			# }
		}
	}
	else {
		Write-Host "MRR: No compatible rigs found! Write `"$($Config.WorkerName)`" string to MRR rig name." -ForegroundColor Yellow
	}

	if ([Config]::ActiveTypes.Length -gt 0 -and ($KnownAlgos.Values | Measure-Object -Property Count -Sum).Sum -gt 0) {
		$sumprofit = (($KnownAlgos.Values | ForEach-Object { ($_.Values | Where-Object { $_.Item -and $_.Item.Profit -gt 0 } | Select-Object @{ Name = "Profit"; Expression = { $_.Item.Profit } } |
			Measure-Object Profit -Maximum) }) | Measure-Object -Property Maximum -Sum).Sum
		if ($global:HasConfirm -eq $true) {
			Write-Host "Rig profit: $([decimal]::Round($sumprofit, 8))"
		}
		[bool] $save = $false
		$Algos.Values | Where-Object { $_.Profit -eq 0 -and [decimal]$_.Password -gt 0 -and $Cfg.DisabledAlgorithms -notcontains $_.Algorithm } | ForEach-Object {
			$Algo = $_
			$Speed = (($KnownAlgos.Values | Foreach-Object { $t = $_[$Algo.Algorithm]; if ($t -and $t.Item -and $t.Item.Profit -gt 0) { $t.Item } }) |
				Measure-Object Speed -Sum).Sum
			$profit = $Speed * $Algo.Price
			if ($profit -gt $sumprofit) {
				Write-Host "$($Algo.Algorithm) profit at last 10 rents or suggested price is $([decimal]::Round($profit, 8)), rented $("{0:N1}" -f [decimal]$_.Password)% $($Algo.Info)"
				if ($global:HasConfirm -eq $true) {
					if (Get-Question "Add rig to MRR for algorithm '$($Algo.Algorithm)'") {
						$prms = @{
							"name" = "$($whoami.username) $($Config.WorkerName) under MindMiner"
							"hash" = @{ "hash" = $Speed; "type" = "hash" }
							"type" = $Algo.User
							"server" = $server.name
							"minhours" = 4
							"maxhours" = 12
							"status" = "enabled"
							"price" = @{ "type" = "hash"; "btc" = @{ "price" = $Algo.Price } }
						}
						if ($Cfg.Wallets) {
							$Cfg.Wallets | Where-Object { [Config]::MRRWallets -contains $_ } | ForEach-Object {
								$prms.price."$_" = @{ "enabled" = $true; "autoprice" = $true }
							}
						}
						$mrr.Put("/rig", $prms)
					}
					else {
						$Cfg.DisabledAlgorithms += $Algo.Algorithm
						$save = $true
					}
				}
				else {
					$global:NeedConfirm = $true
				}
			}
		}
		if ($save) {
			[BaseConfig]::Save($configpath, $Cfg)
		}
	}

	# info as standart pool
	$PoolInfo.HasAnswer = $true
	$PoolInfo.AnswerTime = [DateTime]::Now
}
catch {
	Write-Host $_
}
finally {
	if ($mrr) {	$mrr.Dispose() }
}

return $PoolInfo