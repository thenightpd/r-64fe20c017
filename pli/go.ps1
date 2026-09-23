$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = 'https://thenightpd.github.io/r-64fe20c017/pli/setup.ps1'
$expected = '78B220ECA9E4566D43E29B90428F4B54B15B4BE82BD3B2E461BEEB8D20175D70'

$client = New-Object Net.WebClient
try {
  [byte[]]$bytes = $client.DownloadData($url)
} finally {
  $client.Dispose()
}

$hasher = [Security.Cryptography.SHA256]::Create()
try {
  $actual = [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '')
} finally {
  $hasher.Dispose()
}

if ($actual -cne $expected) {
  throw "Setup hash mismatch. Expected $expected but received $actual."
}

$code = [Text.Encoding]::UTF8.GetString($bytes)
& ([ScriptBlock]::Create($code))
