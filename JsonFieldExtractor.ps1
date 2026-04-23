Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

function Try-ParseJson {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    try {
        return [PSCustomObject]@{
            Success = $true
            Object  = ($Text | ConvertFrom-Json -ErrorAction Stop)
            Error   = $null
            Mode    = 'Direct'
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Object  = $null
            Error   = $_.Exception.Message
            Mode    = 'Direct'
        }
    }
}

function Get-BalancedJsonSubstring {
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [char]$OpenChar,

        [Parameter(Mandatory)]
        [char]$CloseChar
    )

    $start = $Text.IndexOf($OpenChar)
    if ($start -lt 0) { return $null }

    $depth = 0
    $inString = $false
    $escape = $false

    for ($i = $start; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]

        if ($escape) {
            $escape = $false
            continue
        }

        if ($ch -eq '\') {
            if ($inString) {
                $escape = $true
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = -not $inString
            continue
        }

        if (-not $inString) {
            if ($ch -eq $OpenChar) { $depth++ }
            elseif ($ch -eq $CloseChar) { $depth-- }

            if ($depth -eq 0) {
                return $Text.Substring($start, ($i - $start + 1))
            }
        }
    }

    return $null
}

function Convert-PastedTextToJsonObject {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $trimmed = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Input JSON is empty."
    }

    # 1) Try exactly as pasted
    $direct = Try-ParseJson -Text $trimmed
    if ($direct.Success) {
        return [PSCustomObject]@{
            Object = $direct.Object
            Mode   = 'Parsed input directly'
        }
    }

    # 2) Try first balanced object
    $objectChunk = Get-BalancedJsonSubstring -Text $trimmed -OpenChar '{' -CloseChar '}'
    if ($objectChunk) {
        $objTry = Try-ParseJson -Text $objectChunk
        if ($objTry.Success) {
            return [PSCustomObject]@{
                Object = $objTry.Object
                Mode   = 'Extracted first JSON object from pasted text'
            }
        }
    }

    # 3) Try first balanced array
    $arrayChunk = Get-BalancedJsonSubstring -Text $trimmed -OpenChar '[' -CloseChar ']'
    if ($arrayChunk) {
        $arrTry = Try-ParseJson -Text $arrayChunk
        if ($arrTry.Success) {
            return [PSCustomObject]@{
                Object = $arrTry.Object
                Mode   = 'Extracted first JSON array from pasted text'
            }
        }
    }

    # 4) Try wrapping pasted object fragments as an array
    # Useful when user pasted just the contents of results without the surrounding [ ]
    if ($trimmed -match '"[A-Za-z0-9_]+"?\s*:') {
        $wrappedArray = "[`r`n$trimmed`r`n]"
        $fragTry = Try-ParseJson -Text $wrappedArray
        if ($fragTry.Success) {
            return [PSCustomObject]@{
                Object = $fragTry.Object
                Mode   = 'Wrapped pasted object fragments as an array'
            }
        }
    }

    throw "Unable to parse pasted content as valid JSON. Make sure you copied the full object/array, or paste just the contents of the array cleanly."
}

function Get-JsonArrays {
    param(
        [Parameter(Mandatory)]
        $JsonObject
    )

    $results = @()

    if ($null -eq $JsonObject) {
        return @()
    }

    if ($JsonObject -is [System.Collections.IEnumerable] -and -not ($JsonObject -is [string])) {
        $rootItems = @($JsonObject)
        if ($rootItems.Count -gt 0 -and $null -ne $rootItems[0] -and $rootItems[0].PSObject -and $rootItems[0].PSObject.Properties.Count -gt 0) {
            $results += [PSCustomObject]@{
                Name  = '<root>'
                Items = $rootItems
            }
        }
    }

    if ($JsonObject.PSObject -and $JsonObject.PSObject.Properties) {
        foreach ($prop in $JsonObject.PSObject.Properties) {
            $value = $prop.Value

            if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                $items = @($value)
                if ($items.Count -gt 0 -and $null -ne $items[0] -and $items[0].PSObject -and $items[0].PSObject.Properties.Count -gt 0) {
                    $results += [PSCustomObject]@{
                        Name  = $prop.Name
                        Items = $items
                    }
                }
            }
        }
    }

    $results = @(
        $results | Sort-Object @{ Expression = { if ($_.Name -eq 'results') { 0 } else { 1 } } }, Name
    )

    return $results
}

function Get-PropertyNamesFromItems {
    param(
        [Parameter(Mandatory)]
        [array]$Items
    )

    $props = foreach ($item in $Items) {
        if ($null -ne $item -and $item.PSObject -and $item.PSObject.Properties) {
            foreach ($prop in $item.PSObject.Properties) {
                $prop.Name
            }
        }
    }

    return @($props | Sort-Object -Unique)
}

function Get-SelectedCheckedItems {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.CheckedListBox]$CheckedListBox
    )

    $selected = @()
    foreach ($checkedItem in $CheckedListBox.CheckedItems) {
        $selected += [string]$checkedItem
    }

    return @($selected)
}

function Get-FieldDelimiterValue {
    param([string]$Name)

    switch ($Name) {
        'Comma'     { ', ' }
        'Tab'       { "`t" }
        'Pipe'      { ' | ' }
        'Semicolon' { '; ' }
        default     { ' | ' }
    }
}

function Get-RowDelimiterValue {
    param([string]$Name)

    switch ($Name) {
        'Blank line' { "`r`n`r`n" }
        'Comma'      { ', ' }
        'Tab'        { "`t" }
        'Pipe'       { ' | ' }
        default      { "`r`n" }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'JSON Field Extractor'
$form.Size = New-Object System.Drawing.Size(1180, 820)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(1180, 820)

$font = New-Object System.Drawing.Font('Segoe UI', 9)
$mono = New-Object System.Drawing.Font('Consolas', 9)

$lblInput = New-Object System.Windows.Forms.Label
$lblInput.Location = New-Object System.Drawing.Point(12, 10)
$lblInput.Size = New-Object System.Drawing.Size(250, 20)
$lblInput.Text = 'Input JSON'
$lblInput.Font = $font
$form.Controls.Add($lblInput)

$txtInput = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(12, 32)
$txtInput.Size = New-Object System.Drawing.Size(800, 310)
$txtInput.Multiline = $true
$txtInput.ScrollBars = 'Both'
$txtInput.WordWrap = $false
$txtInput.Font = $mono
$txtInput.AcceptsReturn = $true
$txtInput.AcceptsTab = $true
$txtInput.Anchor = 'Top,Left,Right'
$form.Controls.Add($txtInput)

$rightX = 830
$rightW = 320

$btnParse = New-Object System.Windows.Forms.Button
$btnParse.Location = New-Object System.Drawing.Point($rightX, 32)
$btnParse.Size = New-Object System.Drawing.Size(150, 32)
$btnParse.Text = 'Parse JSON'
$btnParse.Font = $font
$btnParse.Anchor = 'Top,Right'
$form.Controls.Add($btnParse)

$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Location = New-Object System.Drawing.Point(($rightX + 160), 32)
$btnLoad.Size = New-Object System.Drawing.Size(150, 32)
$btnLoad.Text = 'Load File'
$btnLoad.Font = $font
$btnLoad.Anchor = 'Top,Right'
$form.Controls.Add($btnLoad)

$lblArray = New-Object System.Windows.Forms.Label
$lblArray.Location = New-Object System.Drawing.Point($rightX, 76)
$lblArray.Size = New-Object System.Drawing.Size($rightW, 20)
$lblArray.Text = 'Detected arrays: 0'
$lblArray.Font = $font
$lblArray.Anchor = 'Top,Right'
$form.Controls.Add($lblArray)

$lblArraySelect = New-Object System.Windows.Forms.Label
$lblArraySelect.Location = New-Object System.Drawing.Point($rightX, 104)
$lblArraySelect.Size = New-Object System.Drawing.Size($rightW, 20)
$lblArraySelect.Text = 'Array to use'
$lblArraySelect.Font = $font
$lblArraySelect.Anchor = 'Top,Right'
$form.Controls.Add($lblArraySelect)

$cmbArray = New-Object System.Windows.Forms.ComboBox
$cmbArray.Location = New-Object System.Drawing.Point($rightX, 126)
$cmbArray.Size = New-Object System.Drawing.Size($rightW, 24)
$cmbArray.DropDownStyle = 'DropDownList'
$cmbArray.Font = $font
$cmbArray.Anchor = 'Top,Right'
$form.Controls.Add($cmbArray)

$lblProps = New-Object System.Windows.Forms.Label
$lblProps.Location = New-Object System.Drawing.Point($rightX, 160)
$lblProps.Size = New-Object System.Drawing.Size($rightW, 20)
$lblProps.Text = 'Available attributes'
$lblProps.Font = $font
$lblProps.Anchor = 'Top,Right'
$form.Controls.Add($lblProps)

$clbProps = New-Object System.Windows.Forms.CheckedListBox
$clbProps.Location = New-Object System.Drawing.Point($rightX, 182)
$clbProps.Size = New-Object System.Drawing.Size($rightW, 170)
$clbProps.CheckOnClick = $true
$clbProps.Font = $font
$clbProps.Anchor = 'Top,Right'
$form.Controls.Add($clbProps)

$lblSort = New-Object System.Windows.Forms.Label
$lblSort.Location = New-Object System.Drawing.Point($rightX, 362)
$lblSort.Size = New-Object System.Drawing.Size($rightW, 20)
$lblSort.Text = 'Sort by'
$lblSort.Font = $font
$lblSort.Anchor = 'Top,Right'
$form.Controls.Add($lblSort)

$cmbSort = New-Object System.Windows.Forms.ComboBox
$cmbSort.Location = New-Object System.Drawing.Point($rightX, 384)
$cmbSort.Size = New-Object System.Drawing.Size($rightW, 24)
$cmbSort.DropDownStyle = 'DropDownList'
$cmbSort.Font = $font
$cmbSort.Anchor = 'Top,Right'
$form.Controls.Add($cmbSort)

$rbAsc = New-Object System.Windows.Forms.RadioButton
$rbAsc.Location = New-Object System.Drawing.Point($rightX, 418)
$rbAsc.Size = New-Object System.Drawing.Size(110, 24)
$rbAsc.Text = 'Ascending'
$rbAsc.Checked = $true
$rbAsc.Font = $font
$rbAsc.Anchor = 'Top,Right'
$form.Controls.Add($rbAsc)

$rbDesc = New-Object System.Windows.Forms.RadioButton
$rbDesc.Location = New-Object System.Drawing.Point(($rightX + 120), 418)
$rbDesc.Size = New-Object System.Drawing.Size(110, 24)
$rbDesc.Text = 'Descending'
$rbDesc.Font = $font
$rbDesc.Anchor = 'Top,Right'
$form.Controls.Add($rbDesc)

$chkUnique = New-Object System.Windows.Forms.CheckBox
$chkUnique.Location = New-Object System.Drawing.Point($rightX, 448)
$chkUnique.Size = New-Object System.Drawing.Size(120, 24)
$chkUnique.Text = 'Unique only'
$chkUnique.Font = $font
$chkUnique.Anchor = 'Top,Right'
$form.Controls.Add($chkUnique)

$chkUpper = New-Object System.Windows.Forms.CheckBox
$chkUpper.Location = New-Object System.Drawing.Point(($rightX + 140), 448)
$chkUpper.Size = New-Object System.Drawing.Size(160, 24)
$chkUpper.Text = 'UPPERCASE output'
$chkUpper.Font = $font
$chkUpper.Anchor = 'Top,Right'
$form.Controls.Add($chkUpper)

$lblFieldDelimiter = New-Object System.Windows.Forms.Label
$lblFieldDelimiter.Location = New-Object System.Drawing.Point($rightX, 482)
$lblFieldDelimiter.Size = New-Object System.Drawing.Size($rightW, 20)
$lblFieldDelimiter.Text = 'Field delimiter (between selected attributes)'
$lblFieldDelimiter.Font = $font
$lblFieldDelimiter.Anchor = 'Top,Right'
$form.Controls.Add($lblFieldDelimiter)

$cmbFieldDelimiter = New-Object System.Windows.Forms.ComboBox
$cmbFieldDelimiter.Location = New-Object System.Drawing.Point($rightX, 504)
$cmbFieldDelimiter.Size = New-Object System.Drawing.Size($rightW, 24)
$cmbFieldDelimiter.DropDownStyle = 'DropDownList'
$cmbFieldDelimiter.Font = $font
$cmbFieldDelimiter.Anchor = 'Top,Right'
[void]$cmbFieldDelimiter.Items.Add('Pipe')
[void]$cmbFieldDelimiter.Items.Add('Comma')
[void]$cmbFieldDelimiter.Items.Add('Tab')
[void]$cmbFieldDelimiter.Items.Add('Semicolon')
$cmbFieldDelimiter.SelectedItem = 'Pipe'
$form.Controls.Add($cmbFieldDelimiter)

$lblRowDelimiter = New-Object System.Windows.Forms.Label
$lblRowDelimiter.Location = New-Object System.Drawing.Point($rightX, 536)
$lblRowDelimiter.Size = New-Object System.Drawing.Size($rightW, 20)
$lblRowDelimiter.Text = 'Row delimiter (between output rows)'
$lblRowDelimiter.Font = $font
$lblRowDelimiter.Anchor = 'Top,Right'
$form.Controls.Add($lblRowDelimiter)

$cmbRowDelimiter = New-Object System.Windows.Forms.ComboBox
$cmbRowDelimiter.Location = New-Object System.Drawing.Point($rightX, 558)
$cmbRowDelimiter.Size = New-Object System.Drawing.Size($rightW, 24)
$cmbRowDelimiter.DropDownStyle = 'DropDownList'
$cmbRowDelimiter.Font = $font
$cmbRowDelimiter.Anchor = 'Top,Right'
[void]$cmbRowDelimiter.Items.Add('New line')
[void]$cmbRowDelimiter.Items.Add('Blank line')
[void]$cmbRowDelimiter.Items.Add('Comma')
[void]$cmbRowDelimiter.Items.Add('Tab')
[void]$cmbRowDelimiter.Items.Add('Pipe')
$cmbRowDelimiter.SelectedItem = 'New line'
$form.Controls.Add($cmbRowDelimiter)

$btnGenerate = New-Object System.Windows.Forms.Button
$btnGenerate.Location = New-Object System.Drawing.Point($rightX, 596)
$btnGenerate.Size = New-Object System.Drawing.Size($rightW, 34)
$btnGenerate.Text = 'Generate Output'
$btnGenerate.Font = $font
$btnGenerate.Anchor = 'Top,Right'
$form.Controls.Add($btnGenerate)

$lblOutput = New-Object System.Windows.Forms.Label
$lblOutput.Location = New-Object System.Drawing.Point(12, 352)
$lblOutput.Size = New-Object System.Drawing.Size(250, 20)
$lblOutput.Text = 'Output'
$lblOutput.Font = $font
$form.Controls.Add($lblOutput)

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(12, 374)
$txtOutput.Size = New-Object System.Drawing.Size(800, 370)
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = 'Both'
$txtOutput.WordWrap = $false
$txtOutput.Font = $mono
$txtOutput.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($txtOutput)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Location = New-Object System.Drawing.Point($rightX, 646)
$btnCopy.Size = New-Object System.Drawing.Size(150, 32)
$btnCopy.Text = 'Copy Output'
$btnCopy.Font = $font
$btnCopy.Anchor = 'Top,Right'
$form.Controls.Add($btnCopy)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Location = New-Object System.Drawing.Point(($rightX + 160), 646)
$btnSave.Size = New-Object System.Drawing.Size(150, 32)
$btnSave.Text = 'Save Output'
$btnSave.Font = $font
$btnSave.Anchor = 'Top,Right'
$form.Controls.Add($btnSave)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Location = New-Object System.Drawing.Point($rightX, 686)
$btnClear.Size = New-Object System.Drawing.Size($rightW, 32)
$btnClear.Text = 'Clear'
$btnClear.Font = $font
$btnClear.Anchor = 'Top,Right'
$form.Controls.Add($btnClear)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point($rightX, 728)
$lblStatus.Size = New-Object System.Drawing.Size($rightW, 40)
$lblStatus.Text = 'Ready.'
$lblStatus.Font = $font
$lblStatus.Anchor = 'Top,Right'
$form.Controls.Add($lblStatus)

$script:ParsedJson = $null
$script:DetectedArrays = @()
$script:DetectedItems = @()

function Reset-ParsedState {
    $script:ParsedJson = $null
    $script:DetectedArrays = @()
    $script:DetectedItems = @()
    $cmbArray.Items.Clear()
    $clbProps.Items.Clear()
    $cmbSort.Items.Clear()
    $lblArray.Text = 'Detected arrays: 0'
}

function Populate-FieldsFromSelectedArray {
    $clbProps.Items.Clear()
    $cmbSort.Items.Clear()
    $script:DetectedItems = @()

    if ($cmbArray.SelectedIndex -lt 0 -or $cmbArray.SelectedIndex -ge $script:DetectedArrays.Count) {
        $lblStatus.Text = 'No array selected.'
        return
    }

    $selectedArray = $script:DetectedArrays[$cmbArray.SelectedIndex]
    $script:DetectedItems = @($selectedArray.Items)

    $propertyNames = @(Get-PropertyNamesFromItems -Items $script:DetectedItems)

    foreach ($name in $propertyNames) {
        [void]$clbProps.Items.Add($name)
        [void]$cmbSort.Items.Add($name)
    }

    if ($propertyNames.Count -gt 0) {
        $deviceNameIndex = $clbProps.Items.IndexOf('deviceName')
        if ($deviceNameIndex -ge 0) {
            $clbProps.SetItemChecked($deviceNameIndex, $true)
            $cmbSort.SelectedItem = 'deviceName'
        }
        else {
            $clbProps.SetItemChecked(0, $true)
            $cmbSort.SelectedIndex = 0
        }
    }

    $lblStatus.Text = "Loaded array '$($selectedArray.Name)' with $($script:DetectedItems.Count) item(s) and $($propertyNames.Count) attribute(s)."
}

$cmbArray.Add_SelectedIndexChanged({
    Populate-FieldsFromSelectedArray
})

$btnLoad.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $ofd.Title = 'Select JSON file'

    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $txtInput.Text = Get-Content -Path $ofd.FileName -Raw -ErrorAction Stop
            $lblStatus.Text = "Loaded file: $($ofd.FileName)"
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to load file.`r`n$($_.Exception.Message)",
                'Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }
})

$btnParse.Add_Click({
    try {
        Reset-ParsedState
        $txtOutput.Clear()
        $lblStatus.Text = 'Parsing JSON...'

        $parseResult = Convert-PastedTextToJsonObject -Text $txtInput.Text
        $script:ParsedJson = $parseResult.Object
        $script:DetectedArrays = @(Get-JsonArrays -JsonObject $script:ParsedJson)

        if ($script:DetectedArrays.Count -eq 0) {
            throw "Valid JSON was found, but no array of objects was found to extract fields from."
        }

        foreach ($arr in $script:DetectedArrays) {
            [void]$cmbArray.Items.Add("$($arr.Name) ($(@($arr.Items).Count) items)")
        }

        $lblArray.Text = "Detected arrays: $($script:DetectedArrays.Count)"
        $cmbArray.SelectedIndex = 0
        $lblStatus.Text = "Parsed successfully. $($parseResult.Mode)."
    }
    catch {
        Reset-ParsedState
        $lblStatus.Text = 'Parse failed.'
        [System.Windows.Forms.MessageBox]::Show(
            "JSON parse failed.`r`n$($_.Exception.Message)",
            'Parse Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})

$btnGenerate.Add_Click({
    try {
        if (-not $script:DetectedItems -or $script:DetectedItems.Count -eq 0) {
            throw "No parsed array is loaded. Click Parse JSON first."
        }

        $selectedProps = @(Get-SelectedCheckedItems -CheckedListBox $clbProps)
        if ($selectedProps.Count -eq 0) {
            throw "Select at least one attribute."
        }

        $sortProp = [string]$cmbSort.SelectedItem
        if ([string]::IsNullOrWhiteSpace($sortProp)) {
            $sortProp = $selectedProps[0]
        }

        $fieldDelimiter = Get-FieldDelimiterValue -Name ([string]$cmbFieldDelimiter.SelectedItem)
        $rowDelimiter = Get-RowDelimiterValue -Name ([string]$cmbRowDelimiter.SelectedItem)

        $rows = foreach ($item in $script:DetectedItems) {
            $parts = foreach ($prop in $selectedProps) {
                $value = $item.$prop
                if ($null -eq $value) {
                    ''
                }
                elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    (@($value) -join ', ')
                }
                else {
                    [string]$value
                }
            }

            [PSCustomObject]@{
                SortValue = if ($null -eq $item.$sortProp) { '' } else { [string]$item.$sortProp }
                Line      = ($parts -join $fieldDelimiter)
            }
        }

        if ($rbDesc.Checked) {
            $rows = @($rows | Sort-Object -Property SortValue -Descending)
        }
        else {
            $rows = @($rows | Sort-Object -Property SortValue)
        }

        $lines = @($rows.Line)

        if ($chkUpper.Checked) {
            $lines = @($lines | ForEach-Object { $_.ToUpper() })
        }

        if ($chkUnique.Checked) {
            $lines = @($lines | Sort-Object -Unique)
        }

        $txtOutput.Text = ($lines -join $rowDelimiter)
        $lblStatus.Text = "Generated $($lines.Count) row(s)."
    }
    catch {
        $lblStatus.Text = 'Generate failed.'
        [System.Windows.Forms.MessageBox]::Show(
            "Output generation failed.`r`n$($_.Exception.Message)",
            'Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})

$btnCopy.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($txtOutput.Text)) {
            throw "There is no output to copy."
        }

        [System.Windows.Forms.Clipboard]::SetText($txtOutput.Text)
        $lblStatus.Text = 'Output copied to clipboard.'
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to copy output.`r`n$($_.Exception.Message)",
            'Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})

$btnSave.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($txtOutput.Text)) {
            throw "There is no output to save."
        }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'Text files (*.txt)|*.txt|CSV files (*.csv)|*.csv|All files (*.*)|*.*'
        $sfd.Title = 'Save output'
        $sfd.FileName = 'output.txt'

        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Set-Content -Path $sfd.FileName -Value $txtOutput.Text -Encoding UTF8
            $lblStatus.Text = "Saved output to $($sfd.FileName)"
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to save output.`r`n$($_.Exception.Message)",
            'Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
})

$btnClear.Add_Click({
    $txtInput.Clear()
    $txtOutput.Clear()
    Reset-ParsedState
    $rbAsc.Checked = $true
    $chkUnique.Checked = $false
    $chkUpper.Checked = $false
    $cmbFieldDelimiter.SelectedItem = 'Pipe'
    $cmbRowDelimiter.SelectedItem = 'New line'
    $lblStatus.Text = 'Cleared.'
})

[void]$form.ShowDialog()