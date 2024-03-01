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

    .EXAMPLE
    PS> .\FolderSync.ps1 -Source "F:\Storage Reports\" -Destination "D:\Storage Reports" -LogPath "C:\Temp\Logs\" -LogToConsole:$true

#>

param
(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [Parameter(Mandatory = $false)][Boolean]$LogToConsole = $false
)   

Clear-Host
$scriptPath = Split-Path $PSCommandPath -Parent
$global:logTimeFormat = "dd-MM-yyyy HH:mm:ss"
$global:isIse = Test-Path variable:global:psISE #checks if the script is opened in ISE ($true) or running in console ($false)

# Load external functions
. (Join-Path -Path $scriptPath -ChildPath 'FolderSync-Functions.ps1')
    
$exitErrortMsg = "" #to be used if the script doesn't meet requirements

$isSrcDirOK = Test-Path -Path $Source # Check if the source directory exists
if ($isSrcDirOK -eq $false) { $exitErrortMsg += "Source path" }

# Check if the destination and log directory exists
$isDstDirOK = CreateFolder -Folder $Destination
  
if ($isDstDirOK) {
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
LogInfo -Message "FolderSync operation started"
LogInfo -Message ("Source " + $Source)
LogInfo -Message ("Destination " + $Source)
LogInfo -Message ("LogFile " + $logFile)
LogInfo -Message ("Output to console? " + $LogToConsole)

#region Main
    # Initialize counters 
    $CopiedDirs = 0
    $CopiedFiles = 0 
    $DeletedDirs = 0
    $DeletedFiles = 0
    $FailedDelDirs = 0
    $FailedDelFiles = 0
    $FailedCopyDirs = 0
    $FailedCopyFiles = 0
    $BytesCopied = 0
    
    $srcItems = Get-ChildItem -Path $Source -Recurse -Force # Get full source tree
    $dstItems = Get-ChildItem -Path $Destination -Recurse -Force # Get full destination tree

    <#  Create the list of operations
        Information to retain: 
            - Directories: FullName
            - Files: Name, LastWriteTime, Length

        Operations to perform:
            - Delete files and folders at the destination
            - Copy files if they don't exist at the destination, or if they are modified (LastWriteTime and/or Length differ)
    #>

    # Separate folders from files at the source
    $srcDirs = $srcItems.Where({ $_.PSIsContainer -eq $true }) | Select-Object FullName
    $srcFiles = $srcItems.Where({ $_.PSIsContainer -eq $false }) | Select-Object FullName, LastWriteTime, Length

    # Separate folders from files at the destination
    
    $dstDirs = $dstItems.Where({ $_.PSIsContainer -eq $true }) | Select-Object FullName
    $dstFiles = $dstItems.Where({ $_.PSIsContainer -eq $false }) | Select-Object FullName, LastWriteTime, Length | Sort-Object FullName


    # In order to properly compare surce <> destination, we need to match the directory structure by replacing source dir with dest dir
    
    $srcDirWithDestPath = $srcDirs | Select-Object @{N = 'FullName'; E = { ($_.FullName).Replace($Source, $Destination) } }
    $srcFileWithDstPath = $srcFiles | Select-Object @{N = 'FullName'; E = { ($_.FullName).Replace($Source, $Destination) } }, LastWriteTime, Length

    # Delete all files at destination that no loger exist at the source
    if ($dstFiles.Count -ne 0) {
        $filesToDelete = Compare-Object -ReferenceObject $srcFileWithDstPath -DifferenceObject $dstFiles -Property FullName -ErrorAction SilentlyContinue `
                        | Where-Object { $_.SideIndicator -eq '=>' } `
                        | Select-Object FullName 
    }

    foreach ($item in $filesToDelete)
    {
        $name = $item.FullName
        Remove-Item -Path $name -Force -ErrorAction SilentlyContinue -ErrorVariable errLog -Verbose:$LogToConsole
        if ($errLog.Count -eq 0) {
            $DeletedFiles += 1
            LogSuccess -Message ("File deleted: " + $name)
        }
        else {
            $FailedDelFiles += 1
            LogError -Message ("Failed to delete file: " + $name + " | Reason: " + $errLog.Exception) 
        }
    }

    # Delete all directories at destination that no loger exist at the source
    if ($dstDirs.Count -ne 0) {
        $dirsToDelete = Compare-Object -ReferenceObject $srcDirWithDestPath -DifferenceObject $dstDirs -Property FullName `
                        | Where-Object { $_.SideIndicator -eq '=>' } `
                        | Select-Object FullName
    }

    foreach ($item in $dirsToDelete)
    {
        $name = $item.FullName
        Remove-Item -Path $name -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable errLog -Verbose:$LogToConsole
        if ($errLog.Count -eq 0) {
            $DeletedDirs += 1
            LogSuccess -Message ("Folder deleted: " + $name)
        }
        else {
            $FailedDelDirs += 1
            LogError -Message ("Failed to delete folder: " + $name + " | Reason: " + $errLog.Exception) 
        }
    }


    # Dorectories to copy or overwrite (here we also compare by Size and modified date)
    if ($dstDirs.Count -ne 0) {
        $dirsToCopy = Compare-Object -ReferenceObject $srcDirWithDestPath -DifferenceObject $dstDirs -Property FullName, LastWriteTime, Length `
                            | Where-Object { $_.SideIndicator -eq '<=' } `
                            | Select-Object @{N = 'FullName'; E = { ($_.FullName).Replace($Destination, $Source) }}
    }
    else {
        # No directories found at destination so we create them all
        $dirsToCopy = $srcDirs
    }
    foreach ($item in $dirsToCopy)
    {
        $name = $item.FullName.Replace($Source, $Destination)
        if (CreateFolder -Folder $name) {
            $CopiedDirs += 1
            LogSuccess -Message ("New directory: " + $name)
        }
        else {
            $FailedCopyDirs
            LogError -Message ("Failed to create new directory: " + $name)
        }
    }

    # Files to copy or overwrite (here we also compare by Size and modified date)

    if ($dstFiles.Count -ne 0) {
        $filesToCopy = Compare-Object -ReferenceObject $srcFileWithDstPath -DifferenceObject $dstFiles -Property FullName, LastWriteTime, Length `
                            | Where-Object { $_.SideIndicator -eq '<=' } `
                            | Select-Object @{N = 'FullName'; E = { ($_.FullName).Replace($Destination, $Source) }}
    }
    else {
        # No files found at destination so we create them all
        $filesToCopy = $srcFiles
    }
    foreach ($item in $filesToCopy)
    {
        $srcFileName = $item.FullName
        $dstfileName = $srcFileName.Replace($Source, $Destination)
        $result = Copy-Item -Path $srcFileName -Destination $dstfileName -PassThru -ErrorAction SilentlyContinue -ErrorVariable errLog -Verbose:$LogToConsole 
        if ($errLog.Count -eq 0) {
            $CopiedFiles += 1
            $fileSize = 0
            $fileSize = (Get-ChildItem -Path $srcFileName).Length
            $BytesCopied += $fileSize
            LogSuccess -Message ("New file: " + $dstfileName + " (Size " + $fileSize + ")")
        }
        else {
            $FailedCopyFiles += 1
            LogSuccess -Message ("Failed to copy file: " + $dstfileName + " | Reason: " + $errLog.Exception)
        }
    }
LogInfo -Message "FolderSync operation finished."

LogInfo -Message ("Directories created: " + $CopiedDirs)
LogInfo -Message ("Files copied: " + $CopiedFiles + " (bytes transferred: " + $BytesCopied + ")")
LogInfo -Message ("Directories deleted: " + $DeletedDirs)
LogInfo -Message ("Files deleted: " + $DeletedFiles)
LogInfo -Message ("Directories failed to be deleted: " + $FailedDelDirs)
LogInfo -Message ("Files failed to be deleted: " + $FailedDelFiles)
LogInfo -Message ("Directories failed to be created: " + $FailedCopyDirs)
LogInfo -Message ("Files failed to be created/copied: " + $FailedCopyFiles)

#endregion Main
