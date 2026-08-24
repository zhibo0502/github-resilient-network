[CmdletBinding()]
param()

$scriptPath = Join-Path $PSScriptRoot 'git-direct.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("github-direct-test-" + [guid]::NewGuid())
$capture = Join-Path $temporary 'capture.txt'
$fakeGit = Join-Path $temporary 'git.cmd'
$originalPath = $env:PATH
$originalCapture = $env:GITHUB_DIRECT_TEST_CAPTURE
$proxyNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')
$originalProxy = @{}
foreach ($name in $proxyNames) {
    $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    $originalProxy[$name] = @{
        Exists = $null -ne $item
        Value = if ($null -ne $item) { $item.Value } else { $null }
    }
}
$sentinels = @{
    HTTP_PROXY = 'http-sentinel'
    HTTPS_PROXY = 'https-sentinel'
    ALL_PROXY = 'all-sentinel'
    NO_PROXY = 'no-sentinel'
}

try {
    New-Item -ItemType Directory -Path $temporary -ErrorAction Stop | Out-Null
    @'
@echo off
(
echo HTTP_PROXY=%HTTP_PROXY%
echo HTTPS_PROXY=%HTTPS_PROXY%
echo ALL_PROXY=%ALL_PROXY%
echo NO_PROXY=%NO_PROXY%
echo ARGS=%*
) > "%GITHUB_DIRECT_TEST_CAPTURE%"
exit /b 37
'@ | Set-Content -LiteralPath $fakeGit -Encoding ascii

    foreach ($entry in $sentinels.GetEnumerator()) {
        Set-Item -LiteralPath "Env:$($entry.Key)" -Value $entry.Value
    }
    $env:GITHUB_DIRECT_TEST_CAPTURE = $capture
    $env:PATH = "$temporary;$originalPath"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath push origin test-branch
    if ($LASTEXITCODE -ne 37) {
        throw "expected git exit 37, got $LASTEXITCODE"
    }

    foreach ($entry in $sentinels.GetEnumerator()) {
        if ((Get-Item -LiteralPath "Env:$($entry.Key)").Value -ne $entry.Value) {
            throw "wrapper did not restore $($entry.Key)"
        }
    }

    $lines = Get-Content -LiteralPath $capture
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY')) {
        if ($lines -notcontains "$name=") {
            throw "$name was not empty inside git child"
        }
    }
    if ($lines -notcontains 'NO_PROXY=github.com,api.github.com,raw.githubusercontent.com') {
        throw 'NO_PROXY did not contain the direct GitHub hosts'
    }
    $argsLine = $lines | Where-Object { $_ -like 'ARGS=*' }
    if ($argsLine -ne 'ARGS=-c http.proxy= -c https.proxy= push origin test-branch') {
        throw "unexpected git arguments: $argsLine"
    }

    Write-Output 'git-direct self-test passed'
}
finally {
    $env:PATH = $originalPath
    if ($null -eq $originalCapture) {
        Remove-Item Env:GITHUB_DIRECT_TEST_CAPTURE -ErrorAction SilentlyContinue
    }
    else {
        $env:GITHUB_DIRECT_TEST_CAPTURE = $originalCapture
    }
    foreach ($name in $proxyNames) {
        if ($originalProxy[$name].Exists) {
            Set-Item -LiteralPath "Env:$name" -Value $originalProxy[$name].Value
        }
        else {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
}
