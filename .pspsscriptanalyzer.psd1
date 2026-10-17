@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        # This is a CLI tool: Write-Host is the output channel, not a debugging aid.
        'PSAvoidUsingWriteHost'

        # State-changing helpers declare SupportsShouldProcess and delegate the
        # ShouldProcess call down the chain rather than gating themselves, so
        # -WhatIf propagates transitively instead of being consumed at each layer.
        'PSUseShouldProcessForStateChangingFunctions'
        'PSShouldProcess'

        # Dot-sourced bootstrap files intentionally rebind caller-scope variables.
        'PSUseDeclaredVarsMoreThanAssignments'

        # Scripts are written UTF-8 without BOM and stay ASCII-only, which is the
        # subset Windows PowerShell 5.1 reads correctly without a BOM.
        'PSUseBOMForUnicodeEncodedFile'

        # Functions that return collections are named in the plural
        # (Get-ManifestLinks, Get-PluginFolders, Resolve-EntryMappings). Renaming
        # them to satisfy the rule would misrepresent what they return.
        'PSUseSingularNouns'

        # Discover / Format / Save are the domain verbs here. PSUseApprovedVerbs
        # does not know them and would push worse substitutes like ConvertTo.
        'PSUseApprovedVerbs'
    )
}