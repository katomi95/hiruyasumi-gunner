# 無線のセリフを Windows の音声合成（OneCore の英語音声）で WAV にする
#
#   powershell -ExecutionPolicy Bypass -File tools/gen_voice.ps1
#   py -3.10 tools/gen_voice_fx.py      （無線らしい音質にして audio/voice/ へ）
#
# 話者ごとに声と高さ・速さを変える。男性の役は David を低く遅めにして渋くする
param([string]$Only = "")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $PSScriptRoot "voice_raw"
New-Item -ItemType Directory -Force $out | Out-Null

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) {
    $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

$all = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices
function Find-Voice([string[]]$names) {
    foreach ($n in $names) {
        $v = $all | Where-Object { $_.DisplayName -like "*$n*" -and $_.Language -like "en-*" } | Select-Object -First 1
        if ($v) { return $v }
    }
    return $null
}

# 話者 → 声の候補（先頭から探す）・高さ・速さ
$cast = @{
    "旗艦"     = @{ voices = @("David", "Mark"); pitch = "-14%"; rate = "-12%" }
    "艦長"     = @{ voices = @("David", "Mark"); pitch = "-8%";  rate = "-5%" }
    "砲術長"   = @{ voices = @("Mark", "David"); pitch = "-10%"; rate = "+2%" }
    "航法"     = @{ voices = @("Zira");          pitch = "-3%";  rate = "+4%" }
    "艦隊通信" = @{ voices = @("Zira");          pitch = "+0%";  rate = "+10%" }
}

$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$lines = Get-Content -Encoding UTF8 (Join-Path $PSScriptRoot "voice_lines.tsv") | Select-Object -Skip 1
$made = 0
foreach ($line in $lines) {
    if ($line.Trim() -eq "") { continue }
    $c = $line -split "`t"
    $id = $c[0]; $who = $c[1]; $en = $c[3]
    if ($Only -ne "" -and $id -ne $Only) { continue }
    $role = $cast[$who]
    $voice = Find-Voice $role.voices
    if (-not $voice) { throw "英語の音声が見つかりません（候補: $($role.voices -join ', ')）。英語の音声パックを追加してください" }
    $synth.Voice = $voice
    $text = [System.Security.SecurityElement]::Escape($en)
    $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'><prosody pitch='$($role.pitch)' rate='$($role.rate)'>$text</prosody></speak>"
    $stream = Await ($synth.SynthesizeSsmlToStreamAsync($ssml)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    $size = [uint32]$stream.Size
    $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
    Await ($reader.LoadAsync($size)) ([uint32]) | Out-Null
    $bytes = New-Object byte[] $size
    $reader.ReadBytes($bytes)
    [IO.File]::WriteAllBytes((Join-Path $out "$id.wav"), $bytes)
    Write-Output ("{0,-9} {1,-5} {2}" -f $id, $voice.DisplayName, $en)
    $made++
}
Write-Output "$made lines"
