$global:progresspreference = 'SilentlyContinue'

Describe 'The network' {
    Context 'on the machine' {
        It 'should have a WinRM enabled' {
            [bool](Test-WSMan -ErrorAction SilentlyContinue) | Should Be $true
        }
    }
}