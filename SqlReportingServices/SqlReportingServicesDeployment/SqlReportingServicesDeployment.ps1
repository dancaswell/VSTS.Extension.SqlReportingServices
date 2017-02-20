param(
	[Parameter(Mandatory=$True, Position=1)][string]$ReportFiles,
	[Parameter(Mandatory=$True)][string]$ReportUploadRootPath,
	[string]$IncludeDataSource,
	[string]$DataSourceLocalPath,
	[string]$DataSourceRootPath,
	[string]$ConnectionString,

	[string]$IncludeDataSet,
	[string]$DataSetLocalPath,
	[string]$DataSetRootPath,

	[string]$IncludeResources,
	[string]$ResourceRootLocalPath,
	[string]$ResourcePatterns,
	[string]$ResourceRootPath,

	[Parameter(Mandatory=$True)][string]$WebserviceUrl,
	[string]$WsUsername,
	[string]$WsPassword,
	[string]$UseVerbose,
	[string]$OverrideExisting
)
	function Verbose-WriteLine{
		[cmdletbinding()]
		param(
			[Parameter(Position=1)]$text
		)
		if($UseVerbose -and $UseVerbose -eq $true){
			#$oldForeColor = $Host.UI.RawUI.ForegroundColor;
			#$oldBackColor = $Host.UI.RawUI.BackgroundColor;

			#$Host.Ui.RawUI.ForegroundColor = 'Black';
			#$Host.UI.RawUI.BackgroundColor = 'Yellow';
			Write-Host "[VERBOSE] >> $text" -;
			
			#$Host.Ui.RawUI.ForegroundColor = $oldForeColor;
			#$Host.UI.RawUI.BackgroundColor = $oldBackColor;
		}
	}
##########################################################
#                      SETUP OF CODE                     #
##########################################################
	Write-Host "Preparing Deployment of RDL files...";


	Verbose-WriteLine "Preparing script... (Verbose = $UseVerbose)";
	Verbose-WriteLine "Using following parameters:"
	Verbose-WriteLine "ReportFiles: $ReportFiles";
	Verbose-WriteLine "Upload path: $ReportUploadRootPath";

	Verbose-WriteLine "IncludeDataSource: $IncludeDataSource";
	Verbose-WriteLine "DataSourcePath: $DataSourcePath";
	Verbose-WriteLine "connectionstring: $ConnectionString";

	Verbose-WriteLine "IncludeDataSet: $IncludeDataSet";
	Verbose-WriteLine "DataSourcePath: $DataSourcePath";
	Verbose-WriteLine "connectionstring: $ConnectionString";

	Verbose-WriteLine "IncludeResources: $IncludeResources";
	Verbose-WriteLine "ResourceRootLocalPath: $ResourceRootLocalPath";
	Verbose-WriteLine "ResourcePatterns: $ResourcePatterns";
	Verbose-WriteLine "ResourceRootPath: $ResourceRootPath";
	
	$hasWsPassword = "N/A";
	if([System.String]::IsNullOrWhiteSpace($WsPassword) -eq $true){ #Check if the Webservice HAS a password and mark it with some stars
		$hasWsPassword = "********";
	}
	Verbose-WriteLine "Webservice: $WebserviceUrl";
	Verbose-WriteLine "WsUsername: $WsUsername";
	Verbose-WriteLine "WsPassword: $hasWsPassword";

##########################################################
#                      Testing files                     #
##########################################################

	Write-Host "Uploading files" -NoNewline;
	#Get all Files using the $ReportFiles parameter (expecting it is a Wildcard or direct link to 1 file)
	$pathIsValid = Test-Path $ReportFiles;
	if($pathIsValid -eq $False){
		Write-Error "No file(s) matching the path/wildcard $ReportFiles were found";#NotFound 1
		exit -1;
	}

	if($IncludeDataSource -eq $true){
		$pathRdsIsValid = Test-Path $DataSourceLocalPath;
		if($pathRdsIsValid -eq $false){
			Write-Error "No file(s) matching the path/wildcard $pathRdsIsValid were found";#NotFound 1
			exit -1;
		}
	}

##########################################################
#                Creating Webservice proxy               #
##########################################################

	$ssrs= $null; #Webservice proxy
	[System.Management.Automation.PSCredential]$auth = $null; #Auth incase there is one
	if([System.String]::IsNullOrWhiteSpace($WsUsername) -or [System.String]::IsNullOrWhiteSpace($WsPassword)){  #If not use the DefaultCredential (PS session of the machine where this powershell script is executed
		Write-Host "Creating WebService proxy using default credentials"; 
		$ssrs =New-WebServiceProxy -Uri $WebserviceUrl -UseDefaultCredential -Namespace "SSRS" -ErrorAction Stop;
	}else{#Incase there is a Webservice user-password pair, use the PSCredential of that pair
		Write-Host "Creating WebService proxy using credentials";
		$wsSecurePass = ConvertTo-SecureString -String $WsPassword -AsPlainText -Force

		$auth = New-Object System.Management.Automation.PSCredential -ArgumentList $WsUsername,$wsSecurePass;
		$ssrs = New-WebServiceProxy -Uri $WebserviceUrl -Credential $auth -Namespace "SSRS" -ErrorAction Stop;
	}

##########################################################
#		           Uploading datasources                 #
##########################################################

	$rdsFiles = @(Get-ChildItem $DataSourceLocalPath);
	$rdsFileCount = $rdsFiles.Length;
	if($IncludeDataSource -eq $true){ #Update the datasources
		Write-Host "Updating $rdsFileCount datasource files to $WebserviceUrl ($ReportUploadRootPath)...";
		$rdsFiles | ForEach-Object{
			$datasourceName = $_.FullName;
			Write-Host "Uploading datasource $datasourceName to $DataSourceRootPath...";
			Verbose-WriteLine "Reading $datasourceName file...";
			[xml]$rds = Get-Content -Path $_.FullName; #Read the RDS(XML) files
			$connectionProperties = $rds.RptDataSource.ConnectionProperties;
			$Definition = New-Object SSRS.DataSourceDefinition; 
			if([string]::IsNullOrWhiteSpace($ConnectionString)){ #If there is no connectionstring specified, use the one in RDS
				$Definition.ConnectString = $connectionProperties.ConnectString;
			}else{
				$Definition.ConnectString = $ConnectionString;
			}
			$Definition.Extension = $connectionProperties.Extension; #Add the Extension from the RDS
			if([System.Convert]::ToBoolean($connectionProperties.IntegratedSecurity)){ #Set the Integrated mode
				$Definition.CredentialRetrieval = 'Integrated'
			}
			Write-Host ($Definition | Format-List | Out-String)
			$rdsName = $rds.RptDataSource.Name;
			Verbose-WriteLine "Creating Datasource $rdsName";
			#Documentation of the method below: https://msdn.microsoft.com/en-us/library/reportservice2010.reportingservice2010.createdatasource.aspx
			$createdDatasource = $ssrs.CreateDataSource( #Create/Update the Datasource
				$rdsName, #The name of the RDS
				$DataSourceRootPath, #Remote Root path
				$true, #Override existing
				$Definition,# The definition ("xml")
				$null #Additional properties
			);
		}
		Write-Host "Done updating datasources!";
	}
##########################################################
#		            Uploading datasets                   #
##########################################################

	$rsdFiles = @(Get-ChildItem $DataSetLocalPath);
	$rsdFileCount = $rsdFiles.Length;
	if($IncludeDataSet -eq $true){
		Write-Host "Uploading $rsdFileCount Dataset files";
		$rsdFiles | ForEach-Object {
			$datasetName = $_.FullName; 
			$datasetFileName = [System.IO.Path]::GetFileNameWithoutExtension($datasetName);
			Write-Host "Uploading datasource $datasetName to $DataSetRootPath...";
			Verbose-WriteLine "Reading $datasetName file...";
			[xml]$rsd = Get-Content -Path $datasetName;
			$byteRsd = Get-Content -Encoding Byte -Path $datasetName
			$warnings = $null;
			try{
				$dataset = $ssrs.CreateCatalogItem(
					"DataSet",
					$datasetFileName,
					$DataSetRootPath,
					$true,
					$byteRsd,
					$null,
					[ref]$warnings
				);
				
				#If any warning was logged during upload, log them to the console
				if($warnings -ne $null){
					Write-Warning "One or more warnings occured during upload:";
					$warningSb = New-Object System.Text.StringBuilder;
					$warnings | ForEach-Object{
						$txtWarning = $_.Message;
						$warningSb.AppendLine("`t- {$txtWarning}");
					}
					Write-Warning $warningSb.ToString();
				}
			}catch [System.Exception]{
				Write-Error $_.Exception.Message;
				#Terminate script
				exit -1;
			}
		}
	}

##########################################################
#		        Uploading Resource files                 #
##########################################################

	if($IncludeResources -eq $true){
		Add-Type -AssemblyName "System.Web";
		ForEach($item in @($ResourcePatterns.Split("`n"))){
			Write-Warning $item;
			if([string]::IsNullOrWhiteSpace($item)){
				continue;
			}
			$fullPattern = [System.IO.Path]::Combine($ResourceRootLocalPath,$item);
			$test = Test-Path $fullPattern -ErrorAction SilentlyContinue;
			if($test -eq $true){
				Write-Host "Uploading $fullPattern...";
				$files = @(Get-ChildItem $fullPattern);
				$files | ForEach-Object{
					$bts = Get-Content -Encoding Byte $_.FullName;
					$fileName = [System.IO.Path]::GetFileNameWithoutExtension($_.FullName);
					$warning =$null;
					$props = New-Object "System.Collections.Generic.List[SSRS.Property]";
					$mime = New-Object SSRS.Property;
					$mime.Name = "MimeType";
					$mime.Value = [System.Web.MimeMapping]::GetMimeMapping($_.FullName); #Set THe correct mimetype
					$props.Add($mime);
					$resource = $ssrs.CreateCatalogItem(
						"Resource",
						$fileName,
						$ResourceRootPath,
						$true,
						$bts,
						$props.ToArray(),
						[ref]$warning
					);
					if($warnings -ne $null){
						Write-Warning "One or more warnings occured during upload:";
						$warningSb = New-Object System.Text.StringBuilder;
						$warnings | ForEach-Object{
							$txtWarning = $_.Message;
							$warningSb.AppendLine("`t- {$txtWarning}");
						}
						Write-Warning $warningSb.ToString();
					}
				}
			}else{
				Write-Host "Skipping $fullPattern!";
			}
		}
	}

##########################################################
#		             Uploading reports                   #
##########################################################

	$files = @(Get-ChildItem $ReportFiles);
	$fileCount = $files.Length;
	Verbose-WriteLine "Found $fileCount items in $ReportFiles";

	Write-Host "Uploading $fileCount files to $WebserviceUrl ($ReportUploadRootPath)...";
	#Itterate over all files and append them to a catalogitem
	$files | ForEach-Object{ 
		$reportName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name); #Get the name of the reportname
		$bytes = [System.IO.File]::ReadAllBytes($_.FullName); #Get The path to upload
		$byteLenght = $bytes.Lenght; #for verbose logging 
		Write-Host "Uploading report $reportName to $ReportUploadRootPath...";
		Verbose-WriteLine "Uploading $reportName with filesize $byteLength bytes"; 
		$warnings =$null; #Warnings associated to the upload
		try{
		$report = $ssrs.CreateCatalogItem(
			"Report", #The Catalog Item
			$reportName, #The report name
			$ReportUploadRootPath,#Upload root path
			$OverrideExisting, #Overriding files which exists
			$bytes, #The bytes to upload
			$null, #Additional properties to set
			[ref]$warnings #Warnings associated to the upload
		);

		
		#If any warning was logged during upload, log them to the console
		if($warnings -ne $null){
			Write-Warning "One or more warnings occured during upload:";
			$warningSb = New-Object System.Text.StringBuilder;
			$warnings | ForEach-Object{
				$txtWarning = $_.Message;
				$warningSb.AppendLine("`t- {$txtWarning}");
			}
			Write-Warning $warningSb.ToString();
		}
		}catch [System.Exception]{
			Write-Error $_.Exception.Message;
			#Terminate script
			exit -1;
		}

	}
##########################################################
#		               Finishing task                    #
##########################################################
	Write-Host "Done uploading $fileCount files!";
	Write-Host "Deployment of RDL files completed";
##########################################################
#		                Task finished                    #
##########################################################



