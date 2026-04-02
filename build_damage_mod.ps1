# =============================================================
# SOF2 Realistic Damage Mod Builder
# Edit the $Damage table below, then run this script.
# Output: WeaponMod\zz_realistic_damage.pk3
# =============================================================
# How to run: right-click > "Run with PowerShell"
#   or from terminal: .\build_damage_mod.ps1
# =============================================================

$SourceWpn = "$PSScriptRoot\base\sof2_weapons.wpn"
$OutputPk3 = "$PSScriptRoot\WeaponMod\zz_realistic_damage.pk3"
$TempWpn   = "$env:TEMP\sof2_modified.wpn"

# -----------------------------------------------------------
# DAMAGE VALUES - edit these, then re-run to rebuild the pk3
# SP  = singleplayer damage per bullet / per pellet
# MP  = multiplayer damage per bullet / per pellet
# Shotguns fire 9 pellets per shot (USAS-12 / M590)
# Knife throw (alt-fire) stays at 100 - altattacks not touched
# -----------------------------------------------------------
$Damage = @{
    # Weapon Name          SP     MP
    "Knife"          = @{ SP=75;  MP=75  }   # slash  (throw alt stays 100)
    "US SOCOM"       = @{ SP=65;  MP=55  }   # 9mm silenced
    "MK23"           = @{ SP=65;  MP=55  }   # .45 ACP
    "M1911A1"        = @{ SP=65;  MP=55  }   # .45 ACP
    "M1911A1SD"      = @{ SP=60;  MP=50  }   # .45 ACP silenced
    "M1991A1"        = @{ SP=60;  MP=50  }   # 9mm
    "M1991A1SD"      = @{ SP=55;  MP=50  }   # 9mm silenced
    "SILVER_TALON"   = @{ SP=70;  MP=60  }   # .357 mag
    "USAS-12"        = @{ SP=30;  MP=22  }   # pellet x9 = 270 SP total
    "M590"           = @{ SP=30;  MP=25  }   # pellet x9 = 270 SP total
    "Micro Uzi"      = @{ SP=60;  MP=50  }   # 9mm
    "Micro Uzi SD"   = @{ SP=55;  MP=50  }   # 9mm silenced
    "M3A1"           = @{ SP=65;  MP=55  }   # .45 ACP SMG
    "MP5"            = @{ SP=60;  MP=50  }   # 9mm
    "MP5A3"          = @{ SP=60;  MP=50  }   # 9mm
    "MP5SD"          = @{ SP=55;  MP=50  }   # 9mm silenced
    "M4"             = @{ SP=65;  MP=50  }   # 5.56mm
    "M5"             = @{ SP=65;  MP=50  }   # 5.56mm
    "M6"             = @{ SP=60;  MP=50  }   # 5.56mm short barrel
    "M4A1"           = @{ SP=65;  MP=50  }   # 5.56mm + M406 grenade
    "AK74"           = @{ SP=65;  MP=55  }   # 5.45mm
    "AK47"           = @{ SP=75;  MP=60  }   # 7.62x39mm
    "AKM"            = @{ SP=75;  MP=60  }   # 7.62x39mm
    "AKMSD"          = @{ SP=70;  MP=55  }   # 7.62x39mm silenced
    "TYPE56"         = @{ SP=70;  MP=60  }   # 7.62x39mm
    "OICW"           = @{ SP=65;  MP=70  }   # 5.56mm + 20mm grenade
    "SIG552"         = @{ SP=65;  MP=50  }   # 5.56mm
    "SIG553"         = @{ SP=65;  MP=50  }   # 5.56mm
    "SIG551"         = @{ SP=65;  MP=50  }   # 5.56mm
    "MSG90A1"        = @{ SP=100; MP=120 }   # 7.62x51mm sniper - 1-shot kill
    "M60"            = @{ SP=75;  MP=60  }   # 7.62x51mm LMG
    "Emplaced M60"   = @{ SP=75;  MP=65  }
    "Emplaced RPD"   = @{ SP=70;  MP=65  }
    "RPD"            = @{ SP=70;  MP=65  }
}

# Change all mp_gore "no" to "yes" so gore applies in every attack mode
$EnableAllGore = $true

# =============================================================
# Processing - no need to edit below this line
# =============================================================

if (-not (Test-Path $SourceWpn)) {
    Write-Error "Source not found: $SourceWpn"
    exit 1
}

$lines  = Get-Content $SourceWpn -Encoding UTF8
$output = [System.Collections.Generic.List[string]]::new()

$currentWeapon = $null
$depth         = 0
$pendingBlock  = $null   # "attack"/"altattack" waiting for its opening {
$blockType     = $null   # current sub-block type
$blockDepth    = -1      # brace depth where current sub-block opened
$dmgSet        = $false  # SP damage already replaced in this block
$mpDmgSet      = $false  # MP damage already replaced in this block

$changed = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
    $trimmed = $line.Trim()

    # Weapon name - only at depth 1 (inside weapon { } block, not preamble sections)
    if ($depth -eq 1 -and $trimmed -match '^name\s+"(.+)"') {
        $currentWeapon = $matches[1]
        $dmgSet        = $false
        $mpDmgSet      = $false
    }

    # Opening brace
    if ($trimmed -eq '{') {
        $depth++
        if ($pendingBlock) {
            $blockType    = $pendingBlock
            $blockDepth   = $depth
            $pendingBlock = $null
            $dmgSet       = $false
            $mpDmgSet     = $false
        }
    }

    # Closing brace
    if ($trimmed -eq '}') {
        if ($depth -eq $blockDepth) {
            $blockType  = $null
            $blockDepth = -1
        }
        $depth--
        if ($depth -eq 0) { $currentWeapon = $null }
    }

    # Detect attack / altattack keywords (at depth 1 = directly inside a weapon block)
    if ($depth -eq 1 -and $trimmed -in @('attack', 'altattack')) {
        $pendingBlock = $trimmed
    }

    # Modify values - only inside the primary "attack" block of a known weapon
    if ($blockType -eq 'attack' -and $currentWeapon -and $Damage.ContainsKey($currentWeapon)) {

        # SP damage
        if (-not $dmgSet -and $trimmed -match '^damage\s+') {
            $sp  = $Damage[$currentWeapon].SP
            $rep = '${1}' + "`"$sp`""
            $line   = $line -replace '(\bdamage\s+)"?\d+"?', $rep
            $dmgSet = $true
            if (-not $changed.Contains($currentWeapon)) { $changed.Add($currentWeapon) }
        }

        # MP damage
        if (-not $mpDmgSet -and $trimmed -match '^mp_damage\s+') {
            $mp  = $Damage[$currentWeapon].MP
            $rep = '${1}' + $mp
            $line     = $line -replace '(mp_damage\s+)"?\d+"?', $rep
            $mpDmgSet = $true
        }
    }

    # Enable gore on all attack modes
    if ($EnableAllGore -and $line -match 'mp_gore') {
        $line = $line -replace '(?i)(mp_gore\s+)"?no"?', '${1}yes'
    }

    $output.Add($line)
}

# Write modified wpn to temp
$output | Set-Content $TempWpn -Encoding UTF8

# Pack into pk3 (zip with internal path ext_data/SOF2.wpn using forward slashes)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Remove-Item $OutputPk3 -ErrorAction SilentlyContinue
$zip = [System.IO.Compression.ZipFile]::Open($OutputPk3, [System.IO.Compression.ZipArchiveMode]::Create)
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $zip, $TempWpn, 'ext_data/SOF2.wpn',
    [System.IO.Compression.CompressionLevel]::Optimal
) | Out-Null
$zip.Dispose()
Remove-Item $TempWpn

Write-Host ""
Write-Host "Built: $OutputPk3"
Write-Host "Modified $($changed.Count) weapons: $($changed -join ', ')"
Write-Host ""
Write-Host "Launch the game - WeaponMod loads it automatically (zz_ prefix = highest priority)."
