<#
.SYNOPSIS

Interface with the Nexthink API.

#>

#region Exported functions

function Connect-Nexthink
{
    <#
    .SYNOPSIS

    Connect to the Nexthink API.

    .DESCRIPTION

    Connect to the Nexthink API and query environment parameters such as
    available engines.

    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType($null)]
    Param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        # The host name of the portal, i.e. "tenant.region.nexthink.cloud"
        $PortalHost,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.Credential()]
        [Management.Automation.PSCredential]
        # API credentials
        $Credential = (Get-Credential -Message:'Nexthink API account credentials'),

        [Parameter()]
        [int16]
        # The port for API requests to the portal
        $PortalPort = 443,

        [Parameter()]
        [int16]
        # The port for API requests to engines. Defaults to 443 for cloud, 1671
        # otherwise.
        $EnginePort = 0,

        [Parameter()]
        [switch]
        # Skips certificate validation checks. This includes all validations
        # such as expiration, revocation, trusted root authority, etc.
        # WARNING: Using this parameter is not secure and is not recommended.
        # This switch is only intended to be used against known hosts using a
        # self-signed certificate for testing purposes. Use at your own risk.
        $SkipCertificateCheck
    )

    Trap
    {
        throw $_
    }

    # Strip leading https:// and trailing / if present
    $PortalHost = $PortalHost -replace '^https?://' -replace '/$'

    # If the port was passed in the Portal URL, use it in preference to the
    # PortalPort parameter.
    if ( $PortalHost -notmatch ':(\d+)$' )
    {
        $PortalHost += ":${PortalPort}"
    }

    if ( $EnginePort -eq 0 )
    {
        if ( $PortalHost -match '\.cloud\b' )
        {
            $EnginePort = 443
        }
        else
        {
            $EnginePort = 1671
        }
    }

    # Cache the connection info so it doesn't need to be provided every time.
    $script:privNxtPortal = $PortalHost
    $script:privNxtEnginePort = $EnginePort
    $script:privNxtCred = $Credential
    $script:privNxtEngines = @()
    $script:privNxtSkipCerts = $SkipCertificateCheck -eq $true

    # Query the portal API to get a list of the engines.
    $params =
    @{
        'Against'       = 'Portal'
        'Path'          = '/api/configuration/v1/engines'
        'Method'        = 'GET'
    }
    $errored = $true
    try
    {
        $response = Invoke-PrivateNxtQuery @params
        $errored = [string]::IsNullOrEmpty($response)
        if ( $errored )
        {
            throw (
                'No engine data receieved from portal.'
            )
        }
    }
    finally
    {
        if ( $errored )
        {
            # Clear cached connection info on error.
            $script:privNxtPortal = $null
            $script:privNxtEnginePort = 0
            $script:privNxtCred = $null
            $script:privNxtEngines = @()
        }
    }
    $script:privNxtEngines = @($response)
} # function Connect-Nexthink

function Invoke-NexthinkQuery
{
    <#
    .SYNOPSIS

    Run a NXQL query against all engines.

    .DESCRIPTION

    The provided query will be executed against all engines in the environment.

    It's important to note constraint clauses like "(limit 5)" are per engine.
    Also, no deduplication of devices that have history on multiple engines is
    performed.

    .EXAMPLE

    Invoke-NexthinkQuery -Nxql:'(select (name platform last_seen) (from device) (limit 5))'

    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    Param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        # The NXQL query to run
        $Nxql,

        [Parameter()]
        [ValidateSet('windows', 'mac_os', 'mobile')]
        [string[]]
        # Which platforms the query should return. One or more of: windows, mac_os, mobile
        $Platforms = @(),

        [Parameter()]
        [string[]]
        # Any numbered parameters to refer to in the NXQL.
        # Reference using the syntax #%n (where n is the parameter number)
        # i.e. when passing device name as first parameter:
        #     (select name (from device (where device (eq name (string #%1)))
        $Parameters = @(),

        [Parameter()]
        [TimeSpan]
        # Timespan to wait before the request times out.
        $Timeout = [TimeSpan]::FromSeconds(120)
    )

    Trap
    {
        throw $_
    }

    $queryParams =
    @(
        'format=json'
    )
    foreach ( $platform in $Platforms )
    {
        $queryParams += "platform=$platform"
    }
    for ( $i = 0; $i -lt $Parameters.Count; $i++ )
    {
        $queryParams += "p{0}={1}" -f ($i + 1), [Web.HttpUtility]::UrlEncode($Parameters[$i])
    }
    $uriPath = '/2/query?query={0}&{1}' -f
        [Web.HttpUtility]::UrlEncode($Nxql),
        ($queryParams -join '&')

    Invoke-PrivateNxtQuery -Path:$uriPath -Timeout:$Timeout
} # function Invoke-NexthinkQuery

function Get-NexthinkFieldList
{
    <#
    .SYNOPSIS

    Get a list of fields available on a specific table.

    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    Param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        # The table from which to obtain the list of fields
        $Table,

        [Parameter()]
        [string]
        # Return fields available on the aggregate table. Must pass a linked
        # table in the Table parameter.
        $AggregateTable,

        [Parameter()]
        [ValidateSet('windows', 'mac_os', 'mobile')]
        [string]
        # The platform to query
        $Platform = 'windows',

        [Parameter()]
        [switch]
        # Return dynamic fields
        $DynamicField
    )

    Trap
    {
        throw $_
    }

    if ( [string]::IsNullOrEmpty($AggregateTable) )
    {
        if ( $DynamicField )
        {
            $query = '(select #* (from {0})(limit 1))' -f $Table
        }
        else
        {
            $query = '(select notavalidfieldname (from {0})(limit 1))' -f $Table
        }
    }
    else
    {
        $query = '(select * (from {0} (with {1} (compute notavalidfield)(between midnight-1d midnight)))' -f
            $Table,
            $AggregateTable
    }
    $uriPath = '/2/query?query='
    $uriPath += [Web.HttpUtility]::UrlEncode($query)
    $uriPath += '&format=json&platform={0}' -f $Platform

    $result = Invoke-PrivateNxtQuery -Path:$uriPath -ReturnErrorObject

    $result.Options
} # function Get-NexthinkFieldList
function Get-NexthinkEngine
{
    <#
    .SYNOPSIS

    Get a list of engines in the environment.

    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType([Object[]])]
    Param
    (
    )

    Trap
    {
        throw $_
    }

    $script:privNxtEngines
} # function Get-NexthinkEngine

function Get-NexthinkNxqlDataModel
{
    <#
    .SYNOPSIS

    Get the NXQL data model.

    .DESCRIPTION

    Parses the NXQL data model web page and returns a hashtable in the form:

        @{
            Objects =
            @{
                application =
                @{
                    company =
                    @{
                        type='string'
                        platform = 'windows', 'mac_os'
                    }
                    database_usage =
                    @{
                        type='permill'
                        platform = 'windows', 'mac_os'
                    }
                    ...
                }
                ...
            }
            ...
        }

    Relies on parsing the HTML documentation page for the NXQL data model, so as
    such will be fragile to formatting and other changes to the documentation.

    Uses a COM object to parse the HTML so will only work on Windows platforms.

    .LINK

    https://doc.nexthink.com/Documentation/Nexthink/latest/APIAndIntegrations/NXQLDataModel

    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType([Hashtable])]
    Param
    (
    )

    Trap
    {
        throw $_
    }

    if ( $PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -ne 'Win32NT' )
    {
        throw [NotSupportedException]::new('Not supported on non-Windows platforms')
    }

    # NXQL data types documentation web page
    $dataModelUri = 'https://doc.nexthink.com/Documentation/Nexthink/latest/APIAndIntegrations/NXQLDataModel'

    $html = New-Object -ComObject:'HTMLFile'
    if ( $PSVersionTable.PSEdition -eq 'Core' )
    {
        $content = (Invoke-WebRequest -Uri:$dataModelUri).Content
        $html.Write([ref]$content)
    }
    else
    {
        $content = (Invoke-WebRequest -Uri:$dataModelUri -UseBasicParsing).Content
        $html.IHTMLDocument2_write($content)
    }

    $data = @{}
    $class = @{}
    $table = @{}

    $body = $html.getElementById('page_body')
    $className = $newClassName = $null
    $tableName = $null
    foreach ( $node in $body.childNodes )
    {
        switch ( $node.tagName )
        {
            'h2'
            {
                $newClassName = $node.innerText.Trim()
            }
            'h3'
            {
                $tableName = $node.innerText.Trim()
            }
            'table'
            {
                if ( $node.className -eq 'wikitable' )
                {
                    if ( $newClassName -ne $className )
                    {
                        if ( [string]::IsNullOrWhiteSpace($className) -eq $false )
                        {
                            $data.$className = $class
                        }
                        $class = @{}
                        $className = $newClassName
                    }
                    $table = @{}
                    $rows = @($node.getElementsByTagName('tr'))
                    foreach ( $row in $rows )
                    {
                        $td = @($row.getElementsByTagName('td'))
                        if ( $td.Count -eq 6 )
                        {
                            $name, $type = $td[0..1].innerText
                            $plats = @()
                            switch -RegEx ( $td[2..4].innerHtml )
                            {
                                'Windows_black' { $plats += 'windows' }
                                'Mac black'     { $plats += 'mac_os'  }
                                'Mobile black'  { $plats += 'mobile'  }
                            }
                            $table.($name.Trim()) =
                            @{
                                type = $type.Trim()
                                platform = $plats
                            }
                        }
                    }
                    $class.$tableName = $table
                }
            }
        }
    }
    if ( $null -ne $className )
    {
        $data.$className = $class
    }
    $data
} # function Get-NexthinkNxqlDataModel

#endregion
#
#region Private helper functions
#
#
function Wait-PrivateAsyncTask
{
    <#
    .SYNOPSIS

    Wait for an asynchronous Threading.Tasks.Task to complete.

    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    Param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        $Task
    )

    Begin
    {
        $overallTimer = [System.Diagnostics.Stopwatch]::StartNew()
    }
    Process
    {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        while ( $Task.AsyncWaitHandle.WaitOne(500) -eq $false )
        {
            if ( $timer.Elapsed -gt [TimeSpan]::FromSeconds(60) )
            {
                $stack = @(Get-PSCallStack)
                if ( $stack.Count -gt 1 )
                {
                    $stack = @($stack[1])
                }
                $msg = 'Asynchronous task executing for {0}.' -f
                    $overallTimer.Elapsed.ToString(),
                    $stack[0].Location

                Write-Warning $msg
                $timer.Restart()
            }
        }
        $Task.GetAwaiter().GetResult()
    }
} # function Wait-PrivateAsyncTask

function Invoke-PrivateNxtQuery
{
    <#
    .SYNOPSIS

    Execute a API call to Nexthink.

    #>
    [CmdletBinding(SupportsShouldProcess = $false, ConfirmImpact = 'None')]
    [OutputType([Object[]])]
    Param
    (
        [Parameter()]
        [ValidateSet('Portal', 'Engines')]
        [string]
        $Against = 'Engines',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter()]
        [ValidateSet('GET')]
        [string]
        $Method = 'GET',

        [Parameter()]
        [TimeSpan]
        $Timeout = [TimeSpan]::FromSeconds(120),

        [Parameter()]
        [switch]
        $ReturnErrorObject
    )

    Trap
    {
        throw $_
    }

    if ( [string]::IsNullOrEmpty($script:privNxtPortal) -or $null -eq $script:privNxtCred )
    {
        throw 'Not connected to Nexthink. Please connect using Connect-Nexthink'
    }

    if ( $null -eq $script:privNxtHttpClient )
    {
        # Not ideal, this changes the entire app domain. .NET 4.5 allows better
        # handling. Need to keep this until all supported platforms are on v4.5
        # [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor
        #                                                 [Net.SecurityProtocolType]::Tls13 -bor
        #                                                 [Net.SecurityProtocolType]::Tls12 -bor
        #                                                 [Net.SecurityProtocolType]::Tls11
        $client = $script:privNxtHttpClient = [Net.Http.HttpClient]::new()
        # $client.DefaultRequestHeaders.Add('Content-Type', 'application/json')
        $client.DefaultRequestHeaders.Add(
            'Authorization',
            (
                'Basic ' + [Convert]::ToBase64String(
                    [Text.Encoding]::ASCII.GetBytes(
                        ($script:privNxtCred.UserName, $script:privNxtCred.GetNetworkCredential().Password -join ':')
                    )
                )
            )
        )
        $client.Timeout = $Timeout
    }
    $client = $script:privNxtHttpClient

    $reqs = @()
    switch ( $Against )
    {
        'Engines'
        {
            foreach ( $engine in $script:privNxtEngines )
            {
                $reqs += [Uri]::new([Uri]::new('https://{0}' -f $engine.address), $Path)
            }
        }
        'Portal'
        {
            $reqs += [Uri]::new([Uri]::new('https://{0}' -f $script:privNxtPortal), $Path)
        }
    }

    if ( $script:privNxtSkipCerts )
    {
        # Not ideal, this changes the entire app domain. .NET 4.5 allows better
        # handling. Need to keep this until all supported platforms are on v4.5
        Disable-PrivateSslVerification
    }

    $results = @()
    try
    {
        switch ( $Method )
        {
            'GET'
            {
                $tasks = @()
                foreach ( $req in $reqs )
                {
                    $tasks += $client.GetAsync($req)
                }
                :nextTask foreach ( $task in $tasks )
                {
                    $result = Wait-PrivateAsyncTask -Task:$task
                    $content = Wait-PrivateAsyncTask -Task:$result.Content.ReadAsStringAsync()

                    # Parse content: HTML
                    if ( $content -match '^\s*<html>' )
                    {
                        # HTML of some sort, see if it can be parsed.
                        $html = New-Object -ComObject 'HTMLFile'
                        try
                        {
                            if ( $PSVersionTable.PSEdition -eq 'Core' )
                            {
                                $html.Write([ref]$content)
                            }
                            else
                            {
                                $html.IHTMLDocument2_write($content)
                            }
                        }
                        catch
                        {
                            throw [InvalidOperationException]::new('Invalid HTML response', $_.Exception)
                        }
                        $errorMsg = $html.getElementById('error_message')
                        if ( $null -eq $errorMsg )
                        {
                            throw [InvalidOperationException]::new('Unexpected HTML response')
                        }
                        else
                        {
                            # Error with NXQL query
                            $errorMsg = $errorMsg.innerText
                            $errorOpts = $html.getElementById('error_options')
                            if ( $null -ne $errorOpts )
                            {
                                $errorOpts = $errorOpts.getElementsByTagName('li') |
                                    Select-Object -ExpandProperty:'innerText'
                            }
                        }
                        if ( $ReturnErrorObject )
                        {
                            [PSCustomObject]@{
                                'Error' = $errorMsg
                                'Options' = $errorOpts
                            }
                            return
                        }
                        else
                        {
                            throw [InvalidOperationException]::new($errorMsg)
                        }
                    }

                    # Parse content: JSON
                    try
                    {
                        $contentObj = $content | ConvertFrom-Json #-AsHashtable
                        $results += $contentObj
                        continue nextTask
                    }
                    catch
                    {
                        throw [InvalidOperationException]::new('Unexpected response', $_)
                    }
                }
            }
            default
            {
                $msg = 'Method {0} is not implemented' -f $Method
                throw [NotImplementedException]::new($msg)
            }
        }
    }
    finally
    {
        if ( $script:privNxtSkipCerts )
        {
            Enable-PrivateSslVerification
        }
    }

    $results
} # function Invoke-PrivateNxtQuery

function Disable-PrivateSslVerification
{
    if ( $null -eq ([Management.Automation.PSTypeName]'TrustAllCertificatesPolicy').Type )
    {
        Add-Type -TypeDefinition:'
            using System.Net.Security;
            using System.Security.Cryptography.X509Certificates;
            public static class TrustAllCertificatesPolicy
            {
                private static bool TrustingCallBack(object sender, X509Certificate certificate, X509Chain chain,
                                                        SslPolicyErrors sslPolicyErrors)
                {
                    return true;
                }
                public static void SetCallback()
                {
                    System.Net.ServicePointManager.ServerCertificateValidationCallback += TrustingCallBack;
                }
                public static void UnsetCallback()
                {
                    System.Net.ServicePointManager.ServerCertificateValidationCallback -= TrustingCallBack;
                }
            }'
    }
    [TrustAllCertificatesPolicy]::SetCallback()
} # function Disable-PrivateSslVerification

function Enable-PrivateSslVerification
{
    if ( $null -ne ([Management.Automation.PSTypeName]'TrustAllCertificatesPolicy').Type )
    {
        [TrustAllCertificatesPolicy]::UnsetCallback()
    }
} # function Enable-PrivateSslVerification

#endregion
#
#region Private variables
#
#
$script:privNxtPortal = $null
$script:privNxtEngines = @()
$script:privNxtEnginePort = $null
$script:privNxtCred = $null
$script:privNxtHttpClient = $null
$script:privNxtSkipCerts = $false
#endregion
#
#region Export members
#
#
#Requires -Version:5.0
Set-StrictMode -Version:5
$script:ErrorActionPreference = 'Stop'
Add-Type -AssemblyName:'System.Net.Http' # For [Net.Http.HttpClient]
Add-Type -AssemblyName:'System.Web' # For [Web.HttpUtility]::UrlEncode()

Export-ModuleMember -Function:'Connect-Nexthink'
Export-ModuleMember -Function:'Invoke-NexthinkQuery'
Export-ModuleMember -Function:'Get-NexthinkFieldList'
Export-ModuleMember -Function:'Get-NexthinkEngine'
Export-ModuleMember -Function:'Get-NexthinkNxqlDataModel'

#endregion
