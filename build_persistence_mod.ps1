# =============================================================
# SOF2 Combat Mod Builder (WeaponMod + Persistence merged)
# Realistic damage from WeaponMod + permanent gibs/bodies/decals
# Builds in workspace, then deploys to the actual game directory.
# =============================================================
# How to run: right-click > "Run with PowerShell"
#   or from terminal: .\build_persistence_mod.ps1
# =============================================================

$Root       = $PSScriptRoot
$GameDir    = "C:\Users\Igor\Documents\Soldier of Fortune 2"
$ModDir     = "$GameDir\CombatMod"
$BaseDir    = "$Root\base"
$WeaponDir  = "$Root\WeaponMod"

# Source DLLs (game root - originals)
$SrcCgame = "$GameDir\cgamex86.dll"
$SrcGame  = "$GameDir\gamex86.dll"

# Destination DLLs (mod folder in game dir)
$DstCgame = "$ModDir\cgamex86.dll"
$DstGame  = "$ModDir\gamex86.dll"

# Source PK3 (blood pool effects with near-infinite lifetimes)
$SrcPk3   = "$BaseDir\zzz_persistence.pk3"
$DstPk3   = "$ModDir\zzz_persistence.pk3"

# INT_MAX bytes (little-endian): 0x7FFFFFFF = 2,147,483,647 ms (~24.8 days)
$INTMAX = [byte[]](0xFF, 0xFF, 0xFF, 0x7F)

# =============================================================
# cgamex86.dll PATCHES - Client-side body/gib timer values
# =============================================================
# Each patch: [offset, original_bytes, description]
# All patches replace 4-byte int32 timer values with INT_MAX
$CgamePatches = @(
    # --- Init function at 0x350EE (struct field initialization) ---
    # MOV DWORD [ECX+0x1010], 10000  ->  MOV DWORD [ECX+0x1010], 0x7FFFFFFF
    @{ Offset=0x350FD; Original=[byte[]](0x10,0x27,0x00,0x00); Desc="Init: delay timer 10000 -> MAX" }
    # MOV DWORD [ECX+0x1014], 1000   ->  MOV DWORD [ECX+0x1014], 0x7FFFFFFF
    @{ Offset=0x35107; Original=[byte[]](0xE8,0x03,0x00,0x00); Desc="Init: sink duration 1000 -> MAX" }

    # --- Conditional timer at 0x1844 (entity timer assignment) ---
    # MOV DWORD [EDI+0x48], 10000    ->  MOV DWORD [EDI+0x48], 0x7FFFFFFF
    @{ Offset=0x1847; Original=[byte[]](0x10,0x27,0x00,0x00); Desc="Cond: entity timer 10000 -> MAX" }
    # MOV DWORD [EDI+0x48], 16000    ->  MOV DWORD [EDI+0x48], 0x7FFFFFFF
    @{ Offset=0x1850; Original=[byte[]](0x80,0x3E,0x00,0x00); Desc="Cond: entity timer 16000 -> MAX" }

    # --- Function call arguments at 0x9078E (event scheduling) ---
    # PUSH 10000  ->  PUSH 0x7FFFFFFF
    @{ Offset=0x9078F; Original=[byte[]](0x10,0x27,0x00,0x00); Desc="Call: schedule delay 10000 -> MAX" }
    # PUSH 1000   ->  PUSH 0x7FFFFFFF
    @{ Offset=0x907A1; Original=[byte[]](0xE8,0x03,0x00,0x00); Desc="Call: schedule sink 1000 -> MAX" }
)

# =============================================================
# PROCESSING
# =============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SOF2 Combat Mod Builder" -ForegroundColor Cyan
Write-Host "  WeaponMod + Persistence" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify game directory exists
if (-not (Test-Path "$GameDir\SoF2.exe")) {
    Write-Error "Game not found at: $GameDir\SoF2.exe"
    exit 1
}

# Verify source files exist
$missing = @()
if (-not (Test-Path $SrcCgame)) { $missing += "$GameDir\cgamex86.dll" }
if (-not (Test-Path $SrcGame))  { $missing += "$GameDir\gamex86.dll" }
if (-not (Test-Path "$WeaponDir\WeaponMod.pk3")) { $missing += "WeaponMod\WeaponMod.pk3" }
if (-not (Test-Path "$WeaponDir\zz_realistic_damage.pk3")) { $missing += "WeaponMod\zz_realistic_damage.pk3" }
if ($missing.Count -gt 0) {
    Write-Error "Missing source files: $($missing -join ', ')"
    exit 1
}

# Create mod folder
if (-not (Test-Path $ModDir)) {
    New-Item -ItemType Directory -Path $ModDir -Force | Out-Null
}

# --- Step 1: Copy WeaponMod files ---
Write-Host "[1/6] Copying WeaponMod files..." -ForegroundColor Yellow
Copy-Item "$WeaponDir\WeaponMod.pk3" "$ModDir\WeaponMod.pk3" -Force
Copy-Item "$WeaponDir\zz_realistic_damage.pk3" "$ModDir\zz_realistic_damage.pk3" -Force
Copy-Item "$WeaponDir\sof2sp.cfg" "$ModDir\sof2sp.cfg" -Force -ErrorAction SilentlyContinue
if (Test-Path "$WeaponDir\gfx") {
    Copy-Item "$WeaponDir\gfx" "$ModDir\gfx" -Recurse -Force
}
Write-Host "  OK: WeaponMod.pk3, zz_realistic_damage.pk3, sof2sp.cfg" -ForegroundColor Green

# --- Step 2: Copy and patch cgamex86.dll ---
Write-Host "[2/6] Patching cgamex86.dll..." -ForegroundColor Yellow

# Copy fresh from source
Copy-Item $SrcCgame $DstCgame -Force
$cgBytes = [System.IO.File]::ReadAllBytes($DstCgame)

$patchCount = 0
foreach ($patch in $CgamePatches) {
    $off = $patch.Offset
    $orig = $patch.Original
    $desc = $patch.Desc

    # Verify original bytes match
    $match = $true
    for ($i = 0; $i -lt $orig.Length; $i++) {
        if ($cgBytes[$off + $i] -ne $orig[$i]) {
            $match = $false
            break
        }
    }

    if (-not $match) {
        $actual = ($cgBytes[$off..($off+3)] | ForEach-Object { $_.ToString("X2") }) -join " "
        $expected = ($orig | ForEach-Object { $_.ToString("X2") }) -join " "
        Write-Warning "  SKIP $desc - bytes at 0x$($off.ToString('X')) don't match (expected: $expected, got: $actual)"
        continue
    }

    # Apply patch
    for ($i = 0; $i -lt $INTMAX.Length; $i++) {
        $cgBytes[$off + $i] = $INTMAX[$i]
    }
    Write-Host "  OK: $desc" -ForegroundColor Green
    $patchCount++
}

[System.IO.File]::WriteAllBytes($DstCgame, $cgBytes)
Write-Host "  Applied $patchCount/$($CgamePatches.Count) patches to cgamex86.dll" -ForegroundColor Green

# --- Step 3: Copy and patch gamex86.dll ---
Write-Host "[3/6] Patching gamex86.dll..." -ForegroundColor Yellow
Copy-Item $SrcGame $DstGame -Force
$gameBytes = [System.IO.File]::ReadAllBytes($DstGame)

# Patch 1: bodytime default from "30000" (30s) to "9999999" (~2.78 hours)
# The string "30000\0\0\0" at offset 0x1FDBAC has 8 bytes available.
# This is the monster_spawner entity key default - NOT a cvar.
$btOff = 0x1FDBAC
$btOrig = [byte[]](0x33,0x30,0x30,0x30,0x30,0x00,0x00,0x00)  # "30000\0\0\0"
$btNew  = [byte[]](0x39,0x39,0x39,0x39,0x39,0x39,0x39,0x00)  # "9999999\0"

$btMatch = $true
for ($i = 0; $i -lt $btOrig.Length; $i++) {
    if ($gameBytes[$btOff + $i] -ne $btOrig[$i]) { $btMatch = $false; break }
}

if ($btMatch) {
    for ($i = 0; $i -lt $btNew.Length; $i++) { $gameBytes[$btOff + $i] = $btNew[$i] }
    Write-Host "  OK: bodytime default 30000ms -> 9999999ms (~2.78 hours)" -ForegroundColor Green
} else {
    Write-Warning "  SKIP: bodytime bytes at 0x1FDBAC don't match (already patched?)"
}

# Patch 2: Disable visibility-based body culling (PlayerCull)
# At offset 0x18A06F the code checks entity->PlayerCull and enters the
# body removal path when the flag is set. Original instruction:
#   0F 84 CE 1C 00 00   jz +0x1CCE  (skip removal when PlayerCull==0)
# Patch to unconditional jump so removal is ALWAYS skipped:
#   E9 CF 1C 00 00 90   jmp +0x1CCF; nop
$pcOff  = 0x18A06F
$pcOrig = [byte[]](0x0F,0x84,0xCE,0x1C,0x00,0x00)  # jz (conditional)
$pcNew  = [byte[]](0xE9,0xCF,0x1C,0x00,0x00,0x90)  # jmp (unconditional) + nop

$pcMatch = $true
for ($i = 0; $i -lt $pcOrig.Length; $i++) {
    if ($gameBytes[$pcOff + $i] -ne $pcOrig[$i]) { $pcMatch = $false; break }
}

if ($pcMatch) {
    for ($i = 0; $i -lt $pcNew.Length; $i++) { $gameBytes[$pcOff + $i] = $pcNew[$i] }
    Write-Host "  OK: PlayerCull visibility culling DISABLED (jz -> jmp)" -ForegroundColor Green
} else {
    $actual = ($gameBytes[$pcOff..($pcOff+5)] | ForEach-Object { $_.ToString("X2") }) -join " "
    Write-Warning "  SKIP: PlayerCull patch - bytes at 0x$($pcOff.ToString('X')) don't match (got: $actual)"
}

[System.IO.File]::WriteAllBytes($DstGame, $gameBytes)
Write-Host "  OK: gamex86.dll copied and patched" -ForegroundColor Green

# --- Step 4: Copy persistence PK3 (blood pool effects) ---
Write-Host "[4/6] Copying zzz_persistence.pk3..." -ForegroundColor Yellow
if (Test-Path $SrcPk3) {
    Copy-Item $SrcPk3 $DstPk3 -Force
    Write-Host "  OK: Blood pool effects with infinite lifetimes" -ForegroundColor Green
} else {
    Write-Warning "  zzz_persistence.pk3 not found in base\ - blood pool override skipped"
}

# --- Step 5: Create merged autoexec.cfg ---
Write-Host "[5/6] Creating merged autoexec.cfg..." -ForegroundColor Yellow

$autoexec = @"
// =============================================================
// SOF2 Combat Mod - Merged Autoexec Config
// WeaponMod realistic damage + permanent bodies/gibs/decals
// =============================================================

// Enable cheats (required for some cvars)
sv_cheats 1

// --- DLL Loading (required for mod DLLs) ---
set vm_game "0"
set vm_cgame "0"
set vm_ui "0"
set com_blindlyloaddlls "1"

// --- Gore / Dismemberment ---
set g_dismember "100"
set cg_dismember "100"
set cg_gibs "1"
set cg_blood "1"

// --- Body Persistence ---
// bodytime: server-side limb/blood splotch removal delay (ms)
// Default 30000 (30s). Set to INT_MAX for permanent.
bodytime 2147483647

// g_corpsecount: max simultaneous dead bodies
set g_corpsecount "64"

// --- Decal / Mark Persistence ---
set cg_marktime "2147483647"
set cg_marks "1"
set r_marksOnTriangleMeshes "1"

// Max number of mark polys the engine will track
set cg_numMarks "4096"

// Server-side procedural decal limit
set g_procDecalLimit "4096"

// --- Brass / Shell Casings ---
set cg_brassTime "2147483647"

// --- Effect Scale ---
// WARNING: values above 2.0 can crash in heavy combat
set fx_countScale "2.0"
"@

Set-Content -Path "$ModDir\autoexec.cfg" -Value $autoexec -Encoding UTF8
Write-Host "  OK: autoexec.cfg created" -ForegroundColor Green

# --- Summary ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  BUILD COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Mod folder: CombatMod\" -ForegroundColor White
Write-Host ""
Write-Host "To activate, add to your game shortcut:" -ForegroundColor White
Write-Host '  +set fs_game CombatMod' -ForegroundColor Yellow
Write-Host ""
Write-Host "Example shortcut target:" -ForegroundColor White
Write-Host '  "C:\...\SoF2.exe" +set fs_game CombatMod' -ForegroundColor Yellow
Write-Host ""
Write-Host "What this mod includes:" -ForegroundColor White
Write-Host "  FROM WEAPONMOD:" -ForegroundColor Magenta
Write-Host "  - Realistic bullet damage (zz_realistic_damage.pk3)" -ForegroundColor Gray
Write-Host "  - WeaponMod content (WeaponMod.pk3)" -ForegroundColor Gray
Write-Host "  FROM PERSISTENCE:" -ForegroundColor Magenta
Write-Host "  - Bodies and severed limbs stay permanently" -ForegroundColor Gray
Write-Host "  - Up to 64 corpses on screen" -ForegroundColor Gray
Write-Host "  - Client-side body/gib timers patched to ~24.8 days (cgamex86.dll)
  - Server-side bodytime patched from 30s to ~2.78h (gamex86.dll)
  - Visibility-based body culling DISABLED (gamex86.dll)" -ForegroundColor Gray
Write-Host "  - Blood pools last entire session (EFX overrides)" -ForegroundColor Gray
Write-Host "  - Bullet holes and blood decals last entire session" -ForegroundColor Gray
Write-Host "  - Shell casings persist on ground" -ForegroundColor Gray
Write-Host ""

# --- Step 6: Update game shortcut ---
$lnkPath = Get-ChildItem $Root -Filter "*.lnk" | Select-Object -First 1
if ($lnkPath) {
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnkPath.FullName)
    $newArgs = "+set fs_game CombatMod +set vm_game 0 +set vm_cgame 0 +set com_blindlyloaddlls 1"
    if ($sc.Arguments -ne $newArgs) {
        $sc.Arguments = $newArgs
        $sc.Save()
        Write-Host "  Shortcut updated: $($lnkPath.Name)" -ForegroundColor Green
        Write-Host "  Args: $newArgs" -ForegroundColor Gray
    } else {
        Write-Host "  Shortcut already correct" -ForegroundColor Green
    }
} else {
    Write-Host "  No .lnk shortcut found - set launch args manually:" -ForegroundColor Yellow
    Write-Host '  +set fs_game CombatMod +set vm_game 0 +set vm_cgame 0 +set com_blindlyloaddlls 1' -ForegroundColor Yellow
}
Write-Host ""

# Keep window open if double-clicked
if ($Host.Name -eq 'ConsoleHost') {
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
