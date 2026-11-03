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

function Get-JarvisTelegramProfileRoutes {
    param([object]$TopicMap)
    $routes = @()
    $topics = if ($TopicMap.topics -is [Collections.IDictionary]) { @($TopicMap.topics.GetEnumerator()) } else { @($TopicMap.topics.PSObject.Properties) }
    foreach ($topic in $topics) {
        $topicId = if ($topic -is [Collections.DictionaryEntry]) { $topic.Key } else { $topic.Name }
        $profile = if ($topic -is [Collections.DictionaryEntry]) { $topic.Value } else { $topic.Value }
        if ($profile -notin @('dev','research','assistant')) { continue }
        $routes += [ordered]@{
            name = "telegram-$profile"
            platform = 'telegram'
            profile = $profile
            chat_id = [string]$TopicMap.chat_id
            thread_id = [string]$topicId
        }
    }
    @($routes)
}

Export-ModuleMember -Function *-Jarvis*
