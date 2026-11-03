Set-StrictMode -Version Latest

function Get-JarvisEnvValue {
    param([string]$EnvFile, [string]$Name)
    if (-not (Test-Path $EnvFile)) { return '' }
    $line = (Read-JarvisUtf8Text $EnvFile) -split "\r?\n" | Where-Object { $_ -match "^$([regex]::Escape($Name))=" } | Select-Object -First 1
    if ($line) { return ($line -split '=', 2)[1].Trim().Trim('"') }
    ''
}

function Invoke-JarvisTelegramApi {
    param([string]$Token, [string]$Method, [hashtable]$Body = @{})
    $safe = "https://api.telegram.org/bot$Token/$Method"
    $response = Invoke-RestMethod -Uri $safe -Method Post -Body $Body -ContentType 'application/x-www-form-urlencoded'
    if (-not $response.ok) { throw "Telegram $Method failed" }
    $response.result
}

function Normalize-JarvisTelegramChatId {
    param([string]$Token, [string]$ChatId)
    $normalized = $ChatId.Trim()
    if ($normalized -match '^\d+$' -and $normalized.Length -ge 10) { $normalized = "-$normalized" }
    if ($normalized -notmatch '^-?\d+$') { throw "Telegram chat ID is invalid: $ChatId" }
    $chat = Invoke-JarvisTelegramApi $Token 'getChat' @{ chat_id = $normalized }
    if ($chat.type -notin @('group','supergroup')) { throw "Telegram chat $normalized is not a group or supergroup." }
    $normalized
}

function Find-JarvisTelegramGroup {
    param([object[]]$Updates)
    foreach ($update in @($Updates | Sort-Object update_id -Descending)) {
        $chat = if ($update.message) { $update.message.chat } elseif ($update.channel_post) { $update.channel_post.chat } else { $null }
        if ($chat -and $chat.type -in @('group','supergroup')) {
            return [pscustomobject]@{ id = [string]$chat.id; title = [string]$chat.title; type = [string]$chat.type }
        }
    }
    $null
}

function Get-JarvisTelegramGroupFromUpdates {
    param([string]$Token)
    Find-JarvisTelegramGroup -Updates @(Invoke-JarvisTelegramApi $Token 'getUpdates')
}

function New-JarvisTelegramTopics {
    param([string]$Token, [string]$ChatId)
    $member = Invoke-JarvisTelegramApi $Token 'getChatMember' @{ chat_id = $ChatId; user_id = (Invoke-JarvisTelegramApi $Token 'getMe').id }
    if ($member.status -ne 'administrator' -or -not $member.can_manage_topics) { throw 'Telegram bot must be an administrator with Manage Topics.' }
    $topics = [ordered]@{ chat_id = [string]$ChatId; topics = [ordered]@{} }
    foreach ($name in @('DEV','RESEARCH','ASSISTANT')) { $topic = Invoke-JarvisTelegramApi $Token 'createForumTopic' @{ chat_id = $ChatId; name = $name }; $topics.topics[[string]$topic.message_thread_id] = $name.ToLowerInvariant() }
    $topics
}

function Write-JarvisTelegramPlugin {
    param([string]$HermesHome, [hashtable]$TopicMap, [string]$OwnerName)
    $dir = Join-Path $HermesHome 'plugins\telegram_topic_profiles'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Write-JarvisUtf8Text -Path (Join-Path $dir 'plugin.yaml') -Text (@("name: telegram_topic_profiles", "version: 1.0.0", 'description: "Route Telegram forum topics to Hermes profiles."', "author: $OwnerName", 'kind: standalone') -join "`n")
    Write-JarvisUtf8Text -Path (Join-Path $dir 'topics.json') -Text ($TopicMap | ConvertTo-Json -Depth 5)
    $plugin = @'
import json
from pathlib import Path
def _load_map():
    return json.loads((Path(__file__).parent / "topics.json").read_text())
def _route(**kwargs):
    source = kwargs.get("source")
    if source is None: return
    if not getattr(source, "thread_id", None) or getattr(source, "profile", None): return
    mapping = _load_map()
    if str(getattr(source, "chat_id", "")) != str(mapping.get("chat_id")): return
    profile = mapping.get("topics", {}).get(str(getattr(source, "thread_id", "")))
    if profile: source.profile = profile
def register(ctx):
    ctx.register_hook("pre_gateway_dispatch", _route)
'@
    Write-JarvisUtf8Text -Path (Join-Path $dir '__init__.py') -Text $plugin
}

Export-ModuleMember -Function *-Jarvis*
