param(
    [Parameter(Mandatory = $true)]
    [string]$MarkdownPath,

    [string]$ChannelId,

    [string]$MentionUserId,

    [string]$EnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw '.env 파일을 찾을 수 없습니다. .env.example을 참고해 만들어 주세요.'
}

$settings = @{}
foreach ($line in Get-Content -LiteralPath $EnvPath) {
    if ($line -match '^\s*#' -or $line -notmatch '=') {
        continue
    }

    $name, $value = $line -split '=', 2
    $settings[$name.Trim()] = $value.Trim().Trim('"').Trim("'")
}

$token = $settings['SLACK_BOT_TOKEN']
if ([string]::IsNullOrWhiteSpace($ChannelId)) {
    $ChannelId = $settings['SLACK_CHANNEL_ID']
}

if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($ChannelId)) {
    throw 'SLACK_BOT_TOKEN 또는 전송 채널 설정이 없습니다.'
}

if (-not (Test-Path -LiteralPath $MarkdownPath)) {
    throw '전송할 Markdown 파일을 찾을 수 없습니다.'
}

$message = Get-Content -Raw -LiteralPath $MarkdownPath
if (-not [string]::IsNullOrWhiteSpace($MentionUserId)) {
    $message = "<@$MentionUserId> 알림 테스트입니다.`n`n$message"
}

$blocks = [System.Collections.Generic.List[object]]::new()
$remaining = $message
while ($remaining.Length -gt 0) {
    $take = [Math]::Min(2800, $remaining.Length)
    if ($take -lt $remaining.Length) {
        $breakAt = $remaining.LastIndexOf("`n", $take - 1, $take)
        if ($breakAt -gt 0) {
            $take = $breakAt + 1
        }
    }

    $chunk = $remaining.Substring(0, $take).Trim()
    if ($chunk.Length -gt 0) {
        $blocks.Add(@{
            type = 'section'
            text = @{ type = 'mrkdwn'; text = $chunk }
        })
    }
    $remaining = $remaining.Substring($take)
}

$payload = @{
    channel = $ChannelId
    text = '프로덕트 디자이너 취업 레이더'
    blocks = $blocks.ToArray()
    unfurl_links = $false
    unfurl_media = $false
} | ConvertTo-Json -Depth 8

$response = Invoke-RestMethod `
    -Uri 'https://slack.com/api/chat.postMessage' `
    -Method Post `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType 'application/json; charset=utf-8' `
    -Body $payload

if (-not $response.ok) {
    throw "Slack 전송 실패: $($response.error)"
}

[pscustomobject]@{
    ok = $true
    channel = $response.channel
    ts = $response.ts
} | ConvertTo-Json -Compress

