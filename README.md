# Personal File Organization System

A PowerShell-based file organization system that intelligently sorts and categorizes files based on content, metadata, and type.

## Overview

This system helps organize personal and family files into a structured directory system, with special handling for development projects, media files, and duplicate detection.

## Prerequisites

- PowerShell 5.1 or higher
- Windows OS
- Write permissions on target directories

## Installation

1. Clone the repository
2. Configure your settings in [src/config/file-organization-config.json](src/config/file-organization-config.json)
3. Run the scripts from PowerShell

## Usage

```powershell
# Organize files
.\src\scripts\Organize-Files.ps1 -SourceDirectory "path\to\source" -TargetDirectory "path\to\target"

# Revert organization
.\src\scripts\Revert-FileOrganization.ps1 -SourceDirectory "path\to\source" -TargetDirectory "path\to\target"
```

## Directory Structure

```
TargetDirectory/
├── Documents/
│   └── Personal/
│       ├── 01 - Family/
│       ├── 02 - Michael/
│       ├── 03 - Jenna/
│       ├── Development/
│       └── Unknown/
├── Media/
│   ├── Pictures/
│   └── Videos/
└── Duplicates/
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

## Configuration

Configure the system using (`file-organization-config.json`) with:
- File extension mappings
- Category patterns
- Family member detection rules
- Custom classification rules
- Wildcard pattern support for flexible matching

## Testing

Run the Pester tests using:

```powershell
Invoke-Pester .\src\tests\Organize-Files.Tests.ps1
```

## Technical Stack

- **Language**: PowerShell
- **Configuration**: JSON
- **Testing**: Pester
- **Pattern Matching**: Regular Expressions with wildcard support
- **Duplicate Detection**: Hash-based comparison

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

GPL License - See LICENSE file for details

## Future Enhancements

2. Additional file type support
4. Cloud storage integration
5. Scheduled organization tasks
