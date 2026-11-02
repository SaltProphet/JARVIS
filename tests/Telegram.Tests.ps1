$module = Join-Path $PSScriptRoot '..\installer\lib\telegram.psm1'
Import-Module $module -Force

Describe 'Telegram owner chat discovery' {
    It 'selects a group update and exposes its title for confirmation' {
        $updates = @([pscustomobject]@{ message = [pscustomobject]@{ chat = [pscustomobject]@{ id = -123; type = 'supergroup'; title = 'JARVIS Crew' } } })
        $candidate = Find-JarvisTelegramGroup -Updates $updates
        $candidate.id | Should Be '-123'
        $candidate.title | Should Be 'JARVIS Crew'
    }
}
