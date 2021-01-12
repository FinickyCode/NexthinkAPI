@{
    IncludeDefaultRules = $true
    ExcludeRules =
    @(
    )
    Rules =
    @{
        PSUseCompatibleSyntax =
        @{
            Enable = $true

            # Versions of PowerShell to check for compatibility
            TargetVersions =
            @(
                '5.1'
                '7.0'
            )
        }
        PSUseCompatibleCommands =
        @{
            Enable = $true

            # Identifies commands that are not available on a targeted PowerShell platform.
            # https://github.com/PowerShell/PSScriptAnalyzer/blob/master/RuleDocumentation/UseCompatibleCommands.md
            TargetProfiles =
            @(
                # PowerShell 5.1 on Windows Server 2019
                'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
            )
        }
        PSUseCompatibleTypes =
        @{
            Enable = $true

            # Types that are not available (loaded by default) in targeted PowerShell platforms.
            # https://github.com/PowerShell/PSScriptAnalyzer/blob/master/RuleDocumentation/UseCompatibleTypes.md
            TargetProfiles =
            @(
                # PowerShell 5.1 on Windows Server 2019
                'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
            )

        }

        PSPlaceOpenBrace =
        @{
            Enable              = $true
            OnSameLine          = $false
            NewLineAfter        = $true
            IgnoreOneLineBlock  = $true
        }

        PSPlaceCloseBrace =
        @{
            Enable              = $true
            NewLineAfter        = $true
            IgnoreOneLineBlock  = $true
            NoEmptyLineBefore   = $false
        }

        PSUseConsistentIndentation =
        @{
            Enable              = $false
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        PSUseConsistentWhitespace =
        @{
            Enable                          = $false # Poor compatability on PS5
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $false
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator                  = $false
            CheckParameter                  = $false
        }

        PSAlignAssignmentStatement =
        @{
            Enable          = $false
            CheckHashtable  = $true
        }

        PSUseCorrectCasing =
        @{
            Enable  = $true
        }

        PSAvoidLongLines =
        @{
            Enable  = $true
        }

        PSProvideCommentHelp =
        @{
            Enable = $true
            ExportedOnly = $true
            BlockComment = $true
            VSCodeSnippetCorrection = $true
            Placement = "before"
        }
    }
}
