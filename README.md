# Personal File Organization System

A PowerShell-based file organization system that intelligently sorts and categorizes files based on content, metadata, and type.

## Repository Structure

```
TargetDirectory/
├── Documents/
│ └── Personal/
│ ├── 01 - Family/
│ │ └── [Categories]/
│ ├── 02 - Michael/
│ │ └── [Categories]/
│ ├── 03 - Jenna/
│ │ └── [Categories]/
│ ├── Development/
│ │ ├── Projects/
│ │ └── Standalone/
│ └── Unknown/
├── Media/
│ ├── Pictures/
│ └── Videos/
└── Duplicates/
```

## Configuration

Uses a JSON configuration file (`file-organization-config.json`) for:
- File extension mappings
- Category patterns
- Family member detection rules
- Custom classification rules
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

2. Additional file type support
4. Cloud storage integration
5. Scheduled organization tasks
