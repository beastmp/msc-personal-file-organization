param(
    [string]$SourceDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Miscellaneous\Misc",
    [string]$TargetDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Miscellaneous\Organized"
)

# Initialize counters
$script:fileCount = @{
    Development = 0
    Media = 0
    Documents = 0
    Total = 0
}

function Move-FilesBack {
    param(
        [string]$path,
        [switch]$IsDevelopment
    )
    
    try {
        if ($IsDevelopment) {
            # For development projects, maintain folder structure
            $projects = Get-ChildItem -Path $path -Directory
            foreach ($project in $projects) {
                $relativePath = $project.FullName.Replace($path, '').TrimStart('\')
                $destination = Join-Path $SourceDirectory $relativePath
                
                if (!(Test-Path $destination)) {
                    New-Item -ItemType Directory -Path $destination -Force | Out-Null
                }
                
                Get-ChildItem -Path $project.FullName -Recurse -File | ForEach-Object {
                    $relativeFilePath = $_.FullName.Replace($project.FullName, '').TrimStart('\')
                    $fileDestination = Join-Path $destination $relativeFilePath
                    $fileDirectory = Split-Path $fileDestination -Parent
                    
                    if (!(Test-Path $fileDirectory)) {
                        New-Item -ItemType Directory -Path $fileDirectory -Force | Out-Null
                    }
                    
                    Move-Item -Path $_.FullName -Destination $fileDestination -Force
                    $script:fileCount.Total++
                    $script:fileCount.Development++
                    Write-Host "Moved back development file: $relativeFilePath" -ForegroundColor Green
                }
            }
        }
        else {
            # For other files, use existing simple move logic
            $files = Get-ChildItem -Path $path -File -Recurse
            
            foreach ($file in $files) {
                $destination = Join-Path $SourceDirectory $file.Name
                
                # If file with same name exists, append a number
                $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $extension = $file.Extension
                $counter = 1
                
                while (Test-Path $destination) {
                    $newFileName = "${baseFileName}_${counter}${extension}"
                    $destination = Join-Path $SourceDirectory $newFileName
                    $counter++
                }
                
                Move-Item -Path $file.FullName -Destination $destination -Force
                $script:fileCount.Total++
                
                # Update category counter
                if ($file.FullName -like "*\Development\*") {
                    $script:fileCount.Development++
                }
                elseif ($file.FullName -like "*\Media\*") {
                    $script:fileCount.Media++
                }
                elseif ($file.FullName -like "*\Documents\*") {
                    $script:fileCount.Documents++
                }
                
                Write-Host "Moved back: $($file.Name)" -ForegroundColor Cyan
            }
        }
    }
    catch {
        Write-Warning "Error moving files: $_"
    }
}

# Main processing logic
Write-Host "`nStarting file reversion...`n" -ForegroundColor Blue

# Process Development folder with structure preservation
$developmentPath = Join-Path $TargetDirectory "Development"
if (Test-Path $developmentPath) {
    Write-Host "Processing Development folder..." -ForegroundColor Green
    Move-FilesBack $developmentPath -IsDevelopment
}

# Process other folders normally
$mediaPath = Join-Path $TargetDirectory "Media"
if (Test-Path $mediaPath) {
    Write-Host "Processing Media folder..." -ForegroundColor Green
    Move-FilesBack $mediaPath
}

# Process Documents folder
$documentsPath = Join-Path $TargetDirectory "Documents"
if (Test-Path $documentsPath) {
    Write-Host "Processing Documents folder..." -ForegroundColor Green
    Move-FilesBack $documentsPath
}

# Clean up empty directories
Write-Host "`nCleaning up empty directories..." -ForegroundColor Blue
Get-ChildItem -Path $TargetDirectory -Recurse -Directory | 
    Sort-Object -Property FullName -Descending |
    ForEach-Object {
        if (!(Get-ChildItem -Path $_.FullName)) {
            Remove-Item -Path $_.FullName -Force
        }
    }

# Display summary
Write-Host "`nReversion Summary:" -ForegroundColor Blue
Write-Host "=================" -ForegroundColor Blue
Write-Host "Development Files: $($script:fileCount.Development)" -ForegroundColor Green
Write-Host "Media Files: $($script:fileCount.Media)" -ForegroundColor Cyan
Write-Host "Document Files: $($script:fileCount.Documents)" -ForegroundColor Yellow
Write-Host "Total Files Moved: $($script:fileCount.Total)" -ForegroundColor White

Write-Host "`nFile reversion complete!" -ForegroundColor Blue
