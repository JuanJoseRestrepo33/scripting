param(
  [string]$sharePath,
  [string]$driveLetter
)

# --- Configuración de FSLogix (sin join al dominio) ---
Write-Host "Iniciando configuración de FSLogix..."

# Desmontar si ya está montado
if (Test-Path "$driveLetter\") {
    Write-Host "Desmontando unidad $driveLetter si existe..."
    net use $driveLetter /delete /y
}

# Montar el recurso compartido
Write-Host "Montando recurso compartido: $sharePath en $driveLetter"
net use $driveLetter $sharePath

# Verificar que se montó correctamente
if (Test-Path "$driveLetter\") {
    Write-Host "Recurso compartido montado exitosamente"
} else {
    Write-Error "Error al montar el recurso compartido"
    exit 1
}

# Permisos NTFS recomendados
Write-Host "Aplicando permisos NTFS..."
icacls $driveLetter /grant "NT AUTHORITY\Authenticated Users:(OI)(CI)(M)"
icacls $driveLetter /grant "CREATOR OWNER:(OI)(CI)(IO)(F)"
icacls $driveLetter /setowner "BUILTIN\Administrators"

# --- Configuración de FSLogix ---
Write-Host "Configurando FSLogix..."
$regPath = "HKLM:\SOFTWARE\FSLogix\Profiles"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force
    Write-Host "Clave de registro de FSLogix Profiles creada."
}

New-ItemProperty -Path $regPath -Name "Enabled" -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "VHDLocations" -Value $sharePath -PropertyType String -Force
New-ItemProperty -Path $regPath -Name "VolumeType" -Value "VHDX" -PropertyType String -Force
New-ItemProperty -Path $regPath -Name "SizeInMBs" -Value 30000 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -PropertyType DWord -Force

# Configuraciones adicionales para Azure AD
New-ItemProperty -Path $regPath -Name "ConcurrentUserSessions" -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "FlipFlopProfileDirectoryName" -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "IsDynamic" -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "LoadDynamicSettings" -Value 1 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "ProfileType" -Value 0 -PropertyType DWord -Force
New-ItemProperty -Path $regPath -Name "RedirXMLSourceFolder" -Value "" -PropertyType String -Force
New-ItemProperty -Path $regPath -Name "SIDDirNamePattern" -Value "%username%" -PropertyType String -Force
New-ItemProperty -Path $regPath -Name "SIDDirNameMatch" -Value "%username%" -PropertyType String -Force

Write-Host "¡Configuración de FSLogix completada exitosamente!"

# --- Configuración adicional para AVD ---
Write-Host "Configurando ajustes adicionales para AVD..."

# Configurar políticas de redirección de carpetas (opcional)
$redirRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (-not (Test-Path $redirRegPath)) {
    New-Item -Path $redirRegPath -Force | Out-Null
}

# Habilitar redirección de carpetas
New-ItemProperty -Path $redirRegPath -Name "EnableSmartScreen" -Value 0 -PropertyType DWord -Force | Out-Null

# Configurar políticas de Windows
$windowsRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $windowsRegPath)) {
    New-Item -Path $windowsRegPath -Force | Out-Null
}

# Deshabilitar OneDrive
New-ItemProperty -Path $windowsRegPath -Name "DisablePersonalDirChange" -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host "Configuración adicional completada."

# --- Verificación final ---
Write-Host "Verificando configuración..."
$fslogixEnabled = Get-ItemProperty -Path $regPath -Name "Enabled" -ErrorAction SilentlyContinue
if ($fslogixEnabled -and $fslogixEnabled.Enabled -eq 1) {
    Write-Host "✅ FSLogix está habilitado correctamente"
} else {
    Write-Warning "⚠️ FSLogix no está habilitado"
}

$vhdLocation = Get-ItemProperty -Path $regPath -Name "VHDLocations" -ErrorAction SilentlyContinue
if ($vhdLocation) {
    Write-Host "✅ Ubicación VHD configurada: $($vhdLocation.VHDLocations)"
} else {
    Write-Warning "⚠️ Ubicación VHD no configurada"
}

Write-Host "🎉 ¡Configuración de FSLogix completada exitosamente!"
Write-Host "Nota: El dispositivo se unirá automáticamente a Azure AD mediante la extensión AADLoginForWindows."
