BeforeAll {
    # Import the script
    . $PSScriptRoot/../scripts/Organize-Files.ps1
    
    # Create test directories
    $script:testRoot = Join-Path $TestDrive "TestFileOrganization"
    $script:sourceDir = Join-Path $testRoot "Source"
    $script:targetDir = Join-Path $testRoot "Target"
    
    # Create test directories
    New-Item -ItemType Directory -Path $sourceDir -Force
    New-Item -ItemType Directory -Path $targetDir -Force
    
    # Helper function to create test files
    function New-TestFile {
        param(
            [string]$Path,
            [string]$Content = "",
            [hashtable]$Metadata = @{}
        )
        
        Set-Content -Path $Path -Value $Content
        
        # Mock metadata for the file
        Mock Get-FileMetadata -ParameterFilter { $path -eq $Path } -MockWith { $Metadata }
    }
}

Describe "File Organization Tests" {
    BeforeEach {
        # Clear test directories before each test
        Get-ChildItem -Path $sourceDir -Recurse | Remove-Item -Force -Recurse
        Get-ChildItem -Path $targetDir -Recurse | Remove-Item -Force -Recurse
        
        # Reset file collection
        $script:fileCollection = @()
        
        # Reset counters
        $script:fileCount = @{
            Development = @{ Projects = 0; Standalone = 0 }
            Media = @{ Images = 0; Videos = 0 }
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
            $fileCollection[0].SubCategory | Should -Be "Images"
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
                Author = "Michael Smith"
                Title = "Work Report"
                Category = "Reports"
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
            
            New-TestFile -Path $psFile -Content "Write-Host 'Test'"
            New-TestFile -Path $imageFile
            New-TestFile -Path $docFile -Metadata @{
                Author = "Michael Smith"
                Title = "Test Document"
            }
            
            # Mock Move-ItemSafe to track moves
            Mock Move-ItemSafe -MockWith { }
            
            # Process files
            Get-ChildItem -Path $sourceDir | ForEach-Object {
                Initialize-FileInfo -path $_.FullName -isDirectory $false
            }
            
            # Verify expected moves
            Should -Invoke Move-ItemSafe -Times 3
        }
    }
    
    Context "Family Member Detection" {
        It "Detects family members from metadata" {
            $fileInfo = [FileOrganizationInfo]::new("test.docx", $false)
            $content = "Test content"
            
            Get-AllPossibleFamilyMembers -fileInfo $fileInfo -content $content
            
            $fileInfo.DetectedFamilyMembers | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Category Detection" {
        It "Detects categories from metadata" {
            $fileInfo = [FileOrganizationInfo]::new("test.docx", $false)
            $content = "Test content"
            
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
