#Requires -RunAsAdministrator
Import-Module powershell-yaml

$config = $args[0]
$bakPath = $args[1]

function GetBakFileNames($bakPath) {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server
    $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
    $restore.Devices.AddDevice($bakPath, ([Microsoft.SqlServer.Management.Smo.DeviceType]::File))
    $fileList = $restore.ReadFileList($server) 

    $defaultDataPath = $server.DefaultFile
    $defaultLogPath = $server.DefaultLog
    $dataLogicalName = $fileList.Rows[0][0].ToString()
    $logLogicalName = $fileList.Rows[1][0].ToString()

    return @($defaultDataPath, $dataLogicalName, $defaultLogPath, $logLogicalName)
}

function RestoreDatabase($dbServer, $sqlCred, $dbName, $bakPath) {
    $dataFileName = "$dbName.mdf"
    $logFileName = "${dbName}_log.ldf"

    $fileNames = GetBakFileNames $bakPath
    $dataFileFolder = $fileNames[0]
    $logFileFolder = $fileNames[2]
    $newDataPath = [System.IO.Path]::Combine($dataFileFolder, $dataFileName)
    $newLogPath = [System.IO.Path]::Combine($logFileFolder, $logFileName)
    $RelocateData = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($fileNames[1], $newDataPath)
    $RelocateLog = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($fileNames[3], $newLogPath)

    Restore-SqlDatabase -ServerInstance $dbServer -SqlCredential $sqlCred -Database $parsedConfig.database.name -BackupFile $bakPath -RelocateFile @($RelocateData,$RelocateLog)
}

$configContent = [System.IO.File]::ReadAllText($config)
$parsedConfig = ConvertFrom-Yaml -Yaml $configContent

$ssCred = Get-Credential -UserName "$env:COMPUTERNAME\USR1CV8" -Message "Enter service credentials"

if ($null -ne $bakPath) {
    $sp = ConvertTo-SecureString $parsedConfig.database.password -AsPlainText -Force
    $sp.MakeReadOnly()
    $sqlCred = New-Object System.Data.SqlClient.SqlCredential($dbUser, $sp )

    RestoreDatabase $parsedConfig.database.server $sqlCred $parsedConfig.database.name $bakPath
}

$platforms = Get-ChildItem -Path "$env:ProgramFiles\1cv8" -Directory | 
    Where-Object { $_.Name -Match "\d+\.\d+\.\d+" } | 
    Sort-Object { $_.Name } -Descending

if ($platforms.Length -eq 0) {
    "Failed to get platfrom version"
} 
else {
    $instanceName = $parsedConfig.infobase.name

    $serviceName = "Standalone server ($instanceName)"

    # stop and delete previous service
    Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
    Get-Service -Name $serviceName -ErrorAction SilentlyContinue | ForEach-Object { sc.exe delete $_.Name }

    $platformPath = $platforms[0].FullName
    $binPath = """$platformPath\bin\ibsrv.exe"" --service --data=""C:\standalone-server\$instanceName"" --config=""$config"""
    $description = "Standalone server 1C:Enterprise 8.3"

    New-Service -Name $serviceName -BinaryPathName $binPath -StartupType Automatic -Description $description -Credential $ssCred
}