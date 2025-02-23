# Personal File Organization System

An intelligent file organization system built in PowerShell that automatically categorizes and organizes files based on content, filename, and file type.

## Features

- **Smart Categorization**: Files are analyzed by both filename and content
- **Family Member Detection**: Detects which family member a document belongs to
- **Category Classification**: Organizes documents into categories like School, Work, Soccer, etc.
- **Development Project Handling**: Preserves project structure for development files
- **Media Organization**: Separates and organizes images and videos
- **Duplicate Prevention**: Uses file hash comparison to prevent duplicate files
- **Configurable Rules**: JSON-based configuration for easy customization
- **Reversion Capability**: Can revert files back to their original location

## Directory Structure

```
Organized/
├── Development/
│   └── [Project folders with structure preserved]
├── Media/
│   ├── Images/
│   └── Videos/
├── Documents/
│   ├── 01 - Family/
│   │   └── [Categories]/
│   ├── 02 - Michael/
│   │   └── [Categories]/
│   └── [Other Family Members]/
│       └── [Categories]/
└── Unknown/
```

## Configuration

The system uses a JSON configuration file (`file-organization-config.json`) that defines:
- File extensions for different types (development, images, videos, documents)
- Categories with include/exclude patterns
- Family members with include/exclude patterns
- Wildcard pattern support for flexible matching

## Scripts

### Organize-Files.ps1
- Main organization script
- Processes files based on configuration
- Maintains folder structures
- Prevents duplicates
- Provides detailed progress and summary

### Revert-FileOrganization.ps1
- Reverts organized files back to source
- Maintains development project structures
- Handles file naming conflicts
- Provides operation summary

## Usage

```powershell
# Organize files
.\Organize-Files.ps1 -SourceDirectory "path\to\source" -TargetDirectory "path\to\target"

# Revert organization
.\Revert-FileOrganization.ps1 -SourceDirectory "path\to\source" -TargetDirectory "path\to\target"
```

## Key Features

1. **Intelligent Content Analysis**
   - Examines both filenames and content
   - Supports pattern matching with wildcards
   - Handles multiple identification criteria

2. **Family-Centric Organization**
   - Organizes by family member first
   - Supports multiple categories per person
   - Default "Family" category for shared documents

3. **Development Project Handling**
   - Preserves complete project structures
   - Maintains source control files
   - Keeps related files together

4. **Media Management**
   - Organizes images and videos separately
   - Supports multiple media formats
   - Maintains original filenames

5. **Safe Operations**
   - Prevents duplicate files
   - Handles naming conflicts
   - Provides detailed logging
   - Includes reversion capability

## Technical Details

- **Language**: PowerShell
- **Configuration**: JSON
- **Pattern Matching**: Regular Expressions with wildcard support
- **File Handling**: Hash-based duplicate detection
- **Progress Tracking**: Real-time progress and summary reporting

## Future Enhancements

1. GUI interface for configuration management
2. Additional file type support
3. Machine learning for improved categorization
4. Cloud storage integration
5. Scheduled organization tasks
