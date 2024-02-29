function Pause([String]$message) {
    Write-Host $message
    if ($isIse) {
        Read-Host
    }
    else {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }    
}

function CreateFolder([String]$Folder) {
    # Check if the destination directory exists, if it's a valid path and create it if necessary. 
    # If already exists or successfully created, simply returns $true
    if (-not (Test-Path -Path $Folder)) {
        try {
            mkdir $Folder -ErrorVariable MDError -ErrorAction SilentlyContinue | Out-Null #we keep the error in MDError variable ($null if no error)
        }
        finally {
            if ($MDError -ne $null) {
                Write-Host -ForegroundColor Red -BackgroundColor White "Error: The provided destination directory could not be created"               
                Write-Host $MDError -ForegroundColor Red -BackgroundColor White 
                Remove-Variable MDError #cleanup
            }
        }
    }
    return (Test-Path -Path $Folder)
}

function getLogTime {
    return Get-Date -Format $logTimeFormat 
}

function LogInfo([string]$Message, [string]$logFile) {
    Write-Host $Message
    $Message = ((getLogTime) + " - [Info] - " + $Message)
    $Message | Out-File -FilePath $logFile -Append
}

function LogSuccess([string]$Message) {
    Write-Host $Message
    $Message = ((getLogTime) + " - [Success] - " + $Message)
    $Message | Out-File -FilePath $logFile -Append
}

function LogError([string]$Message) {
    Write-Host $Message
    $Message = ((getLogTime) + " - [Error] - " + $Message)
    $Message | Out-File -FilePath $logFile -Append
}