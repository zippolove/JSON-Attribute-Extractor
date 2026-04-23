# JSON Field Extractor (PowerShell GUI)

A lightweight PowerShell WinForms tool for extracting, sorting, and formatting data from JSON.  
Paste JSON, pick the fields you want, and instantly generate clean output—no scripting required.

## Features

- Paste JSON directly or load from file
- Automatically detects arrays of objects (no manual pathing needed)
- Dynamically discovers available attributes
- Select one or multiple fields for output
- Sort results (ascending / descending)
- Optional:
  - Remove duplicates
  - Convert output to uppercase
- Flexible formatting:
  - Field delimiter (between selected attributes)
  - Row delimiter (between output rows)
- Copy output to clipboard or save to file

## Example Use Case

### Input JSON

```json
{
  "results": [
    { "name": "Device-A", "status": true },
    { "name": "Device-B", "status": false },
    { "name": "Device-C", "status": true }
  ]
}
```

### Selected Fields

- `name`
- `status`

### Output (Pipe + New Line)

```text
Device-A | True
Device-B | False
Device-C | True
```

## Getting Started

### Requirements

- Windows
- PowerShell 5.1 or newer

### Run the Script

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\JsonFieldExtractor.ps1
```

Or from an existing PowerShell session:

```powershell
.\JsonFieldExtractor.ps1
```

## How It Works

1. Paste JSON into the input box (or click **Load File**)
2. Click **Parse JSON**
3. Select the array (if multiple are detected)
4. Choose one or more attributes
5. Configure:
   - Sort order
   - Field delimiter
   - Row delimiter
6. Click **Generate Output**
7. Copy or save the results

## Tips

### Clean Output Formatting

For most use cases:

- **1 field selected**
  - Row delimiter: New line
- **Multiple fields selected**
  - Field delimiter: Pipe or Semicolon
  - Row delimiter: New line

Example:

```text
Device-A | True
Device-B | False
```

### Single-Line Output

If you want everything on one line:

- Row delimiter: Pipe or Comma

```text
Device-A | True | Device-B | False | Device-C | True
```

### Handling Imperfect JSON

The tool attempts to be forgiving:

- Supports full JSON documents
- Supports standalone arrays
- Attempts to extract valid JSON from pasted content

If parsing fails:

- Ensure the JSON is complete (not cut off)
- Try pasting only the array portion
- Use **Load File** for best reliability

## Limitations

- Designed for flat JSON objects (no deep nested path selection yet)
- Sorting is string-based (not natural numeric sorting)
- Very large JSON files may impact performance

## Future Improvements (Ideas)

- Nested property selection (e.g. `parent.child.value`)
- Filtering (e.g. only show items where `status = true`)
- CSV export with headers
- Natural sorting
- Preset output modes (table, CSV, list)

## License

MIT (or whatever you choose)

## Contributing

PRs welcome. Keep it simple and practical.
