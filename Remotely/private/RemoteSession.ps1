function CopyStreams
{
    param
    (
        [Parameter(Position=0, Mandatory=$true)] 
        $inputStream
    ) 

    $outStream = New-Object 'System.Management.Automation.PSDataCollection[PSObject]'

    foreach($item in $inputStream)
    {
        $outStream.Add($item)
    }

    $outStream.Complete()

    ,$outStream
}

function AddArgumentListtoSessionVars {
	[CmdletBinding()]
	param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()] $session
    )
	$InvokeCommandParams= @{
		Scriptblock={
						if ($PSSenderInfo.ApplicationArguments.Keys -ne 'PSVersionTable')  {
							# there are arguments passed to the session other than PSversionTable, add them to the current session
							$PSSenderInfo.ApplicationArguments.Keys -ne 'PSversionTable' |
								Foreach-Object -Process {
									New-Variable -Name $PSitem -Value  $PSSenderInfo.ApplicationArguments[$PSitem]
								}
						}
					};
		Session = $session;
		ErroAction = 'Stop';
	}
	Invoke-Command 	@InvokeCommandParams
}

function CreateSessions
{
	[CmdletBinding(DefaultParameterSetName='Computername')]
    param
    (
        [Parameter(Mandatory, ParameterSetName='ComputerName')]
        [string[]] $Nodes,

        [Parameter()]
        $CredentialHash,

		[Parameter()]
		[hashtable]$ArgumentList,

		[Parameter(ParameterSetName='ConfigurationData')]
		[HashTable]$ConfigData
    )
	if ($argumenList) {
		$PSSessionOption = New-PSSessionOption -ApplicationArguments $ArgumentList  -NoMachineProfile         
	}
	else {
		$PSSessionOption = New-PSSessionOption  -NoMachineProfile 
	}
	Switch -Exact ($PSCmdlet.ParameterSetName) {
		'ComputerName' {
			
			foreach($Node in $Nodes)
			{ 
				if(-not $script:sessionsHashTable.ContainsKey($Node))
				{                                   
					$sessionName = "Remotely-" + $Node                              
					if ($CredentialHash -and $CredentialHash[$Node])
					{
						$sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $Node -Name $sessionName -Credential $CredentialHash[$node] -SessionOption $PSSessionOption) -Credential $CredentialHash[$node]
					}
					else
					{
						$sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $Node -Name $sessionName -SessionOption $PSSessionOption)  
					}
					$script:sessionsHashTable.Add($sessionInfo.session.ComputerName, $sessionInfo)              
				}               
			}
			break
		}
		'ConfigurationData' {
			foreach ($node in $ConfigData.AllNodes) {
				$ArgumentList.Add('Node',$node) # Add this as an argument list, so that it is availabe as $Node in remote session
				if(-not $script:sessionsHashTable.ContainsKey($Node.NodeName))
				{                                   
					$sessionName = "Remotely-" + $Node.NodeName                              
					if ($CredentialHash -and $CredentialHash[$Node.NodeName])
					{
						$sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $Node.NodeName -Name $sessionName -Credential $CredentialHash[$node] -SessionOption $PSSessionOption) -Credential $CredentialHash[$node]
					}
					else
					{
						$sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $Node.NodeName -Name $sessionName -SessionOption $PSSessionOption)  
					}
					$script:sessionsHashTable.Add($sessionInfo.session.ComputerName, $sessionInfo)              
				}
			}
			break
		}
	}
    
}

function CreateLocalSession
{    
    param(
        [Parameter(Position=0)] $Node = 'localhost'
    )

    if(-not $script:sessionsHashTable.ContainsKey($Node))
    {
        $sessionInfo = CreateSessionInfo -Session (New-PSSession -ComputerName $Node -Name $sessionName)
        $script:sessionsHashTable.Add($Node, $sessionInfo)
    } 
}

function CreateSessionInfo
{
    param(
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Position=1)]
        [pscredential] $Credential
    )
    return [PSCustomObject] @{ Session = $Session; Credential = $Credential}
}

function CheckAndReconnect
{
    param
    (
        [Parameter(Position=0, Mandatory=$true)]
        [ValidateNotNullOrEmpty()] $sessionInfo
    )

    if($sessionInfo.Session.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened)
    {
        Write-Verbose "Unexpected session state: $sessionInfo.Session.State for machine $($sessionInfo.Session.ComputerName). Re-creating session" 
        if($sessionInfo.Session.ComputerName -ne 'localhost')
        {
            if ($sessionInfo.Credential)
            {
                $sessionInfo.Session = New-PSSession -ComputerName $sessionInfo.Session.ComputerName -Credential $sessionInfo.Credential
            }
            else
            {
                $sessionInfo.Session = New-PSSession -ComputerName $sessionInfo.Session.ComputerName
            }
        }
        else
        {
            $sessionInfo.Session = New-PSSession -ComputerName 'localhost'
        }
    }
}