param
(
    [Parameter(Mandatory = $false)][String]$Source="N:\Downloads",
    [Parameter(Mandatory = $false)][String]$Destination="C:\Temp\Test",
    [Parameter(Mandatory = $false)][String]$LogPath="C:\Temp\Logs",
    [Parameter(Mandatory = $false)][Boolean]$SyncPermissions = $false, 
    [Parameter(Mandatory = $false)][Boolean]$LogToConsole = $false
)   

<#
    .SYNOPSIS
    Synchronizes a folder from one location to another.

    .DESCRIPTION
    The script can synchronize a folder, including the file permissions if needed.
    The results can be saved in a log file

    .PARAMETER source
    Mandatory - Specifies the source folder.

    .PARAMETER destination
    Mandatory - Specifies the replica folder.

    .INPUTS
    No input file or pipe required / supported at the moment

    .OUTPUTS
    System.String. The script returns the name of the log file - if specified

    .EXAMPLE
    PS> xxxxxxxxxxxxxxxxxxxxxxxxx

    .EXAMPLE
    PS> xxxxxxxxxxxxxxxxxxxxxxxxx

    .EXAMPLE
    PS> xxxxxxxxxxxxxxxxxxxxxxxxx
#>

<#
        Script requirements:
        
        Synchronization must be one-way: 
        After the synchronization content of the replica folder should be modified to exactly match content of the source folder;
        File creation/copying/removal operations should be logged to a file and to the console output;
        Folder paths and log file path should be provided using the command line arguments;
        Do not use robocopy and similar utilities
        
        ***************************************************************************************************
        To check:

        - Is the source directory valid?
        - Does the destination folder exist? Create it if not
        what to do if SyncPermissions = true
#>

Clear-Host
$scriptPath = Split-Path $PSCommandPath -Parent
$global:logTimeFormat = "dd-MM-yyyy HH:mm:ss"
$global:isIse = Test-Path variable:global:psISE #checks if the script is opened in ISE ($true) or running in console ($false)

# Load external functions
& (Join-Path -Path $scriptPath -ChildPath "FolderSync-Functions.ps1")
    
#region Params check and replica preparations
$exitErrortMsg = "" #to be used if the script doesn't meet requirements
    
$isSrcDirOK = Test-Path -Path $Source # Check if the source directory exists
if ($isSrcDirOK -eq $false) { $exitErrortMsg += "Source path" }

# Check if the destination and log directory exists
$isDstDirOK = CreateFolder -Folder $Destination
  
if ($isDstDirOK) {
    if ([string]$LogPath -eq "") { #if LogPath was not specified, assumes $Destination\Logs
        $LogPath = Join-Path -Path $Destination -ChildPath "Logs"
    }
    $isLogDirOK = CreateFolder -Folder $LogPath
}
else {
    $isLogDirOK = $false
    $exitErrortMsg += "Destination path"
}

# if $Source, $Destination and $LogPath are all verified, continue, otherwise stop the script
$canContinue = $isSrcDirOK -and $isDstDirOK -and $isLogDirOK
if (-not $canContinue) {
    Pause -message ("The script stopped due to: " + $exitErrortMsg + ". Press any key to exit")
}

$global:logFile = Join-Path -Path $LogPath -ChildPath ("FolderSync_" + (Get-Date -Format "yyyyMMddHHmmss") + ".log")

#endregion Params check and replica preparations

#region Main
$SourceItems = Get-ChildItem -Path $Source -Recurse # Get source info
$DestinationItems = Get-ChildItem -Path $Destination -Recurse # Get destination info

<#  Create the list of operations
    Information to retain from Source: 
    Directories: FullName
    Files Name, CreationTime, LastWriteTime, Length
    Array structure: Item Name #>

$sourceDirectories = $SourceItems.Where({ $_.PSIsContainer -eq $true }) | Select-Object FullName
$sourceFiles = $SourceItems.Where({ $_.PSIsContainer -eq $false }) | Select-Object FullName, LastWriteTime, Length

$destinationDirectories = $destinationItems.Where({ $_.PSIsContainer -eq $true }) | Select-Object FullName
$destinationFiles = $destinationItems.Where({ $_.PSIsContainer -eq $false }) | Select-Object FullName, LastWriteTime, Length | Sort-Object FullName

# Let's delete all files in destination that no loger exist at the source
# In order to properly compare surce <> destination, we need to match the directory structure by replacing source dir with dest dir
$scFileTemp = $sourcefiles | Select-Object @{N = 'FullName'; E = { ($_.FullName).Replace($Source, $Destination) } }, LastWriteTime, Length | Sort-Object Fullname

$srcDirTemp = $sourceDirectories | Select-Object @{N = 'FullName'; E = { ($_.FullName).Replace($Source, $Destination) } } | Sort-Object Fullname

$filesToDelete = $destinationFiles.Where({ $sourceFilesTemp -NotContains $_ })
$filesToDelete = $sourceFilesTemp.Where({ $destinationFiles -NotContains $_ })

$ItemsToCopy = $SourceItems.Where({ $DestinationItems -NotContains $_ })
$ItemsToDelete = $DestinationItems.Where({ $SourceItems -NotContains $_ })
foreach ($item in $ItemsToCopy) {
    if ($item.PSIsContainer) {
        $folderName = $item.FullName.Replace($Source, $Destination)
        if (CreateFolder -Folder $folderName) {
            LogSuccess -Message ("New directory: " + $folderName)
        }
        else {
            LogError -Message ("Failed to create new directory: " + $folderName)
        }
    }
    else {
        $srcFileName = $item.FullName
        $dstfileName = $srcFileName.Replace($Source, $Destination)
        $copyResult = Copy-Item -Path $srcFileName -Destination $dstfileName -PassThru -ErrorAction SilentlyContinue -Verbose:$LogToConsole
        if ($null -ne $copyResult) {
            LogSuccess -Message ("New file: " + $dstfileName)
        }
        else {
            LogSuccess -Message ("Failed to copy file: " + $dstfileName)
        }
    }
}
#endregion Main
