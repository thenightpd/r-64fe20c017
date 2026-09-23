$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = 'https://thenightpd.github.io/r-64fe20c017/pli/setup.ps1'
$expected = 'EDB3AF78FAD414BB00D898B093D9AEF290CDE511C2ED957B1E656A297EAF9150'

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
