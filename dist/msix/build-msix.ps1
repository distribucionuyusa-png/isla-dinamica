# Arma IslaDinamica-<versión>.msix a partir de la carpeta publicada de la app.
# Uso (Windows, con el Windows SDK):  .\packaging\msix\build-msix.ps1 -AppDir <carpeta con IslaDinamica.exe> -Version 1.8.0
# - Para la Microsoft Store: identity.json con los valores de Partner Center; el .msix se sube SIN firmar (la Store lo firma).
# - Para probar en una PC: con SignForSideload = true se firma con un certificado de prueba y se deja el .cer al lado.
param(
    [Parameter(Mandatory = $true)][string]$AppDir,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\out')
)
$ErrorActionPreference = 'Stop'
$id = Get-Content (Join-Path $PSScriptRoot 'identity.json') -Raw | ConvertFrom-Json
$v = [Version]$Version
$pkgVersion = "$($v.Major).$($v.Minor).$([Math]::Max(0,$v.Build)).0"

# Herramientas del Windows SDK (la versión más nueva instalada).
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $sdk) { throw 'No se encontró makeappx.exe: instala el Windows SDK.' }
$makeappx = $sdk.FullName
$signtool = Join-Path $sdk.DirectoryName 'signtool.exe'

$layout = Join-Path $env:TEMP "IslaDinamica-msix-$pkgVersion"
if (Test-Path $layout) { Remove-Item $layout -Recurse -Force }
Copy-Item $AppDir $layout -Recurse
Copy-Item (Join-Path $PSScriptRoot 'Assets') (Join-Path $layout 'Assets') -Recurse -Force
# El desinstalador del Setup.exe no va en el paquete.
Remove-Item (Join-Path $layout 'Desinstalar.exe') -ErrorAction SilentlyContinue

$manifest = Get-Content (Join-Path $PSScriptRoot 'AppxManifest.xml') -Raw
$manifest = $manifest.Replace('{{IDENTITY_NAME}}', $id.IdentityName).Replace('{{PUBLISHER}}', $id.Publisher).
    Replace('{{PUBLISHER_DISPLAY_NAME}}', $id.PublisherDisplayName).Replace('{{VERSION}}', $pkgVersion)
Set-Content (Join-Path $layout 'AppxManifest.xml') $manifest -Encoding UTF8

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$msix = Join-Path $OutDir "IslaDinamica-$Version.msix"
& $makeappx pack /d $layout /p $msix /o
if ($LASTEXITCODE -ne 0) { throw "makeappx falló ($LASTEXITCODE)" }

if ($id.SignForSideload) {
    # Certificado de prueba con el mismo Publisher del manifiesto (solo para instalar en PCs de prueba).
    $cert = New-SelfSignedCertificate -Type Custom -Subject $id.Publisher -KeyUsage DigitalSignature `
        -FriendlyName 'Isla dinámica (prueba)' -CertStoreLocation 'Cert:\CurrentUser\My' `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    $pfx = Join-Path $env:TEMP 'IslaDinamica-prueba.pfx'
    $pwd = ConvertTo-SecureString -String 'isla-prueba' -Force -AsPlainText
    Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $pwd | Out-Null
    Export-Certificate -Cert $cert -FilePath (Join-Path $OutDir 'IslaDinamica-prueba.cer') | Out-Null
    & $signtool sign /fd SHA256 /a /f $pfx /p 'isla-prueba' $msix
    if ($LASTEXITCODE -ne 0) { throw "signtool falló ($LASTEXITCODE)" }
}
Write-Host "Paquete: $msix"
