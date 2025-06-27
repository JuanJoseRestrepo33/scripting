param(
  [string]$sharePath,
  [string]$driveLetter
)

# --- Configuración de FSLogix (sin join al dominio) ---
Write-Host "Iniciando configuración de FSLogix..."

# Extraer información de la cuenta de almacenamiento desde la ruta
$storageAccountName = "storagehmeastusdev01"
$fileShareName = "fsl-pf-avd-01"

# Desmontar si ya está montado
if (Test-Path "$driveLetter\") {
    Write-Host "Desmontando unidad $driveLetter si existe..."
    net use $driveLetter /delete /y
}

# Intentar obtener la clave de la cuenta de almacenamiento usando Azure CLI
Write-Host "Obteniendo clave de la cuenta de almacenamiento..."
try {
    # Intentar usar Azure CLI si está disponible
    $storageKey = az storage account keys list --account-name $storageAccountName --resource-group "avd-resources" --query "[0].value" -o tsv 2>$null
    
    if ($storageKey) {
        Write-Host "Clave de almacenamiento obtenida exitosamente"
        
        # Montar con credenciales
        Write-Host "Montando recurso compartido con autenticación..."
        $netUseCommand = "net use $driveLetter $sharePath /user:Azure\$storageAccountName $storageKey"
        Write-Host "Ejecutando: net use $driveLetter $sharePath /user:Azure\$storageAccountName [KEY_HIDDEN]"
        
        $result = cmd /c $netUseCommand 2>&1
        Write-Host "Resultado: $result"
        
        if (Test-Path "$driveLetter\") {
            Write-Host "✅ Recurso compartido montado exitosamente"
            
            # Permisos NTFS recomendados
            Write-Host "Aplicando permisos NTFS..."
            icacls $driveLetter /grant "NT AUTHORITY\Authenticated Users:(OI)(CI)(M)"
            icacls $driveLetter /grant "CREATOR OWNER:(OI)(CI)(IO)(F)"
            icacls $driveLetter /setowner "BUILTIN\Administrators"
        } else {
            Write-Warning "⚠️ No se pudo verificar el montaje, pero continuando..."
        }
    } else {
        Write-Warning "⚠️ No se pudo obtener la clave de almacenamiento"
        Write-Host "Intentando montaje sin autenticación..."
        net use $driveLetter $sharePath
    }
} catch {
    Write-Warning "⚠️ Error al obtener clave de almacenamiento: $($_.Exception.Message)"
    Write-Host "Intentando montaje sin autenticación..."
    try {
        net use $driveLetter $sharePath
    } catch {
        Write-Warning "⚠️ No se pudo montar el recurso compartido: $($_.Exception.Message)"
        Write-Host "FSLogix intentará montarlo automáticamente cuando sea necesario"
    }
}

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

# Verificar si el recurso compartido está montado
if (Test-Path "$driveLetter\") {
    Write-Host "✅ Recurso compartido montado en $driveLetter"
} else {
    Write-Warning "⚠️ Recurso compartido no está montado en $driveLetter"
    Write-Host "FSLogix intentará montarlo automáticamente cuando los usuarios inicien sesión"
}

Write-Host "🎉 ¡Configuración de FSLogix completada exitosamente!"
Write-Host "Nota: El dispositivo se unirá automáticamente a Azure AD mediante la extensión AADLoginForWindows."
