[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$GitArguments
)

$names = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')
$previous = @{}
foreach ($name in $names) {
    $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    $previous[$name] = @{
        Exists = $null -ne $item
        Value = if ($null -ne $item) { $item.Value } else { $null }
    }
}

try {
    $env:HTTP_PROXY = ''
    $env:HTTPS_PROXY = ''
    $env:ALL_PROXY = ''
    $env:NO_PROXY = 'github.com,api.github.com,raw.githubusercontent.com'

    Get-Command git -ErrorAction Stop | Out-Null
    & git -c http.proxy= -c https.proxy= @GitArguments
    $gitExitCode = $LASTEXITCODE
}
finally {
    foreach ($name in $names) {
        if ($previous[$name].Exists) {
            Set-Item -LiteralPath "Env:$name" -Value $previous[$name].Value
        }
        else {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}

exit $gitExitCode
