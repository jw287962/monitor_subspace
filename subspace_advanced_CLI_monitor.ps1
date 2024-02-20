<#  ------------------------------------------------------------------------------------------------
	Script location on Github: https://github.com/irbujam/ss_log_event_monitor
	--------------------------------------------------------------------------------------------- #>

##header
$host.UI.RawUI.WindowTitle = "Subspace Advanced CLI Process Monitor"
function main {
	$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	$gitVersion = fCheckGitNewVersion
	$_refresh_duration_default = 30
	$refreshTimeScaleInSeconds = 0		# defined in config, defaults to 30 if not provided
	#
	$_b_console_disabled = $false
	####
	$_b_listener_running = $false
	$_api_enabled = "N"
	$_api_host = ""
	$_api_host_ip = ""
	$_api_host_port = ""
	$_url_prefix_listener = ""
	$_b_request_processed = $false
	#
	$_alert_stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	####
	$_allOutput = ""

	$_total_spacer_length = $_total_spacer_length = ("-----------------------------------------------------------------------------------------").Length
	$_url_telegram = ""
	$_chat_id = ""
	Clear-Host
	
	try {
		while ($true) {
			
			Clear-Host
			$_b_first_time = $True
			$_line_spacer_color = "gray"
			$_farmer_header_color = "cyan"
			$_farmer_header_data_color = "yellow"
			$_disk_header_color = "white"
			$_html_red = "red"
			$_html_green = "green"
			$_html_blue = "blue"
			$_html_black = "black"
			$_html_yellow = "yellow"

			$_farmers_metrics_raw_arr = [System.Collections.ArrayList]@()
			$_node_metrics_raw_arr = [System.Collections.ArrayList]@()

			$_configFile = "./config.txt"
			$_farmers_ip_arr = Get-Content -Path $_configFile | Select-String -Pattern "="

			for ($arrPos = 0; $arrPos -lt $_farmers_ip_arr.Count; $arrPos++)
			{
				if ($_farmers_ip_arr[$arrPos].toString().Trim(' ') -ne "" -and $_farmers_ip_arr[$arrPos].toString().IndexOf("#") -lt 0) {
					$_config = $_farmers_ip_arr[$arrPos].toString().split("=").Trim(" ")
					
					$_process_type = $_config[0].toString()
					if ($_process_type.toLower().IndexOf("enable-api") -ge 0) { $_api_enabled = $_config[1].toString()}
					elseif ($_process_type.toLower().IndexOf("api-host") -ge 0) {$_api_host = $_config[1].toString() + ":"}
					elseif ($_process_type.toLower().IndexOf("refresh") -ge 0) {

						$refreshTimeScaleInSeconds = [int]$_config[1]
						if ($refreshTimeScaleInSeconds -eq 0 -or $refreshTimeScaleInSeconds -eq "" -or $refreshTimeScaleInSeconds -eq $null) {$refreshTimeScaleInSeconds = $_refresh_duration_default}
					}
				}
			}
			###Check if API mode enabled and we have a host
			if ($_api_enabled.toLower() -eq "y" -and $_api_host -ne $null -and $_api_host -ne "")
			{
				$_b_console_disabled = $true

				if ($_b_request_processed -eq $false) 
				{
					#### create listener object for later use
					# create a listener for inbound http request
					$_api_host_arr = $_api_host.split("=").Trim(" ")
					# $_api_host_ip = $_api_host_arr[0]
					# $_api_host_port = $_api_host_arr[1]
					
					# Should work with just that due to split on '='
					$_api_host_url = $_api_host_arr
					# if ($_api_host_ip -eq "0.0.0.0" ){ $_api_host_url = "*:" + $_api_host_port }
					
					$_url_prefix = "http://" + $_api_host_url + "/"
					$_url_prefix_listener = $_url_prefix.toString().replace("http://127.0.0.1", "http://localhost")
					#Write-Host ("_url_prefix_listener: " + $_url_prefix_listener)

					$_http_listener = New-Object System.Net.HttpListener
					$_http_listener.Prefixes.Add($_url_prefix_listener)

					$_http_listener.Start()
					$_b_listener_running = $true
				}
				# wait for request - async
				$_prompt_listening_mode = "Ready to Listen, please open statistics using url: " + $_url_prefix_listener + "summary"
				Write-Host -NoNewline ("`r {0} " -f $_prompt_listening_mode) -ForegroundColor White
				$_context_task = $_http_listener.GetContextAsync()
				#$_context_task = $_http_listener.GetContext()
			}
			#Write-Host "_b_console_disabled: " $_b_console_disabled
			#Write data to appropriate destination

			
			if ($_b_console_disabled) {
				$_b_request_processed = fInvokeHttpRequestListener  $_farmers_ip_arr $_context_task $_alert_stopwatch
				#$_http_listener.Close()	
			}
			else{
				fWriteDataToConsole $_farmers_ip_arr $_alert_stopwatch
							
				fStartCountdownTimer $refreshTimeScaleInSeconds
			}

			
		
			
			###### Auto refresh
			$HoursElapsed = $Stopwatch.Elapsed.TotalHours
			if ($HoursElapsed -ge 1) {
				$gitNewVersion = fCheckGitNewVersion
				if ($gitNewVersion) {
					$gitVersion = $gitNewVersion
				}
				$Stopwatch.Restart()
			}
			######
		}
	}
	finally 
	{
		if ($_b_listener_running -eq $true) 
		{
			$_http_listener.Close()	
			Write-Host ""
			Write-Host " Listener stopped, exiting..." -ForegroundColor $_html_yellow
		}
	}
}

function fInvokeHttpRequestListener ([array]$_io_farmers_ip_arr, [object]$_io_context_task, [object]$_io_alert_stopwatch) {
	$_io_html = $null
	$_font_size = 5
	
	while (!($_context_task.AsyncWaitHandle.WaitOne(200))) { 

			$_seconds_elapsed = $_alert_stopwatch.Elapsed.TotalSeconds
			#Write-Host "_seconds_elapsed: " $_seconds_elapsed
			#Write-Host "refreshTimeScaleInSeconds: " $refreshTimeScaleInSeconds
			#Write-Host "alert overdue?: " ($_seconds_elapsed -ge $refreshTimeScaleInSeconds)
			if ($_seconds_elapsed -ge $refreshTimeScaleInSeconds) {
					$_io_html = fBuildHtml $_io_farmers_ip_arr $_io_alert_stopwatch
					$_alert_stopwatch.Restart()
			}
	}
	## process request received
	$_context = $_context_task.GetAwaiter().GetResult()
	$_io_html = fBuildHtml $_io_farmers_ip_arr $_io_alert_stopwatch
	#$_context = $_io_context_task
	
	# read request properties
	$_request_method = $_context.Request.HttpMethod
	$_request_url = $_context.Request.Url
	
	# adjust matching for localhost url flavours
	$_request_url_for_matching = $_request_url.toString().replace("http://127.0.0.1", "http://localhost")
	$_request_url_endpoint = ($_request_url_for_matching -split $_api_host_port)[1]

	# set and send response 
	$_context.Response.StatusCode = 200
	if (($_request_method -eq "GET" -or $_request_method -eq "get") -and $_request_url_endpoint.toLower() -eq "/summary") {
		$_console_log =  "valid url: " + $_request_url + ", method: " + $_request_method
		#Write-Host $_console_log
		$_response = $_io_html
		if ($_response) {
			$_response_bytes = [System.Text.Encoding]::UTF8.GetBytes($_response)
			$_context.Response.OutputStream.Write($_response_bytes, 0, $_response_bytes.Length)
		}
	}
	#else {
	#	$_console_log =  "invalid url: " + $_request_url + ", method: " + $_request_method
	#	#Write-Host $_console_log
	#	$_response = "<html><body>Invalid url...</body></html>"
	#	$_response_bytes = [System.Text.Encoding]::UTF8.GetBytes($_response)
	#	$_context.Response.OutputStream.Write($_response_bytes, 0, $_response_bytes.Length)
	#}

	# end response and close listener
	#Start-Sleep -Milliseconds 200
	#Start-Sleep -Seconds 1
	$_context.Response.Close()
	
	return $true 
}

Function fStartCountdownTimer ([int]$_io_timer_duration) {
	$_sleep_interval_milliseconds = 1000
	$_spinner = '|', '/', '—', '\'
	$_spinnerPos = 0
	$_end_dt = [datetime]::UtcNow.AddSeconds($_io_timer_duration)
	[System.Console]::CursorVisible = $false
	
	while (($_remaining_time = ($_end_dt - [datetime]::UtcNow).TotalSeconds) -gt 0) {
		Write-Host -NoNewline ("`r {0} " -f $_spinner[$_spinnerPos++ % 4]) -ForegroundColor White 
		#Write-Host -NoNewLine ("Refreshing in {0,3} seconds..." -f [Math]::Ceiling($_remaining_time))
		Write-Host "Refreshing in " -NoNewline 
		Write-Host ([Math]::Ceiling($_remaining_time)) -NoNewline -ForegroundColor black -BackgroundColor gray
		Write-Host " seconds..." -NoNewline 
		Start-Sleep -Milliseconds ([Math]::Min($_sleep_interval_milliseconds, $_remaining_time * 1000))
	}
	Write-Host
}

function fGetElapsedTime ([object]$_io_obj) {
	$_time_in_seconds = 0
	if ($_io_obj) {
		$_time_in_seconds = $_io_obj.Uptime
	}
	$_resp_total_uptime =  New-TimeSpan -seconds $_time_in_seconds
	
	return $_resp_total_uptime
}

function fBuildDynamicSpacer ([int]$ioSpacerLength, [string]$ioSpaceType) {
	$dataSpacerLabel = ""
	for ($k=1;$k -le $ioSpacerLength;$k++) {
		$dataSpacerLabel = $dataSpacerLabel + $ioSpaceType
	}
	return $dataSpacerLabel
}

function fPingMetricsUrl ([string]$ioUrl) {
	.{
		$_response = ""
		$_fullUrl = "http://" + $ioUrl + "/metrics"
		try {
			$farmerObj = Invoke-RestMethod -Method 'GET' -uri $_fullUrl
			if ($farmerObj) {
				$_response = $farmerObj.toString()
			}
		}
		catch {}
	}|Out-Null
	return $_response
}

function fParseMetricsToObj ([string]$_io_rest_str) {

	$_rest_arr = $_io_rest_str -split "# HELP"

	[array]$_response_metrics = $null
	foreach ($_rest_arr_element in $_rest_arr)
	{
		$_part_arr = $_rest_arr_element -split "`n"

		$Help = $_part_arr[0]
		$Type = $_part_arr[1]
		for ($_arr_pos = 2; $_arr_pos -lt $_part_arr.Count; $_arr_pos++)
		{
			$Criteria = ""
			$_part = $_part_arr[$_arr_pos].toString()
			if ($_arr_pos -eq 2 -and $_part.toLower().IndexOf(" unit ") -lt 0 -and $_part.Trim(' ') -ne "" -and $_part.toLower().IndexOf("eof") -lt 0)
			{
				# label
				[array]$_value_arr = ($Type -split ' ').Trim('#')
				$ValueName = $_value_arr[2]
				$LabelName = $_value_arr[1]
				$LabelValue = $null
				$Value = $_value_arr[3]
				
				$_metric = [PSCustomObject]@{
					Name		 = $ValueName
					Id			 = $LabelName
					Instance	 = $LabelValue
					Value		 = $Value
				}
				$_response_metrics += $_metric
				# data
				$_value_arr = ($_part -split ' ')
				$ValueName = $_value_arr[0]
				$LabelName = $null
				$LabelValue = $null
				$Value = $_value_arr[1]
				
				$_metric = [PSCustomObject]@{
					Name		 = $ValueName
					Id			 = $LabelName
					Instance	 = $LabelValue
					Value		 = $Value
				}
				$_response_metrics += $_metric
			}
			elseif ($_part.Trim(' ') -ne "" -and $_part.toLower().IndexOf("eof") -lt 0)
			{
				[array]$_value_arr = ($_part -split '[{}]').Trim(' ')
				#
				if ($_value_arr.Count -ne 1) 							# data with identifer
				{
					$ValueName = $_value_arr[0]
					$Label = $_value_arr[1] -split "="
					$LabelName = $Label[0]
					$LabelValue = $Label[1] -replace '"',''
					$Value = $_value_arr[2]
					$Criteria = $Label[2]
				}
				elseif ($_part.IndexOf("#") -lt 0)						# data no identifer
				{
					$_value_arr = ($_part -split ' ')
					$ValueName = $_value_arr[0]
					$LabelName = $null
					$LabelValue = $null
					$Value = $_value_arr[1]
				}
				else
				{														# unit label
					$_value_arr = ($_part -split ' ').Trim('#')
					$ValueName = $_value_arr[2]
					$LabelName = $_value_arr[1]
					$LabelValue = $null
					$Value = $_value_arr[3]
				}
				$_metric = [PSCustomObject]@{
					Name		 = $ValueName
					Id			 = $LabelName
					Instance	 = $LabelValue
					Value		 = $Value
					Criteria	 = $Criteria
				}
				$_response_metrics += $_metric
			}
		}
	}
	return $_response_metrics
}

function fGetNodeMetrics ([array]$_io_node_metrics_arr) {
	$_resp_node_metrics_arr = [System.Collections.ArrayList]@()

	[array]$_node_sync_arr = $null
	[array]$_node_peers_arr = $null

	$_chain_id_sync = ""
	$_chain_id_peer = ""
	$_node_sync_status = 0
	$_node_peer_count = 0
	#
	foreach ($_metrics_obj in $_io_node_metrics_arr)
	{
		if ($_metrics_obj.Name.IndexOf("substrate_sub_libp2p_is_major_syncing") -ge 0 -and $_metrics_obj.Name.IndexOf("chain") -ge 0) 
		{
			$_node_sync_status = $_metrics_obj.Value
			$_chain_id_sync = $_metrics_obj.Instance
			$_node_sync_info = [PSCustomObject]@{
				Id			= $_chain_id_sync
				State		= $_node_sync_status
			}
			$_node_sync_arr += $_node_sync_info
		}
		elseif ($_metrics_obj.Name.IndexOf("substrate_sub_libp2p_peers_count") -ge 0 -and $_metrics_obj.Name.IndexOf("chain") -ge 0) 
		{
			$_node_peer_count = $_metrics_obj.Value
			$_chain_id_peer = $_metrics_obj.Instance
			$_node_peer_info = [PSCustomObject]@{
				Id				= $_chain_id_peer
				Connected		= $_node_peer_count
			}
			$_node_peers_arr += $_node_peer_info
		}
	}
	#
	$_node_metrics = [PSCustomObject]@{
		Sync		= $_node_sync_arr
		Peers		= $_node_peers_arr
	}
	[void]$_resp_node_metrics_arr.add($_node_metrics)

	return $_resp_node_metrics_arr
}

function fGetDiskSectorPerformance ([array]$_io_farmer_metrics_arr) {
	$_resp_disk_metrics_arr = [System.Collections.ArrayList]@()

	[array]$_resp_UUId_arr = $null
	[array]$_resp_sector_perf_arr = $null
	[array]$_resp_rewards_arr = $null
	[array]$_resp_misses_arr = $null
	[array]$_resp_plots_completed_arr = $null
	[array]$_resp_plots_remaining_arr = $null

	$_unit_type = ""
	$_unique_farm_id = ""
	$_farmer_disk_id = ""
	$_farmer_disk_sector_plot_time = 0.00
	$_farmer_disk_sector_plot_count = 0
	$_total_sectors_plot_count = 0
	$_uptime_seconds = 0
	$_total_sectors_plot_time_seconds = 0
	$_total_disk_per_farmer = 0
	#
	$_farmer_disk_id_rewards = ""
	$_farmer_disk_proving_success_count = 0
	$_farmer_disk_proving_misses_count = 0
	$_total_rewards_per_farmer = 0
	#
	foreach ($_metrics_obj in $_io_farmer_metrics_arr)
	{
		if ($_metrics_obj.Name.IndexOf("subspace_farmer_sectors_total_sectors") -ge 0 -and $_metrics_obj.Id.IndexOf("farm_id") -ge 0) 
		{
			$_plot_id = ($_metrics_obj.Instance -split ",")[0]
			$_plot_state = $_metrics_obj.Criteria.ToString().Trim('"')
			$_sectors = $_metrics_obj.Value
			
			$_plots_info = [PSCustomObject]@{
				Id			= $_plot_id
				PlotState	= $_plot_state
				Sectors		= $_sectors
			}
			if ($_plot_state.toLower() -eq "notplotted") {
				$_resp_plots_remaining_arr += $_plots_info
			}
			elseif ($_plot_state.toLower() -eq "plotted") {
				$_resp_plots_completed_arr += $_plots_info
			}
		}
		elseif ($_metrics_obj.Name.IndexOf("subspace_farmer_auditing_time_seconds_count") -ge 0 -and $_metrics_obj.Id.IndexOf("farm_id") -ge 0) 
		{
			$_uptime_seconds = $_metrics_obj.Value
			$_unique_farm_id = $_metrics_obj.Instance
			$_farm_id_info = [PSCustomObject]@{
				Id		= $_unique_farm_id
			}
			$_resp_UUId_arr += $_farm_id_info
		}
		elseif ($_metrics_obj.Name.IndexOf("subspace_farmer_sector_plotting_time_seconds") -ge 0)
		{
			if ($_metrics_obj.Id.toLower().IndexOf("unit") -ge 0 -or $_metrics_obj.Id.toLower().IndexOf("type") -ge 0)
			{
				$_unit_type = $_metrics_obj.Value.toLower()
				$_farmer_disk_id = ""
			}
			elseif ($_metrics_obj.Id.IndexOf("farm_id") -ge 0) 
			{
				$_farmer_disk_id = $_metrics_obj.Instance
				if ($_metrics_obj.Name.toLower().IndexOf("sum") -ge 0) { $_farmer_disk_sector_plot_time = [double]($_metrics_obj.Value) }
				if ($_metrics_obj.Name.toLower().IndexOf("count") -ge 0) { $_farmer_disk_sector_plot_count = [int]($_metrics_obj.Value) }
				if ($_farmer_disk_sector_plot_time -gt 0 -and $_farmer_disk_sector_plot_count -gt 0) 
				{
					$_sectors_per_hour = 0.0
					$_minutes_per_sector = 0.0
					switch ($_unit_type) {
						"seconds" 	{
							$_sectors_per_hour = [math]::Round(($_farmer_disk_sector_plot_count * 3600) / $_farmer_disk_sector_plot_time, 1)
							$_minutes_per_sector = [math]::Round($_farmer_disk_sector_plot_time / ($_farmer_disk_sector_plot_count * 60), 1)
							$_total_sectors_plot_time_seconds += $_farmer_disk_sector_plot_time
						}
						"minutes" 	{
							$_sectors_per_hour = [math]::Round($_farmer_disk_sector_plot_count / $_farmer_disk_sector_plot_time, 1)
							$_minutes_per_sector = [math]::Round($_farmer_disk_sector_plot_time / $_farmer_disk_sector_plot_count, 1)
							$_total_sectors_plot_time_seconds += ($_farmer_disk_sector_plot_time * 60)
						}
						"hours" 	{
							$_sectors_per_hour = [math]::Round($_farmer_disk_sector_plot_count / ($_farmer_disk_sector_plot_time * 60), 1)
							$_minutes_per_sector = [math]::Round(($_farmer_disk_sector_plot_time * 60) / $_farmer_disk_sector_plot_count, 1)
							$_total_sectors_plot_time_seconds += ($_farmer_disk_sector_plot_time * 3600)
						}
					}
					$_total_disk_per_farmer += 1
					
					$_farmer_disk_sector_plot_time = 0.00
					$_farmer_disk_sector_plot_count = 0
					#
					$_disk_sector_perf = [PSCustomObject]@{
						Id					= $_farmer_disk_id
						SectorsPerHour		= $_sectors_per_hour
						MinutesPerSector	= $_minutes_per_sector
					}
					$_resp_sector_perf_arr += $_disk_sector_perf
				}
			}
		}
		elseif ($_metrics_obj.Name.IndexOf("subspace_farmer_sector_plotted_counter_sectors_total") -ge 0) 
		{
			$_total_sectors_plot_count = [int]($_metrics_obj.Value) 
		}
		elseif ($_metrics_obj.Name.IndexOf("subspace_farmer_proving_time_seconds") -ge 0)
		{
			if ($_metrics_obj.Id.toLower().IndexOf("unit") -ge 0 -or $_metrics_obj.Id.toLower().IndexOf("type") -ge 0)
			{
				$_farmer_disk_id_rewards = ""
			}
			elseif ($_metrics_obj.Id.IndexOf("farm_id") -ge 0 -and $_metrics_obj.Name.toLower().IndexOf("count") -ge 0) 
			{
				$_farmer_id = $_metrics_obj.Instance -split ","
				$_farmer_disk_id_rewards = $_farmer_id[0]
				if ($_metrics_obj.Criteria.toLower().IndexOf("success") -ge 0) {
					$_farmer_disk_proving_success_count = [int]($_metrics_obj.Value)
					
					$_disk_rewards_metric = [PSCustomObject]@{
						Id		= $_farmer_disk_id_rewards
						Rewards	= $_farmer_disk_proving_success_count
						#Misses	= $_farmer_disk_proving_misses_count
					}
					$_resp_rewards_arr += $_disk_rewards_metric
				}
				elseif ($_metrics_obj.Criteria.toLower().IndexOf("timeout") -ge 0) {
					$_farmer_disk_proving_misses_count = [int]($_metrics_obj.Value)
					
					$_disk_misses_metric = [PSCustomObject]@{
						Id		= $_farmer_disk_id_rewards
						#Rewards	= $_farmer_disk_proving_success_count
						Misses	= $_farmer_disk_proving_misses_count
					}
					$_resp_misses_arr += $_disk_misses_metric
				}
				$_total_rewards_per_farmer += $_farmer_disk_proving_success_count
				#
				#
				$_farmer_disk_proving_success_count = 0
				$_farmer_disk_proving_misses_count = 0
			}
		}
	}
	#
	$_disk_sector_perf = [PSCustomObject]@{
		Id					= "overall"
		TotalSectors		= $_total_sectors_plot_count
		TotalSeconds		= $_total_sectors_plot_time_seconds
		TotalDisks			= $_total_disk_per_farmer
		Uptime				= $_uptime_seconds
		TotalRewards		= $_total_rewards_per_farmer
	}
	$_resp_sector_perf_arr += $_disk_sector_perf

	$_disk_metrics = [PSCustomObject]@{
		Id				= $_resp_UUId_arr
		Performance		= $_resp_sector_perf_arr
		Rewards			= $_resp_rewards_arr
		Misses			= $_resp_misses_arr
		PlotsCompleted	= $_resp_plots_completed_arr
		PlotsRemaining	= $_resp_plots_remaining_arr
	}
	[void]$_resp_disk_metrics_arr.add($_disk_metrics)

	#return $_resp_sector_perf_arr
	#return $_resp_rewards_arr



	return $_resp_disk_metrics_arr
}

function fSendDiscordNotification ([string]$ioUrl, [string]$ioMsg) {
	$JSON = @{ "content" = $ioMsg; } | convertto-json
	Invoke-WebRequest -uri $ioUrl -Method POST -Body $JSON -Headers @{'Content-Type' = 'application/json'} 

}

function fSendTelegramNotification ([string]$ioUrl, [string]$ioMsg) {
	 $TelegramData = @{
        chat_id = $_chat_id
        text = $ioMsg
		parse_mode = "HTML"
    } | convertto-json
	try{
	
	$response = Invoke-WebRequest -Uri $ioUrl -Method Post -Body $TelegramData -ContentType "application/json" 
	if ($response.StatusCode -eq 200) {
        # Write-Host "Telegram Request was successful: $($response.StatusDescription)"
    } else {
        Write-Host "Telegram Request failed: $($response)"
    }
	}catch{
		Write-Host "An error occurred: $_ $($response) "
	}
	}

function fGetProcessState ([string]$_io_process_type, [string]$_io_host_ip, [string]$_io_hostname, [string]$_io_alert_url, [object]$_io_alert_sw, [string]$_url_telegram) {
	$_resp_process_state_arr = [System.Collections.ArrayList]@()

	$_b_process_running_state = $False
	#
	# get process state, send notification if process is stopped/not running
	$_resp = fPingMetricsUrl $_io_host_ip		# needs to be outside of elapsed time check as response is used downstream to eliminiate dup call
	if ($_resp -eq "") {
		$_alert_text = $_io_process_type + " status: Stopped, Hostname:" + $_io_hostname
		try {
			# fSendDiscordNotification $_io_alert_url $_alert_text
			fSendTelegramNotification $_url_telegram $_alert_text
		}
		catch {}
		#
		$_b_process_running_state = $False
	}
	else { $_b_process_running_state = $True }

	[void]$_resp_process_state_arr.add($_resp)
	[void]$_resp_process_state_arr.add($_b_process_running_state)

	return $_resp_process_state_arr
}

function fCheckGitNewVersion {
	.{
		$gitVersionArr = [System.Collections.ArrayList]@()
		$gitVersionCurrObj = Invoke-RestMethod -Method 'GET' -uri "https://api.github.com/repos/subspace/subspace/releases/latest" 2>$null
		if ($gitVersionCurrObj) {
			$tempArr_1 = $gitVersionArr.add($gitVersionCurrObj.tag_name)
			$gitNewVersionReleaseDate = (Get-Date $gitVersionCurrObj.published_at).ToLocalTime() 
			$tempArr_1 = $gitVersionArr.add($gitNewVersionReleaseDate)
		}
	}|Out-Null
	return $gitVersionArr
}

function fWriteDataToConsole ([array]$_io_farmers_ip_arr, [object]$_io_stopwatch) {
	$_url_discord = ""
	
	for ($arrPos = 0; $arrPos -lt $_io_farmers_ip_arr.Count; $arrPos++)
	{
	
		$_farmer_metrics_raw = ""
		$_node_metrics_raw = ""
		[array]$_process_state_arr = $null
		if ($_io_farmers_ip_arr[$arrPos].toString().Trim(' ') -ne "" -and $_io_farmers_ip_arr[$arrPos].toString().IndexOf("#") -lt 0) {
			$_config = $_io_farmers_ip_arr[$arrPos].toString().split("=").Trim(" ")
			$_process_type = $_config[0].toString()
			
			if ($_process_type.toLower().IndexOf("chat_id") -ge 0) { $_chat_id =  +[Double]$_config[1]
			}

			if ($_process_type.toLower().IndexOf("telegram") -ge 0) { $_url_telegram = $_config[1].toString()

			}	
			if ($_process_type.toLower().IndexOf("discord") -ge 0) { $_url_discord = $_config[1].toString()
				}
			elseif ($_process_type.toLower() -eq "node" -or $_process_type.toLower() -eq "farmer") { 
				$_host_ip = $_config[1].toString()
				# $_host_port = $_config[2].toString()
				$_host_url = $_host_ip
				$_hostname = ""
				
				## Experimental
				## Message: start changes here in case of host name resolution related issues while using this tool
				#
				# START COMMENT - Type # in front of the line until the line where it says "STOP COMMENT"
				## What is happening here is an attempt to hide IP info on screen display and use hostname instead
				#try {
				#	$_hostname_obj = [system.net.dns]::gethostentry($_host_ip)
				#	$_hostname = $_hostname_obj.NameHost
				#}
				#catch 
				#{
				#	$_hostname = $_host_ip
				#}
				# STOP COMMENT - Remove the # in front of the next 1 line directly below this line, this will display IP in display
				$_hostname = $_host_ip

				$_process_state_arr = fGetProcessState $_process_type $_host_url $_hostname $_url_discord $_io_stopwatch
				$_b_process_running_ok = $_process_state_arr[1]
				
				$_node_peers_connected = 0
				if ($_process_type.toLower() -eq "farmer") {
					# $_total_spacer_length = ("--------------------------------------------------------------------------------------------------------").Length
					$_spacer_length = $_total_spacer_length
					$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
					Write-Host $_label_spacer -ForegroundColor $_line_spacer_color
					#echo `n
				}
				else {				# get node metrics
					$_node_metrics_raw = $_process_state_arr[0]
					[void]$_node_metrics_raw_arr.add($_node_metrics_raw)
					$_node_metrics_formatted_arr = fParseMetricsToObj $_node_metrics_raw_arr[$_node_metrics_raw_arr.Count - 1]
	
					$_node_metrics_arr = fGetNodeMetrics $_node_metrics_formatted_arr
					$_node_sync_state = $_node_metrics_arr[0].Sync.State
					$_node_peers_connected = $_node_metrics_arr[0].Peers.Connected
				}
				
				$_console_msg = $_process_type + " status: "
				Write-Host $_console_msg -nonewline -ForegroundColor $_farmer_header_color
				$_console_msg = ""
				$_console_msg_color = ""
				if ($_b_process_running_ok -eq $True) {
					$_console_msg = "Running"
					$_console_msg_color = $_html_green
				}
				else {
					$_console_msg = "Stopped"
					$_console_msg_color = $_html_red
				}
				Write-Host $_console_msg -ForegroundColor $_console_msg_color -nonewline
				Write-Host ", " -nonewline
				Write-Host "Hostname: " -nonewline -ForegroundColor $_farmer_header_color
				Write-Host $_hostname -nonewline -ForegroundColor $_farmer_header_data_color
				

				if ($_process_type.toLower() -eq "node") {
					Write-Host ", " -nonewline
					Write-Host "Synced: " -nonewline -ForegroundColor $_farmer_header_color
					$_node_sync_state_disp_color = $_html_green
					$_node_sync_state_disp = "Yes"
					if ($_node_sync_state -eq $null) {
						$_node_peers_connected = "-"
						$_node_sync_state_disp = "-"
						$_node_sync_state_disp_color = $_html_red
					}
					elseif ($_node_sync_state -eq 1 -or $_b_process_running_ok -ne $true) {
						$_node_sync_state_disp = "No"
						$_node_sync_state_disp_color = $_html_red
					}
					Write-Host $_node_sync_state_disp -nonewline -ForegroundColor $_node_sync_state_disp_color
					Write-Host ", " -nonewline
					Write-Host "Peers: " -nonewline -ForegroundColor $_farmer_header_color
					Write-Host $_node_peers_connected -ForegroundColor $_farmer_header_data_color
				}
			}
			#elseif ($_process_type.toLower().IndexOf("refresh") -ge 0) {
			#	$refreshTimeScaleInSeconds = [int]$_config[1].toString()
			#	if ($refreshTimeScaleInSeconds -eq 0 -or $refreshTimeScaleInSeconds -eq "" -or $refreshTimeScaleInSeconds -eq $null) {$refreshTimeScaleInSeconds = 30}
			#}

			if ($_process_type.toLower() -ne "farmer") { continue }

			#$_farmer_metrics_raw = fPingMetricsUrl $_host_url
			$_farmer_metrics_raw = $_process_state_arr[0]
			[void]$_farmers_metrics_raw_arr.add($_farmer_metrics_raw)
			$_farmer_metrics_formatted_arr = fParseMetricsToObj $_farmers_metrics_raw_arr[$_farmers_metrics_raw_arr.Count - 1]
			
			# header lables
			$_b_write_header = $True
			#
			$_label_hostname = "Hostname"
			$_label_diskid = "Disk Id"
			$_label_size = "Size    "
			$_label_percent_complete = "% Comp."
			$_label_eta = "ETA(Hrs)"
			$_label_sectors_per_hour = "Sectors/Hr"
			$_label_minutes_per_sectors = "Min/Sector"
			$_label_rewards = "Reward"
			$_label_misses = "Miss"
			$_spacer = " "
			$_total_header_length = $_label_size.Length + $_label_percent_complete.Length + $_label_eta.Length + $_label_sectors_per_hour.Length + $_label_minutes_per_sectors.Length + $_label_rewards.Length + $_label_misses.Length
			$_total_header_labels = 8
			
			#
			
			##
			$_disk_metrics_arr = fGetDiskSectorPerformance $_farmer_metrics_formatted_arr
			$_disk_UUId_arr = $_disk_metrics_arr[0].Id
			$_disk_sector_performance_arr = $_disk_metrics_arr[0].Performance
			$_disk_rewards_arr = $_disk_metrics_arr[0].Rewards
			$_disk_misses_arr = $_disk_metrics_arr[0].Misses
			$_disk_plots_completed_arr = $_disk_metrics_arr[0].PlotsCompleted
			$_disk_plots_remaining_arr = $_disk_metrics_arr[0].PlotsRemaining

			
			
			
			# Write uptime information to console
			foreach ($_disk_sector_performance_obj in $_disk_sector_performance_arr)
			{
				
				if ($_disk_sector_performance_obj) {
					if ($_disk_sector_performance_obj.Id -eq "overall") {
						$_avg_sectors_per_hour = 0.0
						$_avg_minutes_per_sector = 0.0
						
						if ($_disk_sector_performance_obj.TotalSeconds -gt 0) {
						#if ($_disk_sector_performance_obj.TotalSeconds -and $_disk_sector_performance_obj.TotalSeconds -gt 0) {
							$_avg_sectors_per_hour = [math]::Round(($_disk_sector_performance_obj.TotalSectors * 3600)/ $_disk_sector_performance_obj.TotalSeconds, 1)
						}
						if ($_disk_sector_performance_obj.TotalSectors) {
							$_avg_minutes_per_sector = [math]::Round($_disk_sector_performance_obj.TotalSeconds / ($_disk_sector_performance_obj.TotalSectors * 60), 1)
						}
						Write-Host 
						$_total_sectors_per_hour = $_avg_sectors_per_hour*$_disk_sector_performance_obj.TotalDisks

						$_uptime = fGetElapsedTime $_disk_sector_performance_obj
						$_uptime_disp = $_uptime.days.ToString()+"d "+$_uptime.hours.ToString()+"h "+$_uptime.minutes.ToString()+"m "+$_uptime.seconds.ToString()+"s"
						$_OutputHTML = ""
						


						$_OutputHTML = "`n`n"
						switch ($arrPos) {
							9 {
								# If counter is 0, add "AMD 7950X" to $_Output
								$_OutputHTML += "AMD 7950X"
								break
							}
							10 {
								$_OutputHTML += "ROG STRIX Jas"
								break
							}
							# You can add more cases as needed
							default {
								$_OutputHTML += "Windows RogStrix"
								break
								# Default case if the counter is not 0
								# You can add additional logic here if needed
								break
							}
						}
						# OUTPUT HTML FOR TELEGRAM
						$_OutputHTML += ", <b>$($_uptime_disp)</b> Uptime, "
						$_OutputHTML += "`n <b>$($_total_sectors_per_hour)</b> Sectors/Hour, "
						$_OutputHTML += "`n <b>$($_avg_sectors_per_hour)</b> Sectors/Hour (avg/disk), "
						$_OutputHTML += "`n <b>$($_avg_minutes_per_sector)</b> Minutes/Sector (avg), "
						$_OutputHTML += "`n <b>$($_disk_sector_performance_obj.TotalRewards)</b> Total Rewards"


						$_OutputHTML += ""

						$_allOutput += "$_OutputHTML"

						# FOR PWSH CLI
						$_Output = ""
						$_Output += "Uptime: $($_uptime_disp)"
						$_Output += ", "
						$_Output += "Sectors/Hour (avg): $($_avg_sectors_per_hour.ToString())"
						$_Output += ", "
						$_Output += "Minutes/Sector (avg): $($_avg_minutes_per_sector.ToString())"
						$_Output += ", "
						$_Output += "Rewards: $($_disk_sector_performance_obj.TotalRewards.ToString())"

						$_Output
						# Write-Host $_OutputHTML
						
						break
					}
					
				}
			}
			
			# $_total_spacer_length = ("--------------------------------------------------------------------------------------------------------").Length
			$_spacer_length = $_total_spacer_length
			$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
			
			Write-Host $_label_spacer -ForegroundColor $_line_spacer_color

			#foreach ($_disk_sector_performance_obj in $_disk_sector_performance_arr)
			foreach ($_disk_UUId_obj in $_disk_UUId_arr)
			{
				# write header if not already done
				if ($_b_write_header -eq $True) {
					# Host name header info
					# draw line
					if ($_disk_UUId_obj -ne $null) {
						$_total_spacer_length = $_disk_UUId_obj.Id.toString().Length + $_total_header_length + $_total_header_labels + 2 	# 1 for leading and 1 for trailing
					}
					else {
						# $_total_spacer_length = ("------------------------------------------------------------------------").Length
					}
					$_spacer_length = $_total_spacer_length
					$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
					if ($_b_first_time -eq $True) {
						$_b_first_time = $False
					}
					 
					#
					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"

					Write-Host $_label_spacer -nonewline

					Write-Host $_label_diskid -nonewline -ForegroundColor $_disk_header_color
					if ($_disk_UUId_obj -ne $null) {
						$_spacer_length =  $_disk_UUId_obj.Id.toString().Length - $_label_diskid.Length + 1
					}
					else {$_spacer_length = ("------------------------------------------------------------------------").Length}

					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline 
					Write-Host $_label_size -nonewline -ForegroundColor $_disk_header_color

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline 
					Write-Host $_label_percent_complete -nonewline -ForegroundColor $_disk_header_color

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline 
					Write-Host $_label_eta -nonewline -ForegroundColor $_disk_header_color

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline 
					Write-Host $_label_sectors_per_hour -nonewline -ForegroundColor $_disk_header_color

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline
					Write-Host $_label_minutes_per_sectors -nonewline -ForegroundColor $_disk_header_color

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline
					Write-Host $_label_rewards -nonewline -ForegroundColor $_disk_header_color
					
					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline
					Write-Host $_label_misses -nonewline -ForegroundColor $_disk_header_color

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer
					#
					# draw line
					if ($_disk_UUId_obj -ne $null) {
						$_spacer_length =  $_disk_UUId_obj.Id.toString().Length + $_total_header_length + $_total_header_labels + 2 	# 1 for leading and 1 for trailing
					}
					else {$_spacer_length = ("------------------------------------------------------------------------").Length}
					$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
					Write-Host $_label_spacer -ForegroundColor $_line_spacer_color
					#
					$_b_write_header = $False
				}

				# write data table
				$_spacer_length = 0
				$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
				$_label_spacer = $_label_spacer + "|"

				Write-Host $_label_spacer -nonewline
				Write-Host $_disk_UUId_obj.Id -nonewline

				# get performance data - write after eta is calculated
				$_minutes_per_sector_data_disp = "-"
				$_sectors_per_hour_data_disp = "-"
				foreach ($_disk_sector_performance_obj in $_disk_sector_performance_arr)
				{
					if ($_disk_sector_performance_obj) {
						if ($_disk_sector_performance_obj.Id -eq "overall" -or $_disk_UUId_obj.Id -ne $_disk_sector_performance_obj.Id) { continue }
					}
					#
					$_minutes_per_sector_data_disp = $_disk_sector_performance_obj.MinutesPerSector.ToString()
					$_sectors_per_hour_data_disp = $_disk_sector_performance_obj.SectorsPerHour.ToString()
				}

				# write size, % progresion and ETA
				$_b_printed_size_metrics = $False
				$_size_data_disp = "-"
				$_plotting_percent_complete = "-"
				$_plotting_percent_complete_disp = "-"
				$_eta = "-"
				$_eta_disp = "-"
				foreach ($_disk_plots_completed_obj in $_disk_plots_completed_arr)
				{
					if ($_disk_plots_completed_obj) {
						if ($_disk_UUId_obj.Id -ne $_disk_plots_completed_obj.Id) { continue }
					}
					else {break}
					#
					$_size_data_disp = $_disk_plots_completed_obj.Sectors

					foreach ($_disk_plots_remaining_obj in $_disk_plots_remaining_arr)
					{
						if ($_disk_plots_remaining_obj) {
							if ($_disk_UUId_obj.Id -ne $_disk_plots_remaining_obj.Id) { continue }
						}
						else {break}
						
						$_reminaing_sectors = [int]($_disk_plots_remaining_obj.Sectors)
						$_completed_sectors = [int]($_disk_plots_completed_obj.Sectors)
						$_total_sectors_GiB = $_completed_sectors + $_reminaing_sectors
						$_total_disk_sectors_TiB = [math]::Round($_total_sectors_GiB / 1000, 2)
						$_total_disk_sectors_disp = $_total_disk_sectors_TiB.ToString() + " TiB"
						if ($_total_sectors_GiB -ne 0) {
							$_plotting_percent_complete = [math]::Round(($_completed_sectors / $_total_sectors_GiB) * 100, 1)
							$_plotting_percent_complete_disp = $_plotting_percent_complete.ToString() + "%"
						}
						if ($_minutes_per_sector_data_disp -ne "-") {
							$_eta = [math]::Round((([double]($_minutes_per_sector_data_disp) * $_reminaing_sectors)) / (60), 2)
							$_eta_disp = $_eta.toString()
						}
						
						$_spacer_length = 1
						$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
						$_label_spacer = $_label_spacer + "|"
						Write-Host $_label_spacer -nonewline
						Write-Host $_total_disk_sectors_disp -nonewline

						$_spacer_length = $_label_size.Length - $_total_disk_sectors_disp.Length
						$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
						$_label_spacer = $_label_spacer + "|"
						Write-Host $_label_spacer -nonewline
						Write-Host $_plotting_percent_complete_disp -nonewline

						$_spacer_length = $_label_percent_complete.Length - $_plotting_percent_complete_disp.Length
						$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
						$_label_spacer = $_label_spacer + "|"
						Write-Host $_label_spacer -nonewline
						Write-Host $_eta_disp -nonewline
					}

					$_b_printed_size_metrics = $True
				}
				if ($_b_printed_size_metrics -eq $False)
				{
					$_spacer_length = 1
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline
					Write-Host "-" -nonewline
					
					$_spacer_length = $_label_size.Length - ("-").Length
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline
					Write-Host "-" -nonewline

					$_spacer_length = $_label_percent_complete.Length - ("-").Length
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					Write-Host $_label_spacer -nonewline
					Write-Host "-" -nonewline
				}

				# write performance data
				$_spacer_length = $_label_eta.Length - $_eta_disp.Length
				$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
				$_label_spacer = $_label_spacer + "|"
			
				Write-Host $_label_spacer -nonewline
				Write-Host $_sectors_per_hour_data_disp -nonewline

				$_spacer_length = [int]($_label_sectors_per_hour.Length - $_sectors_per_hour_data_disp.Length)
				$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
				$_label_spacer = $_label_spacer + "|"
				
				Write-Host $_label_spacer -nonewline
				Write-Host $_minutes_per_sector_data_disp -nonewline
				
				$_b_counted_missed_rewards = $False
				$_b_data_printed = $False
				$_missed_rewards_count = 0
				$_missed_rewards_color = "white"
				$_b_reward_data_printed = $false
				$_rewards_data_disp = "-"
				foreach ($_disk_rewards_obj in $_disk_rewards_arr)
				{
					if ($_disk_UUId_obj.Id -ne $_disk_rewards_obj.Id) {
							continue
					}
					$_rewards_data_disp = $_disk_rewards_obj.Rewards.ToString()

					$_spacer_length = [int]($_label_minutes_per_sectors.Length - $_minutes_per_sector_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
				
					Write-Host $_label_spacer -nonewline
					Write-Host $_disk_rewards_obj.Rewards -nonewline
					
					$_b_reward_data_printed = $true
				}
				if ($_b_reward_data_printed -eq $false) 				# rewards not published yet in endpoint
				{
					$_spacer_length = [int]($_label_minutes_per_sectors.Length - $_minutes_per_sector_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					Write-Host $_label_spacer -nonewline
					Write-Host "-" -nonewline
				}


				$_b_misses_data_printed = $false
				foreach ($_disk_misses_obj in $_disk_misses_arr)
				{
					if ($_disk_UUId_obj.Id -ne $_disk_misses_obj.Id) {
							continue
					}
					
					if ($_disk_misses_obj.Misses -gt 0) {
						$_missed_rewards_color = $_html_red
					}
					
					$_spacer_length = [int]($_label_rewards.Length - $_rewards_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					Write-Host $_label_spacer -nonewline
					Write-Host $_disk_misses_obj.Misses -nonewline -ForegroundColor $_missed_rewards_color

					$_spacer_length = [int]($_label_misses.Length - $_disk_misses_obj.Misses.toString().Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					Write-Host $_label_spacer
					
					$_b_misses_data_printed = $true
				}
				if ($_b_misses_data_printed -eq $false) 				# misses not published yet in endpoint
				{
					# write data - combine missed and rewards into single line of display
					$_b_data_printed = $True

					$_spacer_length = [int]($_label_rewards.Length - $_rewards_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					Write-Host $_label_spacer -nonewline
					Write-Host 0 -nonewline		#no rewards data (only misses data) populated in endpoint

					$_spacer_length = [int]($_label_misses.Length - ("-").toString().Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					Write-Host $_label_spacer
				}	
						
			}
			#
		}
	
	}

	#
	# draw finish line
	if ($_disk_UUId_obj) {
		$_spacer_length =  $_disk_UUId_obj.Id.toString().Length + $_total_header_length + $_total_header_labels + 2 	# 1 for leading and 1 for trailing
	}
	else {$_spacer_length = ("------------------------------------------------------------------------").Length}
	$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"

	Write-Host $_label_spacer -ForegroundColor $_line_spacer_color
	# 
	# $_allOutput
	fSendTelegramNotification $_url_telegram $_allOutput

	
	# display latest github version info
	$_gitVersionDisp = " - "
	$_gitVersionDispColor = $_html_red
	if ($null -ne $gitVersion) {
		$currentVersion = $gitVersion[0] -replace "[^.0-9]"
		$_gitVersionDisp = $gitVersion[0]
		$_gitVersionDispColor = $_html_green
	}

	Write-Host "Latest github version : " -nonewline
	Write-Host "$($_gitVersionDisp)" -nonewline -ForegroundColor $_gitVersionDispColor
	
	##
	# display last refresh time 
	$currentDate = (Get-Date).ToLocalTime().toString()
	# Refresh
	echo `n
	Write-Host "Last refresh on: " -ForegroundColor Yellow -nonewline; Write-Host "$currentDate" -ForegroundColor Green;
	#
}

function fBuildHtml ([array]$_io_farmers_ip_arr, [object]$_io_alert_swatch) {
	$_url_discord = ""
	#### - build html before proceeding further
	#$_html = "<html><body>"
	$_html = '<html>
				<head>
				<meta name="viewport" content="width=device-width, initial-scale=1">
				<style>
				body {
				  #padding: 25px;
				  background-color: white;
				  color: black;
				  #font-size: 25px;
				}
				.dark-mode {
				  background-color: black;
				  color: white;
				}
				</style>
				</head>
				<button onclick="fToggleDisplayMode()"><font size=4>Toggle dark mode</font></button>
				<script>
				function fToggleDisplayMode() {
				   var element = document.body;
				   element.classList.toggle("dark-mode");
				}
				</script>'
	$_html += "<body>"
	$_html += "<div class='body'>"
	#$_html += "<table border=0>"

	for ($arrPos = 0; $arrPos -lt $_io_farmers_ip_arr.Count; $arrPos++)
	{
		$_farmer_metrics_raw = ""
		$_node_metrics_raw = ""
		[array]$_process_state_arr = $null
		if ($_io_farmers_ip_arr[$arrPos].toString().Trim(' ') -ne "" -and $_io_farmers_ip_arr[$arrPos].toString().IndexOf("#") -lt 0) {
			$_config = $_io_farmers_ip_arr[$arrPos].toString().split("=").Trim(" ")
			$_process_type = $_config[0].toString()


			if ($_process_type.toLower().IndexOf("chat_id") -ge 0) { $_chat_id = [Double]$_config }
			if ($_process_type.toLower().IndexOf("discord") -ge 0) { $_url_discord = $_config[1].toString() 
			
			
			}
			elseif ($_process_type.toLower() -eq "node" -or $_process_type.toLower() -eq "farmer") { 
				$_host_ip = $_config[1].toString()
				# $_host_port = $_config[2.toString()
				$_host_url = $_host_ip
				$_hostname = ""
				
				## Experimental
				## Message: start changes here in case of host name resolution related issues while using this tool
				#
				# START COMMENT - Type # in front of the line until the line where it says "STOP COMMENT"
				## What is happening here is an attempt to hide IP info on screen display and use hostname instead
				#try {
				#	$_hostname_obj = [system.net.dns]::gethostentry($_host_ip)
				#	$_hostname = $_hostname_obj.NameHost
				#}
				#catch 
				#{
				#	$_hostname = $_host_ip
				#}
				# STOP COMMENT - Remove the # in front of the next 1 line directly below this line, this will display IP in display
				$_hostname = $_host_ip

				$_process_state_arr = fGetProcessState $_process_type $_host_url $_hostname $_url_discord $_io_alert_swatch $_url_telegram
				$_b_process_running_ok = $_process_state_arr[1]
				
				if ($_process_type.toLower() -eq "farmer") {
					# $_total_spacer_length = ("------------------------------------------------------------------------------").Length
					$_spacer_length = $_total_spacer_length
					$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
					$_html += "<br><br>"
				}
				else {				# get node metrics
					$_node_metrics_raw = $_process_state_arr[0]
					[void]$_node_metrics_raw_arr.add($_node_metrics_raw)
					$_node_metrics_formatted_arr = fParseMetricsToObj $_node_metrics_raw_arr[$_node_metrics_raw_arr.Count - 1]

					$_node_metrics_arr = fGetNodeMetrics $_node_metrics_formatted_arr
					$_node_sync_state = $_node_metrics_arr[0].Sync.State
					$_node_peers_connected = $_node_metrics_arr[0].Peers.Connected
				}
				
				$_console_msg = $_process_type + " status: "
				$_html += "<tr>"
				$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_console_msg +  "</td>"
				if ($_b_process_running_ok -eq $True) {
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + "Running" +  "</td>"
				}
				else {
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_red + "'>" + "Stopped" +  "</td>"
				}
				$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + ", " +  "</td>"
				$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Hostname: " +  "</td>"
				if ($_process_type.toLower() -eq "farmer") {
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_hostname +  "</td>"
				}
				else {
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_hostname +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + ", " +  "</td>"
					#$_html += "</tr>"
					#$_html += "<tr>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Synced: " +  "</td>"
					$_node_sync_state_disp_color = $_html_green
					$_node_sync_state_disp = "Yes"
					if ($_node_sync_state -eq $null) {
						$_node_peers_connected = "-"
						$_node_sync_state_disp = "-"
						$_node_sync_state_disp_color = $_html_red
					}
					elseif ($_node_sync_state -eq 1 -or $_b_process_running_ok -eq $false) {
						$_node_sync_state_disp = "No"
						$_node_sync_state_disp_color = $_html_red
					}
					$_html += "<td><font size='" + $_font_size + "' color='" + $_node_sync_state_disp_color + "'>" + $_node_sync_state_disp +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + ", " +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Peers: " +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_node_peers_connected +  "</td>"
					$_html += "</tr>"
				}
			}
			#elseif ($_process_type.toLower().IndexOf("refresh") -ge 0) {
			#	$refreshTimeScaleInSeconds = [int]$_config[1].toString()
			#	if ($refreshTimeScaleInSeconds -eq 0 -or $refreshTimeScaleInSeconds -eq "" -or $refreshTimeScaleInSeconds -eq $null) {$refreshTimeScaleInSeconds = 30}
			#}

			if ($_process_type.toLower() -ne "farmer") { continue }

			#$_farmer_metrics_raw = fPingMetricsUrl $_host_url
			$_farmer_metrics_raw = $_process_state_arr[0]
			[void]$_farmers_metrics_raw_arr.add($_farmer_metrics_raw)
			$_farmer_metrics_formatted_arr = fParseMetricsToObj $_farmers_metrics_raw_arr[$_farmers_metrics_raw_arr.Count - 1]
			
			# header lables
			$_b_write_header = $True
			#
			$_label_hostname = "Hostname"
			$_label_diskid = "Disk Id"
			$_label_size = "Size     "
			$_label_percent_complete = "% Complete"
			$_label_eta = "ETA       "
			$_label_sectors_per_hour = "Sectors/Hour"
			$_label_minutes_per_sectors = "Minutes/Sector"
			$_label_rewards = "Rewards"
			$_label_misses = "Misses"
			$_spacer = " "
			$_total_header_length = $_label_size.Length + $_label_percent_complete.Length + $_label_eta.Length + $_label_sectors_per_hour.Length + $_label_minutes_per_sectors.Length + $_label_rewards.Length + $_label_misses.Length
			$_total_header_labels = 8
			
			#
			
			##
			$_disk_metrics_arr = fGetDiskSectorPerformance $_farmer_metrics_formatted_arr
			$_disk_UUId_arr = $_disk_metrics_arr[0].Id
			$_disk_sector_performance_arr = $_disk_metrics_arr[0].Performance
			$_disk_rewards_arr = $_disk_metrics_arr[0].Rewards
			$_disk_misses_arr = $_disk_metrics_arr[0].Misses
			$_disk_plots_completed_arr = $_disk_metrics_arr[0].PlotsCompleted
			$_disk_plots_remaining_arr = $_disk_metrics_arr[0].PlotsRemaining

			# Write uptime information to console
			foreach ($_disk_sector_performance_obj in $_disk_sector_performance_arr)
			{
				
				if ($_disk_sector_performance_obj) {
					if ($_disk_sector_performance_obj.Id -eq "overall") {
						$_avg_sectors_per_hour = 0.0
						$_avg_minutes_per_sector = 0.0
						if ($_disk_sector_performance_obj.TotalSeconds -gt 0) {
						#if ($_disk_sector_performance_obj.TotalSeconds -and $_disk_sector_performance_obj.TotalSeconds -gt 0) {
							$_avg_sectors_per_hour = [math]::Round(($_disk_sector_performance_obj.TotalSectors * 3600)/ $_disk_sector_performance_obj.TotalSeconds, 1)
						}
						if ($_disk_sector_performance_obj.TotalSectors) {
							$_avg_minutes_per_sector = [math]::Round($_disk_sector_performance_obj.TotalSeconds / ($_disk_sector_performance_obj.TotalSectors * 60), 1)
						}
						
						$_uptime = fGetElapsedTime $_disk_sector_performance_obj
						$_uptime_disp = $_uptime.days.ToString()+"d "+$_uptime.hours.ToString()+"h "+$_uptime.minutes.ToString()+"m "+$_uptime.seconds.ToString()+"s"

						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + ", " +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Uptime: " +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_uptime_disp +  "</td>"
						$_html += "</tr>"
						$_html += "<br>"
						$_html += "<tr>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Sectors/Hour (avg): " +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_avg_sectors_per_hour.toString() +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + ", " +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Minutes/Sector (avg): " +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_avg_minutes_per_sector.toString() +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + ", " +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Rewards: " +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_disk_sector_performance_obj.TotalRewards.toString() +  "</td>"
						$_html += "</tr>"
						break
					}
				}
			}

			# $_total_spacer_length = ("--------------------------------------------------------------------------------------------------------").Length
			$_spacer_length = $_total_spacer_length
			$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
			
			$_html += "<br>"

			#foreach ($_disk_sector_performance_obj in $_disk_sector_performance_arr)
			$_html += "<tr><table border=1>"
			foreach ($_disk_UUId_obj in $_disk_UUId_arr)
			{
				# write header if not already done
				if ($_b_write_header -eq $True) {
					# Host name header info
					# draw line
					if ($_disk_UUId_obj -ne $null) {
						$_total_spacer_length = $_disk_UUId_obj.Id.toString().Length + $_total_header_length + $_total_header_labels + 2 	# 1 for leading and 1 for trailing
					}
					else {
						# $_total_spacer_length = ("------------------------------------------------------------------------").Length
						
						}
					$_spacer_length = $_total_spacer_length
					$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
					if ($_b_first_time -eq $True) {
						$_b_first_time = $False
					}
					 
					#
					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"

					$_html += "<tr>"
					#$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_spacer +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_diskid +  "</td>"
					if ($_disk_UUId_obj -ne $null) {
						$_spacer_length =  $_disk_UUId_obj.Id.toString().Length - $_label_diskid.Length + 1
					}
					else {$_spacer_length = ("------------------------------------------------------------------------").Length}
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"

					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_size +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_percent_complete +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_eta +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_sectors_per_hour +  "</td>"

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					#$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_spacer +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_minutes_per_sectors +  "</td>"

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					#$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_spacer +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_rewards +  "</td>"
					
					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					#$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_spacer +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_misses +  "</td>"

					$_spacer_length = 0
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					#$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_label_spacer +  "</td>"
					$_html += "</tr>"
					#
					# draw line
					if ($_disk_UUId_obj -ne $null) {
						$_spacer_length =  $_disk_UUId_obj.Id.toString().Length + $_total_header_length + $_total_header_labels + 2 	# 1 for leading and 1 for trailing
					}
					else {$_spacer_length = ("------------------------------------------------------------------------").Length}
					$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"
					#$_html += "<tr>"
					#$_html += '<hr style="width:50%;text-align:left;margin-left:0">'
					#$_html += "</tr>"
					#
					$_b_write_header = $False
				}
				#$_disk_sector_performance_obj = $_disk_sector_performance_arr[$arrPos]
				#$_disk_rewards_obj = $_disk_rewards_arr[$arrPos]

				# write data table
				$_spacer_length = 0
				$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
				$_label_spacer = $_label_spacer + "|"

				$_html += "<tr>"
				$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_disk_UUId_obj.Id +  "</td>"

				# get performance data - write after eta is calculated
				$_minutes_per_sector_data_disp = "-"
				$_sectors_per_hour_data_disp = "-"
				foreach ($_disk_sector_performance_obj in $_disk_sector_performance_arr)
				{
					if ($_disk_sector_performance_obj) {
						if ($_disk_sector_performance_obj.Id -eq "overall" -or $_disk_UUId_obj.Id -ne $_disk_sector_performance_obj.Id) { continue }
					}
					#
					$_minutes_per_sector_data_disp = $_disk_sector_performance_obj.MinutesPerSector.ToString()
					$_sectors_per_hour_data_disp = $_disk_sector_performance_obj.SectorsPerHour.ToString()
				}

				# write size, % progresion and ETA
				$_b_printed_size_metrics = $False
				$_size_data_disp = "-"
				$_plotting_percent_complete = "-"
				$_plotting_percent_complete_disp = "-"
				$_eta = "-"
				$_eta_disp = "-"
				foreach ($_disk_plots_completed_obj in $_disk_plots_completed_arr)
				{
					if ($_disk_plots_completed_obj) {
						if ($_disk_UUId_obj.Id -ne $_disk_plots_completed_obj.Id) { continue }
					}
					else {break}
					#
					$_size_data_disp = $_disk_plots_completed_obj.Sectors

					foreach ($_disk_plots_remaining_obj in $_disk_plots_remaining_arr)
					{
						if ($_disk_plots_remaining_obj) {
							if ($_disk_UUId_obj.Id -ne $_disk_plots_remaining_obj.Id) { continue }
						}
						else {break}
						
						$_reminaing_sectors = [int]($_disk_plots_remaining_obj.Sectors)
						$_completed_sectors = [int]($_disk_plots_completed_obj.Sectors)
						$_total_sectors_GiB = $_completed_sectors + $_reminaing_sectors
						$_total_disk_sectors_TiB = [math]::Round($_total_sectors_GiB / 1000, 2)
						$_total_disk_sectors_disp = $_total_disk_sectors_TiB.ToString() + " TiB"
						if ($_total_sectors_GiB -ne 0) {
							$_plotting_percent_complete = [math]::Round(($_completed_sectors / $_total_sectors_GiB) * 100, 1)
							$_plotting_percent_complete_disp = $_plotting_percent_complete.ToString() + "%"
						}
						if ($_minutes_per_sector_data_disp -ne "-") {
							$_eta = [math]::Round((([double]($_minutes_per_sector_data_disp) * $_reminaing_sectors)) / (60 * 24), 2)
							$_eta_disp = $_eta.toString() + " days"
						}
						
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_total_disk_sectors_disp +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_plotting_percent_complete_disp +  "</td>"
						$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_eta_disp +  "</td>"
					}

					$_b_printed_size_metrics = $True
				}
				if ($_b_printed_size_metrics -eq $False)
				{
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "-" +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "-" +  "</td>"
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "-" +  "</td>"
				}

				# write performance data

				$_spacer_length = $_label_eta.Length - $_eta_disp.Length
				$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
				$_label_spacer = $_label_spacer + "|"
			
				$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_sectors_per_hour_data_disp +  "</td>"

				$_spacer_length = [int]($_label_sectors_per_hour.Length - $_sectors_per_hour_data_disp.Length)
				$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
				$_label_spacer = $_label_spacer + "|"
				
				$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_minutes_per_sector_data_disp +  "</td>"

				$_b_counted_missed_rewards = $False
				$_b_data_printed = $False
				$_missed_rewards_count = 0
				$_missed_rewards_color = "white"
				$_b_reward_data_printed = $false
				$_rewards_data_disp = "-"
				foreach ($_disk_rewards_obj in $_disk_rewards_arr)
				{
					if ($_disk_UUId_obj.Id -ne $_disk_rewards_obj.Id) {
							continue
					}
					$_rewards_data_disp = $_disk_rewards_obj.Rewards.ToString()

					$_spacer_length = [int]($_label_minutes_per_sectors.Length - $_minutes_per_sector_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
				
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + $_disk_rewards_obj.Rewards +  "</td>"
					
					$_b_reward_data_printed = $true
				}
				if ($_b_reward_data_printed -eq $false) 				# rewards not published yet in endpoint
				{
					$_spacer_length = [int]($_label_minutes_per_sectors.Length - $_minutes_per_sector_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "-" +  "</td>"
				}


				$_b_misses_data_printed = $false
				foreach ($_disk_misses_obj in $_disk_misses_arr)
				{
					if ($_disk_UUId_obj.Id -ne $_disk_misses_obj.Id) {
							continue
					}
					
					if ($_disk_misses_obj.Misses -gt 0) {
						$_missed_rewards_color = $_html_red
					}
					
					$_spacer_length = [int]($_label_rewards.Length - $_rewards_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					$_html += "<td><font size='" + $_font_size + "' color='" + $_missed_rewards_color + "'>" + $_disk_misses_obj.Misses +  "</td>"

					$_spacer_length = [int]($_label_misses.Length - $_disk_misses_obj.Misses.toString().Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					$_html += "</tr>"
					
					$_b_misses_data_printed = $true
				}
				if ($_b_misses_data_printed -eq $false) 				# misses not published yet in endpoint
				{
					# write data - combine missed and rewards into single line of display
					$_b_data_printed = $True

					$_spacer_length = [int]($_label_rewards.Length - $_rewards_data_disp.Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "-" +  "</td>"

					$_spacer_length = [int]($_label_misses.Length - ("-").toString().Length)
					$_label_spacer = fBuildDynamicSpacer $_spacer_length $_spacer
					$_label_spacer = $_label_spacer + "|"
					
					$_html += "</tr>"
				}				
			}
			$_html += "</table>"
			#
		}
	}
	#
	# draw finish line
	if ($_disk_UUId_obj) {
		$_spacer_length =  $_disk_UUId_obj.Id.toString().Length + $_total_header_length + $_total_header_labels + 2 	# 1 for leading and 1 for trailing
	}
	else {$_spacer_length = ("------------------------------------------------------------------------").Length}
	$_label_spacer = fBuildDynamicSpacer $_spacer_length "-"

	# display output github version info
	$_gitVersionDisp = " - "
	$_gitVersionDispColor = $_html_red
	if ($null -ne $gitVersion) {
		$currentVersion = $gitVersion[0] -replace "[^.0-9]"
		$_gitVersionDisp = $gitVersion[0]
		$_gitVersionDispColor = $_html_green
	}

	$_html += "<br>"
	$_html += "<tr>"
	$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Latest github version : " +  "</td>"
	$_html += "<td><font size='" + $_font_size + "' color='" + $_gitVersionDispColor + "'>" + $_gitVersionDisp +  "</td>"
	$_html += "</tr>"
	$_html += "</table>"
	##
	# display last refresh time 
	#Clear-Host
	$_current_date = (Get-Date).ToLocalTime().toString()
	# Refresh
	$_html += "<br>"
	$_html += "<tr>"
	$_html += "<td><font size='" + $_font_size + "' color='" + $_html_black + "'>" + "Page refreshed on: " +  "</td>"
	$_html += "<td><font size='" + $_font_size + "' color='" + $_html_green + "'>" + $_current_date +  "</td>"
	$_html += "</tr>"
	#
	$_html += "</div>"
	$_html += "</body></html>"

	return $_html
}
			
main
