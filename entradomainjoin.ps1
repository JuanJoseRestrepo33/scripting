param(
  [string]$sharePath,
  [string]$driveLetter
)

# --- Solo configuración de FSLogix (sin join al dominio) ---
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

Write-Host "¡Configuración de FSLogix completada exitosamente!"
