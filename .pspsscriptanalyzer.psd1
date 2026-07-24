@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseDeclaredVarsMoreThanAssignment'
        'PSUseBOMForUnicodeEncodedFile'
    )
}
