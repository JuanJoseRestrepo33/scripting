param(
  [string]$domain,
  [string]$domainUser,
  [string]$domainPass
)

# --- 1. Unir la VM al dominio ---
$securePass = ConvertTo-SecureString $domainPass -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($domainUser, $securePass)

Add-Computer -DomainName $domain -Credential $credential -Force
Write-Host "¡VM unida al dominio! Reiniciando en 10 segundos..."
Start-Sleep -Seconds 10
Restart-Computer
return  # El script se detiene aquí hasta después del reinicio

# --- 2. Montar el File Share y aplicar permisos NTFS ---
# (Ejecuta esta parte después del reinicio y login como usuario de dominio)

$sharePath = "\\storagehmeastusdev01.file.core.windows.net\fsl-pf-avd-01"
$driveLetter = "Z:"

# Desmontar si ya está montado
if (Test-Path "$driveLetter\") {
    net use $driveLetter /delete /y
}

# Montar el recurso compartido
net use $driveLetter $sharePath

# Permisos NTFS recomendados
icacls $driveLetter /grant "NT AUTHORITY\Authenticated Users:(OI)(CI)(M)"
icacls $driveLetter /grant "CREATOR OWNER:(OI)(CI)(IO)(F)"
icacls $driveLetter /setowner "BUILTIN\Administrators"

# --- Configuración de FSLogix ---
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

Write-Host "¡Configuración de FSLogix completada!"
Write-Host "Por favor, cierra sesión e inicia sesión de nuevo con un usuario de prueba para verificar."
