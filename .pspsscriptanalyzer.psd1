@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSUseBOMForUnicodeEncodedFile'
    )
}
