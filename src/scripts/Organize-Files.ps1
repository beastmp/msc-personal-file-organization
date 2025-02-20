param(
    [string]$SourceDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Organized",
    [string]$TargetDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Organized"
)

# Initialize counters
$script:fileCount = @{
    Development = 0
    Images = 0
    Videos = 0
    Unknown = 0
    Documents = @{
        ByFamily = @{}
    }
}

# Load configuration
$configPath = Join-Path $PSScriptRoot "..\config\file-organization-config.json"
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

# Convert configuration to PowerShell objects
$developmentExtensions = $config.extensions.development
$imageExtensions = $config.extensions.images
$videoExtensions = $config.extensions.videos
$documentExtensions = $config.extensions.documents

# Convert categories to hashtable
$categoryKeywords = @{}
$config.categories.PSObject.Properties | ForEach-Object {
    $categoryKeywords[$_.Name] = @{
        Include = $_.Value.include
        Exclude = $_.Value.exclude
    }
}

# Convert family members to hashtable
$familyKeywords = @{}
$config.familyMembers.PSObject.Properties | ForEach-Object {
    $familyKeywords[$_.Name] = @{
        Include = $_.Value.include
        Exclude = $_.Value.exclude
    }
}

function Convert-WildcardToRegex {
    param([string]$pattern)
    
    # Convert * to regex pattern that matches any characters except newlines
    # This will match spaces, underscores, hyphens, etc.
    return [regex]::Escape($pattern).Replace("\*", "[\s\w-]+")
}

function Test-ContentMatch {
    param(
        [string]$content,
        [string[]]$includePatterns,
        [string[]]$excludePatterns
    )
    
    # Check exclusions first
    foreach ($pattern in $excludePatterns) {
        $regexPattern = Convert-WildcardToRegex $pattern
        if ($content -match $regexPattern) {
            return $false
        }
    }
    
    # Then check inclusions
    foreach ($pattern in $includePatterns) {
        $regexPattern = Convert-WildcardToRegex $pattern
        if ($content -match $regexPattern) {
            return $true
        }
    }
    
    return $false
}

function Test-IsDevelopmentProject {
    param([string]$path)
    $files = Get-ChildItem -Path $path -File -Recurse
    return ($files | Where-Object { $developmentExtensions -contains $_.Extension }).Count -gt 0
}

function Move-Item-Safe {
    param(
        [string]$Path,
        [string]$Destination
    )
    
    $fileName = Split-Path $Destination -Leaf
    $targetDir = Split-Path $Destination -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $extension = [System.IO.Path]::GetExtension($fileName)
    $counter = 1
    
    if (Test-Path $Destination) {
        # Compare file hashes to see if they're the same file
        $sourceHash = (Get-FileHash -Path $Path).Hash
        $destHash = (Get-FileHash -Path $Destination).Hash
        
        if ($sourceHash -eq $destHash) {
            Write-Verbose "Skipping identical file: $fileName"
            return $Destination
        }
        
        # Files are different, find a new name
        while (Test-Path $Destination) {
            $Destination = Join-Path $targetDir "${baseName}_${counter}${extension}"
            $counter++
        }
    }
    
    Move-Item -Path $Path -Destination $Destination -Force
    return $Destination
}

function Move-DevelopmentProject {
    param([string]$path)
    try {
        # For reprocessing, we need to maintain the full path structure
        $projectPath = $path
        if ($path.StartsWith($SourceDirectory)) {
            $projectPath = $path.Substring($SourceDirectory.Length).TrimStart('\')
        }
        
        $targetPath = Join-Path $TargetDirectory "Development\$projectPath"
        
        if (!(Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            Get-ChildItem -Path $path -Recurse | ForEach-Object {
                if (!$_.PSIsContainer) {
                    $relativePath = $_.FullName.Substring($path.Length + 1)
                    $destPath = Join-Path $targetPath $relativePath
                    $destDir = Split-Path $destPath -Parent
                    
                    if (!(Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    
                    Move-Item-Safe -Path $_.FullName -Destination $destPath
                }
            }
            Remove-Item -Path $path -Force
        }
        $script:fileCount.Development++
        Write-Host "Moved development project: ${projectPath}" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to move development project: ${projectPath}`nError: $_"
    }
}

function Move-MediaFile {
    param(
        [string]$path,
        [string]$mediaType
    )
    try {
        $fileName = Split-Path $path -Leaf
        $targetPath = Join-Path $TargetDirectory "Media\$mediaType"
        
        if (!(Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }
        $destination = Move-Item-Safe -Path $path -Destination (Join-Path $targetPath $fileName)
        if ($mediaType -eq "Images") { $script:fileCount.Images++ }
        else { $script:fileCount.Videos++ }
        Write-Host "Moved ${mediaType} file: ${fileName}" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to move ${mediaType} file: ${fileName}`nError: $_"
    }
}

function Move-UnknownFile {
    param([string]$path)
    try {
        $fileName = Split-Path $path -Leaf
        $targetPath = Join-Path $TargetDirectory "Unknown"
        
        if (!(Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }
        $destination = Move-Item-Safe -Path $path -Destination (Join-Path $targetPath $fileName)
        $script:fileCount.Unknown++
        Write-Host "Moved unknown file: ${fileName}" -ForegroundColor Red
    }
    catch {
        Write-Warning "Failed to move unknown file: ${fileName}`nError: $_"
    }
}

function Get-FamilyMember {
    param(
        [string]$fileName,
        [string]$content = ""
    )
    
    # Check filename first
    foreach ($member in $familyKeywords.Keys) {
        if (Test-ContentMatch -content $fileName -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {
            return $member
        }
    }
    
    # If no match in filename, check content if provided
    if ($content) {
        foreach ($member in $familyKeywords.Keys) {
            if (Test-ContentMatch -content $content -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {
                return $member
            }
        }
    }
    
    return "01 - Family"
}

function Get-DocumentCategory {
    param(
        [string]$fileName,
        [string]$content = ""
    )
    
    # Check filename first
    foreach ($category in $categoryKeywords.Keys) {
        if (Test-ContentMatch -content $fileName -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
            return $category
        }
    }
    
    # If no match in filename, check content if provided
    if ($content) {
        foreach ($category in $categoryKeywords.Keys) {
            if (Test-ContentMatch -content $content -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
                return $category
            }
        }
    }
    
    return "General"
}

function Move-Document {
    param(
        [string]$path,
        [string]$category
    )
    try {
        $fileName = Split-Path $path -Leaf
        
        # Try to get category and family member from filename first
        $familyMember = Get-FamilyMember $fileName
        if ($familyMember -eq "01 - Family") {
            # If no family member found in filename, check content
            $content = Get-Content -Path $path -Raw
            $familyMember = Get-FamilyMember $fileName $content
        }

        # Only read content if needed for category
        if ($category -eq "General") {
            $content = if ($content) { $content } else { Get-Content -Path $path -Raw }
            $category = Get-DocumentCategory $fileName $content
        }

        $targetPath = Join-Path $TargetDirectory "Documents\${familyMember}\${category}"
        
        if (!(Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }
        $destination = Move-Item-Safe -Path $path -Destination (Join-Path $targetPath $fileName)

        if (!$script:fileCount.Documents.ByFamily.ContainsKey($familyMember)) {
            $script:fileCount.Documents.ByFamily[$familyMember] = @{}
        }
        if (!$script:fileCount.Documents.ByFamily[$familyMember].ContainsKey($category)) {
            $script:fileCount.Documents.ByFamily[$familyMember][$category] = 0
        }
        $script:fileCount.Documents.ByFamily[$familyMember][$category]++
        
        Write-Host "Moved document to ${familyMember}\${category}: ${fileName}" -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Failed to move document: ${fileName}`nError: $_"
    }
}

# Main processing logic
Write-Host "`nStarting file organization...`n" -ForegroundColor Blue

$totalItems = (Get-ChildItem -Path $SourceDirectory -Recurse).Count
$processed = 0

Get-ChildItem -Path $SourceDirectory -Recurse | ForEach-Object {
    $currentPath = $_.FullName
    $processed++
    
    Write-Progress -Activity "Organizing Files" -Status "Processing: ${$_.Name}" `
        -PercentComplete (($processed / $totalItems) * 100)
    
    if ($_.PSIsContainer) {
        if (Test-IsDevelopmentProject $currentPath) {
            Move-DevelopmentProject $currentPath
        }
    }
    else {
        $extension = $_.Extension.ToLower()
        
        if ($imageExtensions -contains $extension) {
            Move-MediaFile $currentPath "Images"
        }
        elseif ($videoExtensions -contains $extension) {
            Move-MediaFile $currentPath "Videos"
        }
        elseif ($documentExtensions -contains $extension) {
            $category = Get-DocumentCategory $currentPath
            Move-Document $currentPath $category
        }
        else {
            Move-UnknownFile $currentPath
        }
    }
}

Write-Progress -Activity "Organizing Files" -Completed

# Display summary
Write-Host "`nOrganization Summary:" -ForegroundColor Blue
Write-Host "===================" -ForegroundColor Blue
Write-Host "Development Projects: ${$script:fileCount.Development}" -ForegroundColor Green
Write-Host "Images: ${$script:fileCount.Images}" -ForegroundColor Cyan
Write-Host "Videos: ${$script:fileCount.Videos}" -ForegroundColor Cyan
Write-Host "Unknown Files: ${$script:fileCount.Unknown}" -ForegroundColor Red
Write-Host "`nDocuments by Family Member:" -ForegroundColor Yellow
foreach ($member in $script:fileCount.Documents.ByFamily.Keys) {
    Write-Host "`n${member}:" -ForegroundColor Yellow
    foreach ($category in $script:fileCount.Documents.ByFamily[$member].Keys) {
        Write-Host "  - ${category}: $($script:fileCount.Documents.ByFamily[$member][$category])" -ForegroundColor Yellow
    }
}

Write-Host "`nFile organization complete!" -ForegroundColor Blue
