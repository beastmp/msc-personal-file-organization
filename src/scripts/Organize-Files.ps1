param(
    [string]$SourceDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Organized",
    [string]$TargetDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Organized"
)

# Initialize counters
$script:fileCount = @{
    Development = @{ Projects = 0; Standalone = 0 }
    Media = @{ Images = 0; Videos = 0 }
    Documents = @{ ByFamily = @{} }
    Unknown = 0
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
$config.categories.PSObject.Properties | ForEach-Object {$categoryKeywords[$_.Name] = @{Include = $_.Value.include;Exclude = $_.Value.exclude}}

# Convert family members to hashtable
$familyKeywords = @{}
$config.familyMembers.PSObject.Properties | ForEach-Object {$familyKeywords[$_.Name] = @{Include = $_.Value.include;Exclude = $_.Value.exclude}}

function Convert-WildcardToRegex {param([string]$pattern) return [regex]::Escape($pattern).Replace("\*", "[\s\w-]+")}

function Test-ContentMatch {param([string]$content,[string[]]$includePatterns,[string[]]$excludePatterns)
    foreach ($pattern in $excludePatterns) {$regexPattern = Convert-WildcardToRegex $pattern;if ($content -match $regexPattern) {return $false}}
    foreach ($pattern in $includePatterns) {$regexPattern = Convert-WildcardToRegex $pattern;if ($content -match $regexPattern) {return $true}}
    return $false
}

function Test-IsDevelopmentProject {param([string]$path)
    $projectIndicators = @('package.json','.sln','.csproj','.vbproj','.gitignore','pom.xml','build.gradle','.project','Makefile','docker-compose.yml')
    foreach ($indicator in $projectIndicators) {if (Test-Path (Join-Path $path $indicator)) {return $true}}
    if ((Test-Path (Join-Path $path ".vs")) -or (Test-Path (Join-Path $path ".git"))) {return $true}
    $devFileCount = (Get-ChildItem -Path $path -File -Recurse | Where-Object { $developmentExtensions -contains $_.Extension }).Count
    return ($devFileCount -gt 1) -and (Get-ChildItem -Path $path -Directory).Count -gt 0
}

function Test-IsStandaloneDevelopmentFile {param([string]$path) $extension = [System.IO.Path]::GetExtension($path).ToLower();return $developmentExtensions -contains $extension}

function Move-Item-Safe {param([string]$Path,[string]$Destination)
    $fileName = Split-Path $Destination -Leaf
    $targetDir = Split-Path $Destination -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $extension = [System.IO.Path]::GetExtension($fileName)
    $counter = 1
    if (Test-Path $Destination) {
        $sourceHash = (Get-FileHash -Path $Path).Hash
        $destHash = (Get-FileHash -Path $Destination).Hash
        if ($sourceHash -eq $destHash) {Write-Verbose "Skipping identical file: $fileName";return $Destination}
        while (Test-Path $Destination) {$Destination = Join-Path $targetDir "${baseName}_${counter}${extension}";$counter++}
    }
    Move-Item -Path $Path -Destination $Destination -Force
    return $Destination
}

function Get-FamilyMember {param([string]$fileName,[string]$content = "")
    foreach ($member in $familyKeywords.Keys) {
        if (Test-ContentMatch -content $fileName -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {return $member}
    }
    if ($content) {
        foreach ($member in $familyKeywords.Keys) {if (Test-ContentMatch -content $content -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {return $member}}
    }
    return "01 - Family"
}

function Get-DocumentCategory {param([string]$fileName,[string]$content = "")
    foreach ($category in $categoryKeywords.Keys) {
        if (Test-ContentMatch -content $fileName -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {return $category}
    }
    if ($content) {
        foreach ($category in $categoryKeywords.Keys) {
            if (Test-ContentMatch -content $content -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {return $category}
        }
    }
    return "General"
}

# File organization class
class FileOrganizationInfo {
    [string]$SourcePath
    [string]$TargetPath
    [string]$Category
    [string]$SubCategory
    [string]$FamilyMember
    [bool]$IsDirectory
    [string]$FileType
    [string]$RelativePath  # For development projects
    [string]$ColorCode  # Add color code property
    
    FileOrganizationInfo([string]$sourcePath, [bool]$isDirectory) {
        $this.SourcePath = $sourcePath
        $this.IsDirectory = $isDirectory
        $this.FileType = if ($isDirectory) { "Directory" } else { [System.IO.Path]::GetExtension($sourcePath).ToLower() }
        $this.ColorCode = 'White'  # Default color
    }
}

# Initialize file collection
$script:fileCollection = @()

function Add-ToFileCollection {
    param(
        [FileOrganizationInfo]$fileInfo,
        [string]$category,
        [string]$subCategory = "",
        [string]$familyMember = "",
        [string]$targetPath = "",
        [string]$colorCode = 'White'
    )
    
    $fileInfo.Category = $category
    $fileInfo.SubCategory = $subCategory
    $fileInfo.FamilyMember = $familyMember
    $fileInfo.TargetPath = $targetPath
    $fileInfo.ColorCode = $colorCode
    $script:fileCollection += $fileInfo
}

function Initialize-FileInfo {
    param([string]$path, [bool]$isDirectory)
    
    $fileInfo = [FileOrganizationInfo]::new($path, $isDirectory)
    
    if ($isDirectory) {
        if (Test-IsDevelopmentProject $path) {
            $relativePath = $path
            if ($path.StartsWith($SourceDirectory)) {
                $relativePath = $path.Substring($SourceDirectory.Length).TrimStart('\')
            }
            $targetPath = Join-Path $TargetDirectory "Development\Projects\$relativePath"
            Add-ToFileCollection -fileInfo $fileInfo -category "Development" -subCategory "Project" -targetPath $targetPath -colorCode 'Green'
        }
        return
    }
    
    # Handle file categorization
    $extension = $fileInfo.FileType
    
    if (Test-IsStandaloneDevelopmentFile $path) {
        $fileType = switch -Wildcard ($extension) {
            ".ps1" { "PowerShell" }
            ".sql" { "SQL" }
            ".py"  { "Python" }
            ".js"  { "JavaScript" }
            ".ts"  { "TypeScript" }
            default { "Other" }
        }
        $targetPath = Join-Path $TargetDirectory "Development\Standalone\$fileType\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Development" -subCategory "Standalone" -targetPath $targetPath -colorCode 'Green'
    }
    elseif ($imageExtensions -contains $extension) {
        $targetPath = Join-Path $TargetDirectory "Media\Images\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Media" -subCategory "Images" -targetPath $targetPath -colorCode 'Cyan'
    }
    elseif ($videoExtensions -contains $extension) {
        $targetPath = Join-Path $TargetDirectory "Media\Videos\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Media" -subCategory "Videos" -targetPath $targetPath -colorCode 'Cyan'
    }
    elseif ($documentExtensions -contains $extension) {
        $fileName = Split-Path $path -Leaf
        $familyMember = Get-FamilyMember $fileName
        $category = Get-DocumentCategory $fileName
        
        if ($familyMember -eq "01 - Family" -or $category -eq "General") {
            try {
                $content = Get-Content -Path $path -Raw
                if ($familyMember -eq "01 - Family") {
                    $familyMember = Get-FamilyMember $fileName $content
                }
                if ($category -eq "General") {
                    $category = Get-DocumentCategory $fileName $content
                }
            }
            catch {
                Write-Warning "Could not read content of file: $fileName"
            }
        }
        
        $targetPath = Join-Path $TargetDirectory "Documents\${familyMember}\${category}\${fileName}"
        Add-ToFileCollection -fileInfo $fileInfo -category "Documents" -subCategory $category -familyMember $familyMember -targetPath $targetPath -colorCode 'Yellow'
    }
    else {
        $targetPath = Join-Path $TargetDirectory "Unknown\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Unknown" -targetPath $targetPath -colorCode 'Red'
    }
}

# Main processing logic
Write-Host "`nScanning files...`n" -ForegroundColor Blue

$totalItems = (Get-ChildItem -Path $SourceDirectory -Recurse).Count
$processed = 0

# First pass: Scan and analyze all files
Get-ChildItem -Path $SourceDirectory -Recurse | ForEach-Object {
    $processed++
    $progressPercentage = [Math]::Min(100, [Math]::Floor(($processed / $totalItems) * 100))
    Write-Progress -Activity "Scanning Files" -Status "Analyzing: $($_.Name)" -PercentComplete $progressPercentage
    
    Initialize-FileInfo -path $_.FullName -isDirectory $_.PSIsContainer
}

Write-Progress -Activity "Scanning Files" -Completed

# Display pre-move summary
Write-Host "`nPre-move Summary:" -ForegroundColor Blue
Write-Host "================" -ForegroundColor Blue
$summary = $script:fileCollection | Group-Object Category
foreach ($category in $summary) {
    Write-Host "`n$($category.Name):" -ForegroundColor Yellow
    $subCategories = $category.Group | Group-Object SubCategory
    foreach ($sub in $subCategories) {
        $count = $sub.Count
        $subName = if ($sub.Name) { $sub.Name } else { "General" }
        Write-Host "  - $subName`: $count" -ForegroundColor Cyan
    }
}

# Second pass: Move files
Write-Host "`nMoving files...`n" -ForegroundColor Blue
$processed = 0
$totalMoves = $script:fileCollection.Count

# Process all files
$script:fileCollection | ForEach-Object {
    $processed++
    $progressPercentage = [Math]::Min(100, [Math]::Floor(($processed / $totalMoves) * 100))
    $fileName = Split-Path $_.SourcePath -Leaf
    Write-Progress -Activity "Moving Files" -Status "Moving: $fileName" -PercentComplete $progressPercentage
    
    $targetDir = Split-Path $_.TargetPath -Parent
    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    
    try {
        Move-Item-Safe -Path $_.SourcePath -Destination $_.TargetPath
        
        # Update counters with better error handling
        switch ($_.Category) {
            "Development" { 
                if ($_.SubCategory -eq "Project") { $script:fileCount.Development.Projects++ }
                else { $script:fileCount.Development.Standalone++ }
            }
            "Media" {
                if ($_.SubCategory -eq "Images") { $script:fileCount.Media.Images++ }
                else { $script:fileCount.Media.Videos++ }
            }
            "Documents" {
                $familyMember = if ([string]::IsNullOrEmpty($_.FamilyMember)) { "01 - Family" } else { $_.FamilyMember }
                $subCategory = if ([string]::IsNullOrEmpty($_.SubCategory)) { "General" } else { $_.SubCategory }
                
                if (!$script:fileCount.Documents.ByFamily.ContainsKey($familyMember)) {
                    $script:fileCount.Documents.ByFamily[$familyMember] = @{} 
                }
                if (!$script:fileCount.Documents.ByFamily[$familyMember].ContainsKey($subCategory)) {
                    $script:fileCount.Documents.ByFamily[$familyMember][$subCategory] = 0
                }
                $script:fileCount.Documents.ByFamily[$familyMember][$subCategory]++
            }
            "Unknown" { $script:fileCount.Unknown++ }
        }
        
        # Display move message with appropriate color
        Write-Host "Moved $($_.Category.ToLower()) file: $fileName" -ForegroundColor $_.ColorCode
    }
    catch {
        Write-Warning "Failed to move file: $fileName`nError: $_"
    }
}

Write-Progress -Activity "Moving Files" -Completed

Write-Host "`nOrganization Summary:" -ForegroundColor Blue
Write-Host "===================" -ForegroundColor Blue
Write-Host "`nDevelopment:" -ForegroundColor Green
Write-Host "  - Projects: $($script:fileCount.Development.Projects)" -ForegroundColor Green
Write-Host "  - Standalone: $($script:fileCount.Development.Standalone)" -ForegroundColor Green
Write-Host "`nMedia:" -ForegroundColor Cyan
Write-Host "  - Images: $($script:fileCount.Media.Images)" -ForegroundColor Cyan
Write-Host "  - Videos: $($script:fileCount.Media.Videos)" -ForegroundColor Cyan
Write-Host "`nUnknown Files: $($script:fileCount.Unknown)" -ForegroundColor Red
Write-Host "`nDocuments by Family Member:" -ForegroundColor Yellow
foreach ($member in $fileCount.Documents.ByFamily.Keys | Sort-Object) {
    Write-Host "`n$member`:" -ForegroundColor Yellow
    foreach ($category in $script:fileCount.Documents.ByFamily[$member].Keys | Sort-Object) {
        Write-Host "  - $category`: $($script:fileCount.Documents.ByFamily[$member][$category])" -ForegroundColor Yellow
    }
}

Write-Host "`nFile organization complete!" -ForegroundColor Blue
