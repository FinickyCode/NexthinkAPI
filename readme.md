# Overview

A PowerShell Cmdlet interface to the Nexthink API.

# APIs supported

* [Web API v2](https://doc.nexthink.com/Documentation/Nexthink/latest/APIAndIntegrations/IntroducingtheWebAPIV2)
* [List Engines API](https://doc.nexthink.com/Documentation/Nexthink/latest/APIAndIntegrations/ListEnginesAPI)

# Usage examples

```
> $nexthinkInstance = 'demo.pac.nexthink.cloud' # <- Put your instance/portal host here.
> $nexthinkCredential = Get-Credential -Message:'Account with API access to Nexthink'

> Connect-Nexthink -PortalHost:$nexthinkInstance -Credential:$nexthinkCredential

> Invoke-NexthinkQuery -Nxql:'(select (name platform last_seen) (from device)(limit 1))'

name         platform last_seen
----         -------- ---------
demodevice   windows  2020-12-24T20:22:56
```

# Cmdlets

| Cmdlet                    | Description                                         |
|---------------------------|-----------------------------------------------------|
| Connect-Nexthink          | Connect to Nexthink.                                |
| Invoke-NexthinkQuery      | Run a NXQL query against all engines.               |
| Get-NexthinkFieldList     | Get a list of fields available on a specific table. |
| Get-NexthinkEngine        | Get a list of engines in the environment.           |
| Get-NexthinkNxqlDataModel | Get the NXQL data model.                            |

# Requirements

PowerShell Desktop/Core 5 or later.
`Get-NexthinkNxqlDataModel` is only supported on Windows.
