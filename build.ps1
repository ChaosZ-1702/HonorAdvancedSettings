$ErrorActionPreference = "Stop"

$root   = "d:\Users\Administrator\Documents\6ac5cf7d3718c824938055b6\lg"
$tools  = "$root\tools"
$bt     = "$tools\bt\android-14"
$plat   = "$tools\p36\android-36\android.jar"
$xposed = "$tools\api-82.jar"
$ecj    = "$tools\ecj.jar"
$proj   = "$root\honor_adv\module"
$build  = "$proj\build"
$ks     = "$root\honor_adv\voreulch.keystore"

# portable JDK (lg\tools\jdk) — no system java on this machine
$env:JAVA_HOME = "$tools\jdk"
$env:Path = "$tools\jdk\bin;$env:Path"

Remove-Item -Recurse -Force $build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$build\classes" | Out-Null
New-Item -ItemType Directory -Force -Path "$build\gen" | Out-Null

Write-Host "== 1/7 aapt2 compile =="
& "$bt\aapt2.exe" compile --dir "$proj\res" -o "$build\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile failed" }

Write-Host "== 2/7 aapt2 link (emits R.java for the vector icon) =="
& "$bt\aapt2.exe" link -o "$build\base.apk" `
    -I $plat `
    --manifest "$proj\AndroidManifest.xml" `
    -R "$build\res.zip" `
    --min-sdk-version 28 --target-sdk-version 35 `
    --version-code 45 --version-name 1.4.22 `
    --java "$build\gen" `
    --auto-add-overlay
# NOTE: no -A here. aapt2 on Windows writes -A asset entry names with '\'
# separators, which Android's AssetManager cannot read. Assets are added
# by the inject step below with forward-slash names instead.
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

Write-Host "== 3/7 compile (ECJ) =="
$srcFiles = Get-ChildItem "$proj\src" -Recurse -Filter *.java | ForEach-Object { $_.FullName }
$srcFiles += Get-ChildItem "$build\gen" -Recurse -Filter *.java | ForEach-Object { $_.FullName }
java -jar $ecj -source 8 -target 8 -nowarn -proc:none -encoding UTF-8 `
    -classpath "$plat;$xposed" `
    -d "$build\classes" `
    @srcFiles
if ($LASTEXITCODE -ne 0) { throw "compile failed" }

Write-Host "== 4/7 dex (d8) =="
Compress-Archive -Path "$build\classes\*" -DestinationPath "$build\classes.zip" -Force
& "$bt\d8.bat" --release --lib $plat --classpath $xposed --output $build "$build\classes.zip"
if ($LASTEXITCODE -ne 0) { throw "d8 failed" }

Write-Host "== 5/7 inject classes.dex + assets (PowerShell, no python) =="
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Update mode copies untouched entries (resources.arsc etc.) byte-for-byte,
# keeping their STORED compression -- .NET cannot create STORED entries, so
# we must never rewrite those. Entries we add ourselves (classes.dex, all
# assets) are DEFLATED, which is fine for them; assets use forward-slash
# names because aapt2 -A would backslash them on Windows.
$zip = [System.IO.Compression.ZipFile]::Open("$build\base.apk", "Update")
try {
    $old = $zip.GetEntry("classes.dex")
    if ($null -ne $old) { $old.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,
        "$build\classes.dex", "classes.dex",
        [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    $assetRoot = "$proj\assets"
    $baseLen = $assetRoot.Length + 1
    Get-ChildItem $assetRoot -Recurse -File | ForEach-Object {
        $name = "assets/" + $_.FullName.Substring($baseLen).Replace('\', '/')
        $entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
        $fs = [System.IO.File]::OpenRead($_.FullName)
        $es = $entry.Open()
        try { $fs.CopyTo($es) } finally { $es.Dispose(); $fs.Dispose() }
    }
} finally {
    $zip.Dispose()
}
Copy-Item "$build\base.apk" "$build\full.apk" -Force
Write-Host "injected classes.dex + assets -> full.apk (forward-slash names)"

Write-Host "== 6/7 zipalign =="
& "$bt\zipalign.exe" -f 4 "$build\full.apk" "$build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

Write-Host "== 7/7 sign (VoreulCH) =="
& "$bt\apksigner.bat" sign --ks $ks --ks-key-alias voreulch `
    --ks-pass pass:VoreulCH2026Yaoshi --key-pass pass:VoreulCH2026Yaoshi `
    --out "$proj\HonorAdvancedSettings.apk" "$build\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }

Write-Host ""
Write-Host "DONE -> $proj\HonorAdvancedSettings.apk"
