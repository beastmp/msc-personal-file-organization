BeforeAll {
    # Import the script
    . $PSScriptRoot/../scripts/Organize-Files.ps1
    
    # Create test directories in TestDrive
    $script:sourceDir = Join-Path $TestDrive "Source"
    $script:targetDir = Join-Path $TestDrive "Target"
    
    New-Item -ItemType Directory -Path $sourceDir -Force
    New-Item -ItemType Directory -Path $targetDir -Force
    
    # Helper function to create test files in TestDrive
    function New-TestFile {
        param(
            [string]$Path,
            [string]$Content = "",
            [hashtable]$Metadata = @{}
        )
        
        # Ensure parent directory exists
        $parentDir = Split-Path $Path -Parent
        if (!(Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force
        }
        
        Set-Content -Path $Path -Value $Content -Force
        
        # Mock metadata for the file
        Mock Get-FileMetadata -ParameterFilter { $path -eq $Path } -MockWith { $Metadata }
    }
}

Describe "File Organization Tests" {
    BeforeEach {
        # Clear test directories
        Get-ChildItem -Path $sourceDir -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse
        Get-ChildItem -Path $targetDir -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse
        
        # Recreate root directories
        New-Item -ItemType Directory -Path $sourceDir -Force
        New-Item -ItemType Directory -Path $targetDir -Force
        
        # Reset collections and counters
        $script:fileCollection = @()
        $script:fileCount = @{
            Development = @{ Projects = 0; Standalone = 0 }
            Media = @{ Pictures = 0; Videos = 0 }
            Documents = @{ ByFamily = @{} }
            Unknown = 0
        }
    }
    
    Context "Development File Detection" {
        It "Identifies PowerShell scripts correctly" {
            $testFile = Join-Path $sourceDir "test.ps1"
            New-TestFile -Path $testFile -Content "Write-Host 'Test'"
            
            Initialize-FileInfo -path $testFile -isDirectory $false
            
            $fileCollection[0].Category | Should -Be "Development"
            $fileCollection[0].SubCategory | Should -Be "Standalone"
        }
        
        It "Identifies development projects" {
            $projectDir = Join-Path $sourceDir "TestProject"
            New-Item -ItemType Directory -Path $projectDir -Force
            New-TestFile -Path (Join-Path $projectDir ".gitignore")
            
            Initialize-FileInfo -path $projectDir -isDirectory $true
            
            $fileCollection[0].Category | Should -Be "Development"
            $fileCollection[0].SubCategory | Should -Be "Project"
        }
    }
    
    Context "Media File Detection" {
        It "Identifies image files correctly" {
            $testFile = Join-Path $sourceDir "test.jpg"
            New-TestFile -Path $testFile
            
            Initialize-FileInfo -path $testFile -isDirectory $false
            
            $fileCollection[0].Category | Should -Be "Media"
            $fileCollection[0].SubCategory | Should -Be "Pictures"  # Changed from Images
        }
        
        It "Identifies video files correctly" {
            $testFile = Join-Path $sourceDir "test.mp4"
            New-TestFile -Path $testFile
            
            Initialize-FileInfo -path $testFile -isDirectory $false
            
            $fileCollection[0].Category | Should -Be "Media"
            $fileCollection[0].SubCategory | Should -Be "Videos"
        }
    }
    
    Context "Document Classification" {
        It "Classifies documents with metadata correctly" {
            $testFile = Join-Path $sourceDir "test.docx"
            $metadata = @{
                Author = "Michael"
                Title = "My Resume"
                Category = "Work"
            }
            New-TestFile -Path $testFile -Metadata $metadata
            
            Initialize-FileInfo -path $testFile -isDirectory $false
            
            $fileCollection[0].Category | Should -Be "Documents"
            $fileCollection[0].DetectedFamilyMembers.Count | Should -BeGreaterThan 0
            $fileCollection[0].DetectedCategories.Count | Should -BeGreaterThan 0
        }
    }
    
    Context "File Movement" {
        It "Moves files to correct locations" {
            # Create test files
            $psFile = Join-Path $sourceDir "test.ps1"
            $imageFile = Join-Path $sourceDir "test.jpg"
            $docFile = Join-Path $sourceDir "test.docx"
            $unknownFile = Join-Path $sourceDir "test.xyz"
            
            New-TestFile -Path $psFile -Content "Write-Host 'Test'"
            New-TestFile -Path $imageFile
            New-TestFile -Path $docFile -Metadata @{
                Author = "Michael"
                Title = "Test Document"
            }
            New-TestFile -Path $unknownFile
            
            # Mock Move-ItemSafe to track moves
            Mock Move-ItemSafe -MockWith { }
            
            # Process files
            Get-ChildItem -Path $sourceDir | ForEach-Object {
                Initialize-FileInfo -path $_.FullName -isDirectory $false
            }
            
            # Verify expected paths
            $script:fileCollection[0].TargetPath | Should -Match "Documents\\Personal\\Development\\Standalone\\PowerShell"
            $script:fileCollection[1].TargetPath | Should -Match "Media\\Pictures"  # Changed from Images
            $script:fileCollection[2].TargetPath | Should -Match "Documents\\Personal\\02 - Michael"
            $script:fileCollection[3].TargetPath | Should -Match "Documents\\Personal\\Unknown"
            
            # Verify moves were called
            Should -Invoke Move-ItemSafe -Times 4
        }
    }
    
    Context "Family Member Detection" {
        It "Detects family members from metadata" {
            $fileInfo = [FileOrganizationInfo]::new("test.docx", $false)
            $content = "Michael"
            
            Get-AllPossibleFamilyMembers -fileInfo $fileInfo -content $content
            
            $fileInfo.DetectedFamilyMembers | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Category Detection" {
        It "Detects categories from metadata" {
            $fileInfo = [FileOrganizationInfo]::new("test.docx", $false)
            $content = "Soccer"
            
            Get-AllPossibleCategories -fileInfo $fileInfo -content $content
            
            $fileInfo.DetectedCategories | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "File Organization Info Class" {
        It "Creates FileOrganizationInfo object correctly" {
            $fileInfo = [FileOrganizationInfo]::new("test.txt", $false)
            
            $fileInfo.SourcePath | Should -Be "test.txt"
            $fileInfo.IsDirectory | Should -Be $false
            $fileInfo.FileType | Should -Be ".txt"
            $fileInfo.ColorCode | Should -Be "White"
            $fileInfo.ProcessedAsProject | Should -Be $false
        }
        
        It "Adds family member detection correctly" {
            $fileInfo = [FileOrganizationInfo]::new("test.txt", $false)
            $fileInfo.AddFamilyMemberDetection("Michael", "Filename", "Michael*")
            
            $fileInfo.DetectedFamilyMembers["Michael"].Value | Should -Be "Michael"
            $fileInfo.DetectedFamilyMembers["Michael"].Sources | Should -Contain "Filename"
            $fileInfo.DetectedFamilyMembers["Michael"].MatchedPatterns | Should -Contain "Michael*"
        }
    }
    
    Context "Duplicate File Handling" {
        BeforeEach {
            # Clear test directories
            Get-ChildItem -Path $sourceDir -Recurse | Remove-Item -Force -Recurse
            Get-ChildItem -Path $targetDir -Recurse | Remove-Item -Force -Recurse
        }
        
        It "Moves duplicate files to root Duplicates folder" {
            # Create original file
            $originalContent = "Test Content"
            $sourceFile1 = Join-Path $sourceDir "original.jpg"
            $sourceFile2 = Join-Path $sourceDir "duplicate.jpg"
            Set-Content -Path $sourceFile1 -Value $originalContent
            Set-Content -Path $sourceFile2 -Value $originalContent
            
            $targetFile = Join-Path $targetDir "Media\Images\test.jpg"
            
            # Move first file
            Move-ItemSafe -Path $sourceFile1 -Destination $targetFile
            
            # Move duplicate file
            Move-ItemSafe -Path $sourceFile2 -Destination $targetFile
            
            # Check if duplicate was moved to root Duplicates folder
            $duplicatesDir = Join-Path $targetDir "Duplicates"
            $duplicateFiles = Get-ChildItem -Path $duplicatesDir -File
            
            $duplicateFiles.Count | Should -Be 1
            $duplicateFiles[0].Extension | Should -Be ".jpg"
            
            # Verify content matches
            $originalHash = Get-FileHash -Path $targetFile
            $duplicateHash = Get-FileHash -Path $duplicateFiles[0].FullName
            $originalHash.Hash | Should -Be $duplicateHash.Hash
        }
        
        It "Moves duplicate files to Duplicates folder" {
            # Create original file
            $originalContent = "Test Content"
            $sourceFile1 = Join-Path $sourceDir "original.txt"
            $sourceFile2 = Join-Path $sourceDir "duplicate.txt"
            Set-Content -Path $sourceFile1 -Value $originalContent
            Set-Content -Path $sourceFile2 -Value $originalContent
            
            $targetFile = Join-Path $targetDir "test.txt"
            
            # Move first file
            Move-ItemSafe -Path $sourceFile1 -Destination $targetFile
            
            # Move duplicate file
            Move-ItemSafe -Path $sourceFile2 -Destination $targetFile
            
            # Check if duplicate was moved to Duplicates folder
            $duplicatesDir = Join-Path $targetDir "Documents\Duplicates"
            $duplicateFiles = Get-ChildItem -Path $duplicatesDir -File
            
            $duplicateFiles.Count | Should -Be 1
            $duplicateFiles[0].Extension | Should -Be ".txt"
            
            # Verify content matches
            $originalHash = Get-FileHash -Path $targetFile
            $duplicateHash = Get-FileHash -Path $duplicateFiles[0].FullName
            $originalHash.Hash | Should -Be $duplicateHash.Hash
        }
        
        It "Handles multiple duplicates with unique names" {
            # Create multiple identical files
            $content = "Test Content"
            1..3 | ForEach-Object {
                $sourceFile = Join-Path $sourceDir "file$_.txt"
                Set-Content -Path $sourceFile -Value $content
            }
            
            $targetFile = Join-Path $targetDir "test.txt"
            
            # Move all files
            Get-ChildItem -Path $sourceDir | ForEach-Object {
                Move-ItemSafe -Path $_.FullName -Destination $targetFile
            }
            
            # Check duplicates folder
            $duplicatesDir = Join-Path $targetDir "Documents\Duplicates"
            $duplicateFiles = Get-ChildItem -Path $duplicatesDir -File
            
            $duplicateFiles.Count | Should -Be 2
            $duplicateFiles | ForEach-Object {
                $hash = Get-FileHash -Path $_.FullName
                $hash.Hash | Should -Be (Get-FileHash -Path $targetFile).Hash
            }
        }
        
        It "Skips moving identical files with same path" {
            # Create a file
            $content = "Test Content"
            $sourceFile = Join-Path $sourceDir "test.txt"
            Set-Content -Path $sourceFile -Value $content
            
            # Try to move to same location
            Move-ItemSafe -Path $sourceFile -Destination $sourceFile
            
            # Verify file still exists in original location
            Test-Path $sourceFile | Should -Be $true
            
            # Verify no duplicates folder was created
            $duplicatesDir = Join-Path $targetDir "Documents\Duplicates"
            Test-Path $duplicatesDir | Should -Be $false
        }
        
        It "Moves duplicate files to root Duplicates folder" {
            # Create source directories
            $imageDir = Join-Path $sourceDir "Images"
            New-Item -ItemType Directory -Path $imageDir -Force
            
            # Create original file
            $originalContent = "Test Content"
            $sourceFile1 = Join-Path $imageDir "original.jpg"
            $sourceFile2 = Join-Path $imageDir "duplicate.jpg"
            Set-Content -Path $sourceFile1 -Value $originalContent
            Set-Content -Path $sourceFile2 -Value $originalContent
            
            $targetFile = Join-Path $targetDir "Media\Images\test.jpg"
            
            # Move first file
            Move-ItemSafe -Path $sourceFile1 -Destination $targetFile
            
            # Move duplicate file
            Move-ItemSafe -Path $sourceFile2 -Destination $targetFile
            
            # Check if duplicate was moved to root Duplicates folder
            $duplicatesDir = Join-Path $targetDir "Duplicates\Images"
            $duplicateFiles = Get-ChildItem -Path $duplicatesDir -File
            
            $duplicateFiles.Count | Should -Be 1
            $duplicateFiles[0].Extension | Should -Be ".jpg"
            
            # Verify content matches
            $originalHash = Get-FileHash -Path $targetFile
            $duplicateHash = Get-FileHash -Path $duplicateFiles[0].FullName
            $originalHash.Hash | Should -Be $duplicateHash.Hash
        }
    }
    
    Context "Multi-tier Category Detection" {
        It "Identifies finance bills correctly" {
            $testFile = Join-Path $sourceDir "electricity_bill.pdf"
            $metadata = @{
                Title = "Electric Bill"
                Subject = "Monthly Utility Bill"
            }
            New-TestFile -Path $testFile -Metadata $metadata
            
            Initialize-FileInfo -path $testFile -isDirectory $false
            
            $fileCollection[0].Category | Should -Be "Documents"
            $fileCollection[0].SubCategory | Should -Be "Finances"
            $fileCollection[0].TertiaryCategory | Should -Be "Bills"
            $fileCollection[0].TargetPath | Should -Match "Documents\\Personal\\01 - Family\\Finances\\Bills"
        }
        
        It "Identifies tax documents correctly" {
            $testFile = Join-Path $sourceDir "tax_return_2023.pdf"
            $metadata = @{
                Title = "Tax Return 2023"
                Subject = "Annual Tax Filing"
            }
            New-TestFile -Path $testFile -Metadata $metadata
            
            Initialize-FileInfo -path $testFile -isDirectory $false
            
            $fileCollection[0].Category | Should -Be "Documents"
            $fileCollection[0].SubCategory | Should -Be "Finances"
            $fileCollection[0].TertiaryCategory | Should -Be "Taxes"
            $fileCollection[0].TargetPath | Should -Match "Documents\\Personal\\01 - Family\\Finances\\Taxes"
        }
        
        It "Uses parent category when subcategory is not detected" {
            $testFile = Join-Path $sourceDir "financial_summary.pdf"
            $metadata = @{
                Title = "Financial Summary"
                Subject = "General Financial Overview"
            }
            New-TestFile -Path $testFile -Metadata $metadata
            
            Initialize-FileInfo -path $testFile -isDirectory $false
            
            $fileCollection[0].Category | Should -Be "Documents"
            $fileCollection[0].SubCategory | Should -Be "Finances"
            $fileCollection[0].TertiaryCategory | Should -BeNullOrEmpty
            $fileCollection[0].TargetPath | Should -Match "Documents\\Personal\\01 - Family\\Finances"
        }
    }
}

Describe "Utility Function Tests" {
    Context "Convert-WildcardToRegex" {
        It "Converts wildcards correctly" {
            Convert-WildcardToRegex -pattern "test*" | Should -Be "test[\s\w-]+"
            Convert-WildcardToRegex -pattern "*test*" | Should -Be "[\s\w-]+test[\s\w-]+"
        }
    }

    Context "Test-ContentMatch" {
        It "Matches content correctly" {
            $result = Test-ContentMatch -content "test123" -includePatterns @("test*") -excludePatterns @()
            $result | Should -Be $true
        }
        
        It "Excludes content correctly" {
            $result = Test-ContentMatch -content "test123" -includePatterns @("test*") -excludePatterns @("*123")
            $result | Should -Be $false
        }
    }
}
