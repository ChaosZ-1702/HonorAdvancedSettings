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
    -A "$proj\assets" `
    -R "$build\res.zip" `
    --min-sdk-version 28 --target-sdk-version 35 `
    --version-code 42 --version-name 1.4.19 `
    --java "$build\gen" `
    --auto-add-overlay
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

Write-Host "== 5/7 inject classes.dex =="
python "$proj\inject_dex.py" "$build\base.apk" "$build\classes.dex" "$build\full.apk"

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
