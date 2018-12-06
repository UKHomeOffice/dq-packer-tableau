Import-Module AWSPowerShell

# Preferences
$ErrorActionPreference = "Stop"
$DebugPreference       = "Continue"
$VerbosePreference     = "Continue"
$IsServerCommand       = $false

# Set some basic variables
$date                  = Get-Date

# Tableau specific variables
$appVersion            = "10.2"
$backups_folder        = "C:\backups\Tableau"
$bin_location          = "D:\Program Files\Tableau\Tableau Server\" + $appVersion + "\bin"
$tabadmin              = $bin_location + "\tabadmin.exe"

# AWS S3 Bucket variables
$Region                = "eu-west-2"
$BucketName            = $env:bucket_name
$BucketSubFolder       = $env:bucket_sub_path

# Backup retention
$DaysToKeep      = "7"

# Gets the current date, then shortens to "dd/mm/yyyy hh:mm:ss pm/am"
function Get-LogDate {
	return (Get-Date).ToUniversalTime().ToString()
}

# Enables logging
function Write-Log {
	param(
		[Parameter(Mandatory=$true)]
		[string] $Info ,
		[Parameter(Mandatory=$true)]
		[string] $LogLevel
	)

	$now = Get-LogDate
	$msg = "{0} : {1}" -f $now, $Info

	if ($IsServerCommand -eq $true) {
		if ($LastExitCode -eq 0) {
			$status="Successful"
		}
			else {
				$status="Failed"
			}
		$msg = "{0} : {1}({2}) : {3}" -f $now, $status.ToUpper(), $LastExitCode, $Info
	}
	switch ($LogLevel) {
		debug { $out = Write-Debug "$($msg)" 5>&1 ;break}
		verbose { &out = Write-Verbose "$($msg)" 4>&1 ;break}
		default { $out = $msg ;break}
	}
	if ($LogLevel -eq "verbose" -or $LogLevel -eq "debug") {
		$out = ($LogLevel).ToUpper() +": "+$out
	}
  Write-Host "$($out)"
	if ($status -eq "Failed") {
		Write-Host "ERROR: Something went wrong. Please check logs"
		Exit 1
	}
}

# Test connectivity to S3
function Try-S3Bucket {
	Write-Log "Checking connection to S3" -LogLevel Info
    if ((Test-S3Bucket -BucketName $BucketName -Region $Region) -eq $false ){
        Write-Error "Missing $BucketName or you do not have access."
		break;
	  }
    else {
        Write-Log "Bucket exists - Continue!" -LogLevel Info
    }
}

# Function to backup Tableau using tabadmin
function Tableau-Backup {
	Write-Log "Starting Tableau backup..." -LogLevel Info
	try {
		$output = &"$tabadmin" backup -d -v $backups_folder
		Invoke-Expression $output
	}
	catch {
		$last_error = $Error[0]
		Write-Error "Tableau backups failed.`n$last_error`n"
		Exit 1
	}
}

# Function to copy files in backup directory to S3
function Copy-S3 {
	Write-Log "Start Copy to S3..." -LogLevel Info
	$output = Get-ChildItem $backups_folder -Recurse
	foreach ($path in $output) {
		try {
		  Write-Host $Path
		  $filename = [System.IO.Path]::GetFileName($path)
		  Write-S3Object -BucketName $BucketName -File $path -Key $BucketSubFolder/$filename -Region $Region
	  }
	  catch {
		  $last_error = $Error[0]
		  Write-Error "Copying to S3 failed.`n$last_error`n"
		  Exit 1
	  }
  }
}

# Function to remove local backups, depending on the backup retention (DaysToKeep)
function Remove-Local-Backups {
	Write-Log "Zipping up Tableau Logs" -LogLevel Info
  try {
	  $oldfiles = Get-ChildItem $backups_folder -file | Where-object {$_.LastWriteTime -lt $date.AddDays(-$DaysToKeep)}
    if($oldfiles.count -gt 0)
      {
  	  $oldfiles.Delete()
      }
  }
	catch {
		$last_error = $Error[0]
		Write-Error "Removing local backups failed.`n$last_error`n"
		Exit 1
	}
}

function Main {
	Try-S3Bucket
	Tableau-Backup
	Copy-S3
	Remove-Local-Backups
}

main
