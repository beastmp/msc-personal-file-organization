[CmdletBinding()]
param(
    [string]$SourceDirectory = "D:\Apps\Microsoft\OneDrive\Documents\Personal\Documents",
    [string]$TargetDirectory = "D:\Apps\Microsoft\OneDrive"
)

# File organization class
class FileOrganizationInfo {
    [string]$SourcePath
    [string]$TargetPath
    [string]$Category
    [string]$SubCategory
    [string]$TertiaryCategory
    [string]$FamilyMember
    [bool]$IsDirectory
    [string]$FileType
    [string]$RelativePath  # For development projects
    [string]$ColorCode  # Add color code property
    [bool]$ProcessedAsProject  # Add new flag
    [hashtable]$DetectedFamilyMembers  # Changed from string[] to hashtable
    [hashtable]$DetectedCategories  # Changed from string[] to hashtable
    [hashtable]$DetectedSubCategories  # New property for tier-2 categories
    [hashtable]$Metadata
    [bool]$UserSelected
    
    FileOrganizationInfo([string]$sourcePath, [bool]$isDirectory) {
        $this.SourcePath = $sourcePath
        $this.IsDirectory = $isDirectory
        $this.FileType = if ($isDirectory) { "Directory" } else { [System.IO.Path]::GetExtension($sourcePath).ToLower() }
        $this.ColorCode = 'White'  # Default color
        $this.ProcessedAsProject = $false
        $this.DetectedFamilyMembers = @{}
        $this.DetectedCategories = @{}
        $this.Metadata = @{}
        $this.UserSelected = $false
    }

    [void] AddFamilyMemberDetection([string]$member, [string]$source, [string]$pattern) {
        if (!$this.DetectedFamilyMembers.ContainsKey($member)) {
            $this.DetectedFamilyMembers[$member] = [DetectionSource]::new($member, $source, $pattern)
        } else {
            $this.DetectedFamilyMembers[$member].Sources += $source
            $this.DetectedFamilyMembers[$member].MatchedPatterns += $pattern
        }
    }

    [void] AddCategoryDetection([string]$category, [string]$source, [string]$pattern) {
        if (!$this.DetectedCategories.ContainsKey($category)) {
            $this.DetectedCategories[$category] = [DetectionSource]::new($category, $source, $pattern)
        } else {
            $this.DetectedCategories[$category].Sources += $source
            $this.DetectedCategories[$category].MatchedPatterns += $pattern
        }
    }
}

class DetectionSource {
    [string]$Value
    [string[]]$Sources
    [string[]]$MatchedPatterns

    DetectionSource([string]$value, [string]$source, [string]$pattern) {
        $this.Value = $value
        $this.Sources = @($source)
        $this.MatchedPatterns = @($pattern)
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

function Get-DuplicateDestination {
    param(
        [string]$SourcePath,
        [string]$FileName
    )
    
    $duplicatesDir = Join-Path $TargetDirectory "Duplicates"
    if (!(Test-Path $duplicatesDir)) {
        New-Item -ItemType Directory -Path $duplicatesDir -Force | Out-Null
    }
    
    $sourceHash = (Get-FileHash -Path $SourcePath).Hash
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [System.IO.Path]::GetExtension($FileName)
    $duplicatePath = Join-Path $duplicatesDir "${baseName}_${sourceHash}${extension}"
    
    return $duplicatePath
}

function Move-ItemSafe {
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
        $sourceHash = (Get-FileHash -Path $Path).Hash
        $destHash = (Get-FileHash -Path $Destination).Hash
        
        if ($sourceHash -eq $destHash) {
            # File is a duplicate but not identical path
            if ($Path -ne $Destination) {
                $duplicatePath = Get-DuplicateDestination -SourcePath $Path -FileName $fileName
                Write-Verbose "Moving duplicate file to: $duplicatePath"
                Move-Item -Path $Path -Destination $duplicatePath -Force
            } else {
                Write-Verbose "Skipping identical file with same path: $fileName"
            }
            return
        }
        
        while (Test-Path $Destination) {
            $Destination = Join-Path $targetDir "${baseName}_${counter}${extension}"
            $counter++
        }
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
    
    $result = @{
        Category = "General"
        SubCategory = $null
    }
    
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
            # First check if any top-level category with subcategories matches
            foreach ($category in $categoryKeywords.Keys) {
                if ($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") {
                    if (Test-ContentMatch -content $categoryText -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
                        $result.Category = $category
                        # Now check subcategories
                        foreach ($subCategory in $categoryKeywords[$category].subcategories.PSObject.Properties.Name) {
                            if (Test-ContentMatch -content $categoryText `
                                -includePatterns $categoryKeywords[$category].subcategories.$subCategory.Include `
                                -excludePatterns $categoryKeywords[$category].subcategories.$subCategory.Exclude) {
                                $result.SubCategory = $subCategory
                                return $result
                            }
                        }
                        # If no subcategory matched, just return the parent category
                        return $result
                    }
                }
            }
            
            # Then check regular categories
            foreach ($category in $categoryKeywords.Keys) {
                if (!($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") -and 
                    (Test-ContentMatch -content $categoryText -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude)) {
                    $result.Category = $category
                    return $result
                }
            }
        }
        
        # Check other metadata fields
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
                    $result.Category = $category
                    return $result
                }
            }
        }
    }
    
    # Check filename and content
    # First, check for categories with subcategories
    foreach ($category in $categoryKeywords.Keys) {
        if ($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") {
            if (Test-ContentMatch -content $fileName -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
                $result.Category = $category
                # Now check subcategories
                foreach ($subCategory in $categoryKeywords[$category].subcategories.PSObject.Properties.Name) {
                    if (Test-ContentMatch -content $fileName `
                        -includePatterns $categoryKeywords[$category].subcategories.$subCategory.Include `
                        -excludePatterns $categoryKeywords[$category].subcategories.$subCategory.Exclude) {
                        $result.SubCategory = $subCategory
                        return $result
                    }
                }
                # If no subcategory matched, just return the parent category
                return $result
            }
        }
    }
    
    # Then check regular categories
    foreach ($category in $categoryKeywords.Keys) {
        if (!($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") -and 
            (Test-ContentMatch -content $fileName -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude)) {
            $result.Category = $category
            return $result
        }
    }
    
    # Check content if provided
    if ($content) {
        # First, check for categories with subcategories
        foreach ($category in $categoryKeywords.Keys) {
            if ($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") {
                if (Test-ContentMatch -content $content -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude) {
                    $result.Category = $category
                    # Now check subcategories
                    foreach ($subCategory in $categoryKeywords[$category].subcategories.PSObject.Properties.Name) {
                        if (Test-ContentMatch -content $content `
                            -includePatterns $categoryKeywords[$category].subcategories.$subCategory.Include `
                            -excludePatterns $categoryKeywords[$category].subcategories.$subCategory.Exclude) {
                            $result.SubCategory = $subCategory
                            return $result
                        }
                    }
                    # If no subcategory matched, just return the parent category
                    return $result
                }
            }
        }
        
        # Then check regular categories
        foreach ($category in $categoryKeywords.Keys) {
            if (!($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") -and 
                (Test-ContentMatch -content $content -includePatterns $categoryKeywords[$category].Include -excludePatterns $categoryKeywords[$category].Exclude)) {
                $result.Category = $category
                return $result
            }
        }
    }
    
    return $result
}

function Add-ToFileCollection {
    param(
        [FileOrganizationInfo]$fileInfo,
        [string]$category,
        [string]$subCategory = "",
        [string]$tertiaryCategory = "",
        [string]$familyMember = "",
        [string]$targetPath = "",
        [string]$colorCode = 'White'
    )
    
    $fileInfo.Category = $category
    $fileInfo.SubCategory = $subCategory
    $fileInfo.TertiaryCategory = $tertiaryCategory
    $fileInfo.FamilyMember = $familyMember
    $fileInfo.TargetPath = $targetPath
    $fileInfo.ColorCode = $colorCode
    $script:fileCollection += $fileInfo
}

function Initialize-FileInfo {
    param([string]$path, [bool]$isDirectory)
    
    # Skip only Development folder
    $developmentFolder = Join-Path $TargetDirectory "Documents\Personal\Development"
    if ($path.StartsWith($developmentFolder)) {
        Write-Verbose "Skipping development folder: $path"
        return
    }
    
    $fileInfo = [FileOrganizationInfo]::new($path, $isDirectory)
    
    if ($isDirectory) {
        if (Test-IsDevelopmentProject $path) {
            $relativePath = $path
            if ($path.StartsWith($SourceDirectory)) {
                $relativePath = $path.Substring($SourceDirectory.Length).TrimStart('\')
            }
            
            $targetPath = Join-Path $TargetDirectory "Documents\Personal\Development\Projects\$relativePath"
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
        $targetPath = Join-Path $TargetDirectory "Documents\Personal\Development\Standalone\$fileType\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Development" -subCategory "Standalone" -targetPath $targetPath -colorCode 'Green'
    }
    elseif ($imageExtensions -contains $extension) {
        $targetPath = Join-Path $TargetDirectory "Media\Pictures\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Media" -subCategory "Pictures" -targetPath $targetPath -colorCode 'Cyan'
    }
    elseif ($videoExtensions -contains $extension) {
        $targetPath = Join-Path $TargetDirectory "Media\Videos\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Media" -subCategory "Videos" -targetPath $targetPath -colorCode 'Cyan'
    }
    elseif ($documentExtensions -contains $extension) {
        $fileName = Split-Path $path -Leaf
        $metadata = Get-FileMetadata -path $path
        $fileInfo.Metadata = $metadata
        
        try {
            $content = Get-Content -Path $path -Raw
        }
        catch {
            Write-Warning "Could not read content of file: $fileName"
            $content = ""
        }
        
        Get-AllPossibleFamilyMembers -fileInfo $fileInfo -content $content
        Get-AllPossibleCategories -fileInfo $fileInfo -content $content
        
        $previousResult = $script:previousResults[$path]
        $familyMember = if ($previousResult) {
            # Update to safely copy the hashtables
            $fileInfo.DetectedFamilyMembers = $previousResult.DetectedFamilyMembers.Clone()
            $fileInfo.UserSelected = $true
            $previousResult.FamilyMember
        } elseif ($fileInfo.DetectedFamilyMembers.Count -gt 0) {
            $fileInfo.UserSelected = $true
            Get-UserSelection -prompt "Select family member for $fileName" -detections $fileInfo.DetectedFamilyMembers -default "01 - Family"
        } else {
            "01 - Family"
        }
        
        $categoryResult = Get-DocumentCategory -fileName $fileName -content $content -metadata $metadata
        $category = $categoryResult.Category
        $subCategory = $categoryResult.SubCategory
        
        # Determine path structure based on whether we have a subcategory
        $categoryPath = if ($subCategory) {
            "$category\$subCategory"
        } else {
            $category
        }
        
        $targetPath = Join-Path $TargetDirectory "Documents\Personal\${familyMember}\${categoryPath}\${fileName}"
        Add-ToFileCollection -fileInfo $fileInfo -category "Documents" -subCategory $category -tertiaryCategory $subCategory -familyMember $familyMember -targetPath $targetPath -colorCode 'Yellow'
    }
    else {
        $targetPath = Join-Path $TargetDirectory "Documents\Personal\Unknown\$(Split-Path $path -Leaf)"
        Add-ToFileCollection -fileInfo $fileInfo -category "Unknown" -targetPath $targetPath -colorCode 'Red'
    }
}

function Get-AllPossibleFamilyMembers {
    param(
        [FileOrganizationInfo]$fileInfo,
        [string]$content = ""
    )
    
    # Check metadata
    if ($fileInfo.Metadata) {
        if (![string]::IsNullOrWhiteSpace($fileInfo.Metadata.Author)) {
            foreach ($member in $familyKeywords.Keys) {
                $patterns = $familyKeywords[$member].Include
                foreach ($pattern in $patterns) {
                    if (Test-ContentMatch -content $fileInfo.Metadata.Author -includePatterns @($pattern) -excludePatterns $familyKeywords[$member].Exclude) {
                        $fileInfo.AddFamilyMemberDetection($member, "Metadata (Author)", $pattern)
                    }
                }
            }
        }
        
        $metaFields = @{
            "Title" = $fileInfo.Metadata.Title
            "Subject" = $fileInfo.Metadata.Subject
            "Comments" = $fileInfo.Metadata.Comments
            "Tags" = $fileInfo.Metadata.Tags
        }
        
        foreach ($field in $metaFields.Keys) {
            if (![string]::IsNullOrWhiteSpace($metaFields[$field])) {
                foreach ($member in $familyKeywords.Keys) {
                    $patterns = $familyKeywords[$member].Include
                    foreach ($pattern in $patterns) {
                        if (Test-ContentMatch -content $metaFields[$field] -includePatterns @($pattern) -excludePatterns $familyKeywords[$member].Exclude) {
                            $fileInfo.AddFamilyMemberDetection($member, "Metadata ($field)", $pattern)
                        }
                    }
                }
            }
        }
    }
    
    # Check filename
    $fileName = Split-Path $fileInfo.SourcePath -Leaf
    foreach ($member in $familyKeywords.Keys) {
        $patterns = $familyKeywords[$member].Include
        foreach ($pattern in $patterns) {
            if (Test-ContentMatch -content $fileName -includePatterns @($pattern) -excludePatterns $familyKeywords[$member].Exclude) {
                $fileInfo.AddFamilyMemberDetection($member, "Filename", $pattern)
            }
        }
    }
    
    # Check content
    if ($content) {
        foreach ($member in $familyKeywords.Keys) {
            $patterns = $familyKeywords[$member].Include
            foreach ($pattern in $patterns) {
                if (Test-ContentMatch -content $content -includePatterns @($pattern) -excludePatterns $familyKeywords[$member].Exclude) {
                    $fileInfo.AddFamilyMemberDetection($member, "Content", $pattern)
                }
            }
        }
    }
    
    return $fileInfo.DetectedFamilyMembers
}

function Get-AllPossibleCategories {
    param(
        [FileOrganizationInfo]$fileInfo,
        [string]$content = ""
    )
    
    $detections = @{}
    
    # Check metadata
    if ($fileInfo.Metadata) {
        $categoryContent = @(
            $fileInfo.Metadata.Category,
            $fileInfo.Metadata.ContentType,
            $fileInfo.Metadata.Project,
            $fileInfo.Metadata.Company,
            $fileInfo.Metadata.Program
        ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        
        if ($categoryContent.Count -gt 0) {
            $categoryText = $categoryContent -join " "
            foreach ($category in $categoryKeywords.Keys) {
                $patterns = $categoryKeywords[$category].Include
                foreach ($pattern in $patterns) {
                    if (Test-ContentMatch -content $categoryText -includePatterns @($pattern) -excludePatterns $categoryKeywords[$category].Exclude) {
                        $fileInfo.AddCategoryDetection($category, "Metadata (Category)", $pattern)
                        
                        # Also check subcategories
                        if ($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") {
                            foreach ($subCategory in $categoryKeywords[$category].subcategories.PSObject.Properties.Name) {
                                $subPatterns = $categoryKeywords[$category].subcategories.$subCategory.Include
                                foreach ($subPattern in $subPatterns) {
                                    if (Test-ContentMatch -content $categoryText -includePatterns @($subPattern) `
                                        -excludePatterns $categoryKeywords[$category].subcategories.$subCategory.Exclude) {
                                        $fileInfo.AddCategoryDetection("$category/$subCategory", "Metadata (Category)", $subPattern)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        $generalContent = @(
            $fileInfo.Metadata.Keywords,
            $fileInfo.Metadata.Subject,
            $fileInfo.Metadata.Title,
            $fileInfo.Metadata.Comments,
            $fileInfo.Metadata.Tags,
            $fileInfo.Metadata.FileDescription
        ) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        
        if ($generalContent.Count -gt 0) {
            $metaText = $generalContent -join " "
            foreach ($category in $categoryKeywords.Keys) {
                $patterns = $categoryKeywords[$category].Include
                foreach ($pattern in $patterns) {
                    if (Test-ContentMatch -content $metaText -includePatterns @($pattern) -excludePatterns $categoryKeywords[$category].Exclude) {
                        $fileInfo.AddCategoryDetection($category, "Metadata (General)", $pattern)
                        
                        # Also check subcategories
                        if ($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") {
                            foreach ($subCategory in $categoryKeywords[$category].subcategories.PSObject.Properties.Name) {
                                $subPatterns = $categoryKeywords[$category].subcategories.$subCategory.Include
                                foreach ($subPattern in $subPatterns) {
                                    if (Test-ContentMatch -content $metaText -includePatterns @($subPattern) `
                                        -excludePatterns $categoryKeywords[$category].subcategories.$subCategory.Exclude) {
                                        $fileInfo.AddCategoryDetection("$category/$subCategory", "Metadata (General)", $subPattern)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    # Check filename
    $fileName = Split-Path $fileInfo.SourcePath -Leaf
    foreach ($category in $categoryKeywords.Keys) {
        $patterns = $categoryKeywords[$category].Include
        foreach ($pattern in $patterns) {
            if (Test-ContentMatch -content $fileName -includePatterns @($pattern) -excludePatterns $categoryKeywords[$category].Exclude) {
                $fileInfo.AddCategoryDetection($category, "Filename", $pattern)
                
                # Also check subcategories
                if ($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") {
                    foreach ($subCategory in $categoryKeywords[$category].subcategories.PSObject.Properties.Name) {
                        $subPatterns = $categoryKeywords[$category].subcategories.$subCategory.Include
                        foreach ($subPattern in $subPatterns) {
                            if (Test-ContentMatch -content $fileName -includePatterns @($subPattern) `
                                -excludePatterns $categoryKeywords[$category].subcategories.$subCategory.Exclude) {
                                $fileInfo.AddCategoryDetection("$category/$subCategory", "Filename", $subPattern)
                            }
                        }
                    }
                }
            }
        }
    }
    
    # Check content
    if ($content) {
        foreach ($category in $categoryKeywords.Keys) {
            $patterns = $categoryKeywords[$category].Include
            foreach ($pattern in $patterns) {
                if (Test-ContentMatch -content $content -includePatterns @($pattern) -excludePatterns $categoryKeywords[$category].Exclude) {
                    $fileInfo.AddCategoryDetection($category, "Content", $pattern)
                    
                    # Also check subcategories
                    if ($categoryKeywords[$category].PSObject.Properties.Name -contains "subcategories") {
                        foreach ($subCategory in $categoryKeywords[$category].subcategories.PSObject.Properties.Name) {
                            $subPatterns = $categoryKeywords[$category].subcategories.$subCategory.Include
                            foreach ($subPattern in $subPatterns) {
                                if (Test-ContentMatch -content $content -includePatterns @($subPattern) `
                                    -excludePatterns $categoryKeywords[$category].subcategories.$subCategory.Exclude) {
                                    $fileInfo.AddCategoryDetection("$category/$subCategory", "Content", $subPattern)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return $fileInfo.DetectedCategories
}

function Get-UserSelection {
    param(
        [string]$prompt,
        [hashtable]$detections,
        [string]$default
    )
    
    if ($detections.Count -eq 0) { return $default }
    if ($detections.Count -eq 1) { return $detections.Keys | Select-Object -First 1 }
    
    Write-Host "`n$prompt" -ForegroundColor Yellow
    
    $i = 1
    $options = @()
    Write-Host "Matches found:" -ForegroundColor Cyan
    foreach ($key in $detections.Keys | Sort-Object) {
        $detection = $detections[$key]
        $options += $key
        
        $sources = ($detection.Sources | Select-Object -Unique) -join ', '
        $patterns = ($detection.MatchedPatterns | Select-Object -Unique) -join ', '
        
        # Add indicator if this was previously selected
        $previousIndicator = if ($detection.Value -eq $default) { " (Previous Selection)" } else { "" }
        Write-Host "$i`: $($detection.Value)$previousIndicator | Sources: [$sources] Matches: [$patterns]" -ForegroundColor Gray
        $i++
    }
    
    Write-Host "D: Default ($default)" -ForegroundColor DarkGray
    
    do {
        $response = Read-Host "> "
        if ($response -eq "D") { return $default }
        if ($response -match '^\d+$') {
            $index = [int]$response - 1
            if ($index -ge 0 -and $index -lt $options.Count) {
                return $options[$index]
            }
        }
    } while ($true)
}

# Initialize counters
$script:fileCount = @{
    Development = @{ Projects = 0; Standalone = 0 }
    Media = @{ Pictures = 0; Videos = 0 }  # Changed Images to Pictures
    Documents = @{ 
        ByFamily = @{}
        MultiTier = @{}  # Add tracking for multi-tier categories
    }
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
$config.categories.PSObject.Properties | ForEach-Object {$categoryKeywords[$_.Name] = @{Include = $_.Value.include;Exclude = $_.Value.exclude;subcategories = $_.Value.subcategories}}

# Convert family members to hashtable
$familyKeywords = @{}
$config.familyMembers.PSObject.Properties | ForEach-Object {$familyKeywords[$_.Name] = @{Include = $_.Value.include;Exclude = $_.Value.exclude}}

# Replace the previous results loading section with this updated version
$script:previousResults = @{}
$previousResultsPath = Join-Path $TargetDirectory ".file-organization-results.json"
if (Test-Path $previousResultsPath) {
    Write-Host "Loading previous results from: $previousResultsPath" -ForegroundColor Blue
    $previousData = Get-Content $previousResultsPath | ConvertFrom-Json
    foreach ($item in $previousData) {
        if ($item.UserSelected) {
            # Convert PSCustomObject to Hashtables
            $detectedFamilyMembers = @{
            }
            if ($item.DetectedFamilyMembers.PSObject.Properties) {
                foreach ($prop in $item.DetectedFamilyMembers.PSObject.Properties) {
                    $detectionSource = [DetectionSource]::new(
                        $prop.Value.Value,
                        [string[]]$prop.Value.Sources,
                        [string[]]$prop.Value.MatchedPatterns
                    )
                    $detectedFamilyMembers[$prop.Name] = $detectionSource
                }
            }

            $detectedCategories = @{
            }
            if ($item.DetectedCategories.PSObject.Properties) {
                foreach ($prop in $item.DetectedCategories.PSObject.Properties) {
                    $detectionSource = [DetectionSource]::new(
                        $prop.Value.Value,
                        [string[]]$prop.Value.Sources,
                        [string[]]$prop.Value.MatchedPatterns
                    )
                    $detectedCategories[$prop.Name] = $detectionSource
                }
            }

            $script:previousResults[$item.SourcePath] = @{
                Category = $item.Category
                SubCategory = $item.SubCategory
                FamilyMember = $item.FamilyMember
                DetectedFamilyMembers = $detectedFamilyMembers
                DetectedCategories = $detectedCategories
            }
        }
    }
    Write-Host "Loaded $($script:previousResults.Count) previous selections" -ForegroundColor Blue
}

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
                if ($_.SubCategory -eq "Pictures") { $script:fileCount.Media.Pictures++ }  # Changed from Images
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
            # For multi-tier categories, show the full path
            $categoryDisplayInfo = if ($_.TertiaryCategory) {
                "$($_.SubCategory)/$($_.TertiaryCategory)"
            } else {
                $_.SubCategory
            }
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
Write-Host "  - Pictures: $($script:fileCount.Media.Pictures)" -ForegroundColor Cyan  # Changed from Images
Write-Host "  - Videos: $($script:fileCount.Media.Videos)" -ForegroundColor Cyan
Write-Host "`nUnknown Files: $($script:fileCount.Unknown)" -ForegroundColor Red
Write-Host "`nDocuments by Family Member:" -ForegroundColor Yellow
foreach ($member in $fileCount.Documents.ByFamily.Keys | Sort-Object) {
    Write-Host "`n$member`:" -ForegroundColor Yellow
    foreach ($category in $script:fileCount.Documents.ByFamily[$member].Keys | Sort-Object) {
        Write-Host "  - $category`: $($script:fileCount.Documents.ByFamily[$member][$category])" -ForegroundColor Yellow
    }
}

# Replace the results saving section with this updated version
$jsonPath = Join-Path $TargetDirectory ".file-organization-results.json"
$fileCollection | ConvertTo-Json -Depth 10 | Set-Content $jsonPath
Write-Host "`nFile organization details exported to: $jsonPath" -ForegroundColor Blue

Write-Host "`nFile organization complete!" -ForegroundColor Blue
