[CmdletBinding()]
param(
    [string]$SourceDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Organized",
    [string]$TargetDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Organized"
)

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
    [bool]$ProcessedAsProject  # Add new flag
    
    FileOrganizationInfo([string]$sourcePath, [bool]$isDirectory) {
        $this.SourcePath = $sourcePath
        $this.IsDirectory = $isDirectory
        $this.FileType = if ($isDirectory) { "Directory" } else { [System.IO.Path]::GetExtension($sourcePath).ToLower() }
        $this.ColorCode = 'White'  # Default color
        $this.ProcessedAsProject = $false
    }
}

function Convert-WildcardToRegex {param([string]$pattern) return [regex]::Escape($pattern).Replace("\*", "[\s\w-]+")}

function Test-ContentMatch {param([string]$content,[string[]]$includePatterns,[string[]]$excludePatterns)
    foreach ($pattern in $excludePatterns) {$regexPattern = Convert-WildcardToRegex $pattern;if ($content -match $regexPattern) {return $false}}
    foreach ($pattern in $includePatterns) {$regexPattern = Convert-WildcardToRegex $pattern;if ($content -match $regexPattern) {return $true}}
    return $false
}

function Test-IsDevelopmentProject {
    param([string]$path)
    
    # Standard project indicators
    $projectIndicators = @(
        'package.json','.sln','.csproj','.vbproj','.gitignore',
        'pom.xml','build.gradle','.project','Makefile',
        'docker-compose.yml','requirements.txt','setup.py'
    )
    
    # Special directories that indicate a project
    $projectDirs = @(
        '.vs','.git','__pycache__','node_modules',
        'bin','obj','build','dist','target'
    )
    
    # Check project files
    foreach ($indicator in $projectIndicators) {
        if (Test-Path (Join-Path $path $indicator)) {
            return $true
        }
    }
    
    # Check special directories
    foreach ($dir in $projectDirs) {
        if (Test-Path (Join-Path $path $dir)) {
            return $true
        }
    }
    
    # Count files by extension to detect multi-file projects
    $files = Get-ChildItem -Path $path -File -Recurse
    $extensionGroups = $files | Group-Object Extension
    
    # If we have multiple files of the same type, likely a project
    foreach ($group in $extensionGroups) {
        if ($developmentExtensions -contains $group.Name -and $group.Count -gt 1) {
            return $true
        }
    }
    
    return $false
}

function Test-IsStandaloneDevelopmentFile {param([string]$path) $extension = [System.IO.Path]::GetExtension($path).ToLower();return $developmentExtensions -contains $extension}

function Move-ItemSafe {param([string]$Path,[string]$Destination)
    $fileName = Split-Path $Destination -Leaf
    $targetDir = Split-Path $Destination -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $extension = [System.IO.Path]::GetExtension($fileName)
    $counter = 1
    if (Test-Path $Destination) {
        $sourceHash = (Get-FileHash -Path $Path).Hash
        $destHash = (Get-FileHash -Path $Destination).Hash
        if ($sourceHash -eq $destHash) {Write-Verbose "Skipping identical file: $fileName";return}
        while (Test-Path $Destination) {$Destination = Join-Path $targetDir "${baseName}_${counter}${extension}";$counter++}
    }
    Move-Item -Path $Path -Destination $Destination -Force
}

function Get-FileMetadata {
    param([string]$path)
    
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = Split-Path $path -Parent
        $file = Split-Path $path -Leaf
        $shellfolder = $shell.Namespace($folder)
        $shellfile = $shellfolder.ParseName($file)
        
        $metadata = @{
            # Existing metadata fields
            Author = $shellfolder.GetDetailsOf($shellfile, 20)
            Title = $shellfolder.GetDetailsOf($shellfile, 21)
            Subject = $shellfolder.GetDetailsOf($shellfile, 22)
            Keywords = $shellfolder.GetDetailsOf($shellfile, 23)
            Comments = $shellfolder.GetDetailsOf($shellfile, 24)
            Tags = $shellfolder.GetDetailsOf($shellfile, 18)
            
            # Additional category-related fields
            Category = $shellfolder.GetDetailsOf($shellfile, 5)    # Document category
            ContentType = $shellfolder.GetDetailsOf($shellfile, 11) # Content type/category
            FileDescription = $shellfolder.GetDetailsOf($shellfile, 34) # File description
            Company = $shellfolder.GetDetailsOf($shellfile, 25)    # Company (useful for Work category)
            Program = $shellfolder.GetDetailsOf($shellfile, 7)     # Program name (useful for Games)
            Project = $shellfolder.GetDetailsOf($shellfile, 63)    # Project name
        }
        
        # Clean up COM objects
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shellfile) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shellfolder) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        
        return $metadata
    }
    catch {
        Write-Warning "Could not read metadata for file: $path"
        return $null
    }
}

function Get-FamilyMember {
    param(
        [string]$fileName,
        [string]$content = "",
        [hashtable]$metadata = $null
    )
    
    # Check metadata first
    if ($metadata) {
        # Check Author field
        if (![string]::IsNullOrWhiteSpace($metadata.Author)) {
            foreach ($member in $familyKeywords.Keys) {
                if (Test-ContentMatch -content $metadata.Author -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {
                    return $member
                }
            }
        }
        
        # Check other metadata fields for family member hints
        $metaContent = @($metadata.Title, $metadata.Subject, $metadata.Comments, $metadata.Tags) -join " "
        if (![string]::IsNullOrWhiteSpace($metaContent)) {
            foreach ($member in $familyKeywords.Keys) {
                if (Test-ContentMatch -content $metaContent -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {
                    return $member
                }
            }
        }
    }
    
    # Then check filename and content as before
    foreach ($member in $familyKeywords.Keys) {
        if (Test-ContentMatch -content $fileName -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {return $member}
    }
    if ($content) {
        foreach ($member in $familyKeywords.Keys) {if (Test-ContentMatch -content $content -includePatterns $familyKeywords[$member].Include -excludePatterns $familyKeywords[$member].Exclude) {return $member}}
    }
    return "01 - Family"
}

function Get-DocumentCategory {
    param(
        [string]$fileName,
        [string]$content = "",
        [hashtable]$metadata = $null
    )
    
    # Check metadata first
    if ($metadata) {
        # Combine all relevant metadata fields with priority on category-specific fields
        $categoryContent = @(
            $metadata.Category,
            $metadata.ContentType,
            $metadata.Project,
            $metadata.Company,
            $metadata.Program
        ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        
        # Check category-specific fields first
        if ($categoryContent.Count -gt 0) {
            $categoryText = $categoryContent -join " "
            foreach ($category in $categoryKeywords.Keys) {
                if (Test-ContentMatch -content $categoryText -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
                    return $category
                }
            }
        }
        
        # Then check other metadata fields
        $generalContent = @(
            $metadata.Keywords,
            $metadata.Subject,
            $metadata.Title,
            $metadata.Comments,
            $metadata.Tags,
            $metadata.FileDescription
        ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        
        if ($generalContent.Count -gt 0) {
            $metaText = $generalContent -join " "
            foreach ($category in $categoryKeywords.Keys) {
                if (Test-ContentMatch -content $metaText -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
                    return $category
                }
            }
        }
    }
    
    # Then check filename and content as before
    foreach ($category in $categoryKeywords.Keys) {
        if (Test-ContentMatch -content $fileName -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {return $category}
    }
    if ($content) {
        foreach ($category in $categoryKeywords.Keys) {
            if (Test-ContentMatch -content $content -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
                return $category
            }
        }
    }
    return "General"
}

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
    
    # Skip only Development\Projects folder
    $projectsFolder = Join-Path $TargetDirectory "Development\Projects"
    if ($path.StartsWith($projectsFolder)) {
        Write-Verbose "Skipping projects folder: $path"
        return
    }
    
    $fileInfo = [FileOrganizationInfo]::new($path, $isDirectory)
    
    if ($isDirectory) {
        if (Test-IsDevelopmentProject $path) {
            $relativePath = $path
            if ($path.StartsWith($SourceDirectory)) {
                $relativePath = $path.Substring($SourceDirectory.Length).TrimStart('\')
                
                # Remove existing Development\Projects from the path if it exists
                if ($relativePath -match '^Development\\Projects\\(.+)$') {
                    $relativePath = $matches[1]
                }
            }
            
            $targetPath = Join-Path $TargetDirectory "Development\Projects\$relativePath"
            Add-ToFileCollection -fileInfo $fileInfo -category "Development" -subCategory "Project" -targetPath $targetPath -colorCode 'Green'
            
            # Mark all files in this project
            Get-ChildItem -Path $path -File -Recurse | ForEach-Object {
                $childInfo = [FileOrganizationInfo]::new($_.FullName, $false)
                $childInfo.ProcessedAsProject = $true
                $script:fileCollection += $childInfo
            }
        }
        return
    }
    
    # Skip if already processed as part of a project
    if ($script:fileCollection.Where({ $_.SourcePath -eq $path -and $_.ProcessedAsProject }, 'First').Count -gt 0) {
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
        $metadata = Get-FileMetadata -path $path
        $familyMember = Get-FamilyMember -fileName $fileName -metadata $metadata
        $category = Get-DocumentCategory -fileName $fileName -metadata $metadata
        
        if ($familyMember -eq "01 - Family" -or $category -eq "General") {
            try {
                $content = Get-Content -Path $path -Raw
                if ($familyMember -eq "01 - Family") {
                    $familyMember = Get-FamilyMember -fileName $fileName -content $content -metadata $metadata
                }
                if ($category -eq "General") {
                    $category = Get-DocumentCategory -fileName $fileName -content $content -metadata $metadata
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


# Initialize file collection
$script:fileCollection = @()

# Main processing logic
Write-Host "`nScanning files...`n" -ForegroundColor Blue

$projectsFolder = Join-Path $TargetDirectory "Development\Projects"
$totalItems = (Get-ChildItem -Path $SourceDirectory -Recurse | 
    Where-Object { 
        $path = $_.FullName
        !$path.StartsWith($projectsFolder)
    }).Count
$processed = 0

# First pass: Scan and analyze all files
Get-ChildItem -Path $SourceDirectory -Recurse | 
    Where-Object { 
        $path = $_.FullName
        !$path.StartsWith($projectsFolder)
    } | ForEach-Object {
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
$script:fileCollection | Where-Object { !$_.ProcessedAsProject } | ForEach-Object {
    $processed++
    $progressPercentage = [Math]::Min(100, [Math]::Floor(($processed / $totalMoves) * 100))
    $fileName = Split-Path $_.SourcePath -Leaf
    Write-Progress -Activity "Moving Files" -Status "Moving: $fileName" -PercentComplete $progressPercentage
    
    $targetDir = Split-Path $_.TargetPath -Parent
    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    
    try {
        Move-ItemSafe -Path $_.SourcePath -Destination $_.TargetPath
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
        
        # Display move message with appropriate color if verbose flag is set
        if ($VerbosePreference -eq 'Continue') {
            Write-Host "Moved $($_.Category.ToLower()) file [$fileName] to $($_.TargetPath)" -ForegroundColor $_.ColorCode
        }
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
