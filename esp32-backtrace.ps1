# Adapted for Windows PowerShell by mwmuni in 2024
# $XTENSA_GDB = "$env:USERPROFILE\.platformio\packages\toolchain-xtensa32\bin\xtensa-esp32-elf-gdb.exe"
$XTENSA_GDB = "$env:USERPROFILE\.platformio\packages\toolchain-xtensa-esp32s3\bin\xtensa-esp32s3-elf-gdb.exe"

# Validate commandline arguments
if ($args.Count -lt 1) {
    Write-Host "usage: $($MyInvocation.MyCommand.Definition) <elf file> [<backtrace-text>]"
    Write-Host "reads from stdin if no backtrace-text is specified"
    exit 1
}

$elf = $args[0]
if (-not (Test-Path $elf)) {
    Write-Host "ELF file not found ($elf)"
    exit 1
}

if ($args.Count -lt 2) {
    Write-Host "reading backtrace from stdin"
    $btt = "CON"
} elseif (-not (Test-Path $args[1])) {
    Write-Host "Backtrace file not found ($args[1])"
    exit 1
} else {
    $btt = $args[1]
}

# Parse exception info and command backtrace
$rePC = 'PC\s*: (0x[0-9a-f]{8})'
$reEA = 'EXCVADDR\s*: (0x[0-9a-f]{8})'
$reBT = 'Backtrace: (.*)'
$reIN = '^[0-9a-f:x ]+$'
$reOT = '[^0-9a-zA-Z](0x[0-9a-f]{8})[^0-9a-zA-Z]'
$inBT = $false
$REGS = @()
$BT = ""

Get-Content $btt | ForEach-Object {
    $p = $_
    if ($p -match $rePC) {
        $REGS += "PC:$($matches[1])"
    } elseif ($p -match $reEA) {
        $REGS += "EXCVADDR:$($matches[1])"
    } elseif ($p -match $reBT) {
        $BT = $matches[1]
        $inBT = $true
    } elseif ($inBT) {
        if ($p -match $reIN) {
            $BT += $matches[0]
        } else {
            $inBT = $false
        }
    } elseif ($p -match $reOT) {
        $REGS += "OTHER:$($matches[1])"
    }
}

# Parse addresses in backtrace and add them to REGS
$n = 0
$BT -split ' ' | ForEach-Object {
    if ($_ -match '(0x[0-9a-f]{8}):') {
        $addr = $matches[1]
        $REGS += "BT-${n}:$addr"
    }
    $n++
}

# Iterate through all addresses and ask GDB to print source info for each one
foreach ($reg in $REGS) {
    $name, $addr = $reg -split ':'
    $info = & $XTENSA_GDB --batch $elf -ex "set listsize 1" -ex "l *$addr" -ex q 2>&1 | `
        ForEach-Object { $_ -replace ';/[^ ]*/ESP32/;;' } | `
        Where-Object { $_ -notmatch "(No such file or directory)|(^$)" }
    if ($info) { Write-Host "${name}: $info" }
}
