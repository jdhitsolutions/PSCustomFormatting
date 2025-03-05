#requires -version 7.2
Function Get-ServerStatus {
    [cmdletbinding(DefaultParameterSetName = 'name')]
    [OutputType('ServerStatus')]
    [alias("gst")]
    Param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            HelpMessage = 'Enter the name of a computer',
            ParameterSetName = 'name')
        ]
        [ValidateNotNullOrEmpty()]
        [string]$Computername = $env:computername,
        [Parameter(ParameterSetName = 'name')]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = 'Session', ValueFromPipeline)]
        [CimSession]$CimSession,
        [Parameter(HelpMessage = "Format values as [INT]")]
        [switch]$AsInt
    )

    Begin {
        Write-Verbose "[$((Get-Date).TimeOfDay)] Starting $($MyInvocation.MyCommand)"
    } #begin

    Process {
        Write-Verbose "[$((Get-Date).TimeOfDay)] Using parameter set $($PSCmdlet.ParameterSetName)"

        $sessParams = @{
            ErrorAction  = 'stop'
            computername = $null
        }
        $cimParams = @{
            ErrorAction = 'stop'
            classname   = $null
        }

        if ($PSCmdlet.ParameterSetName -eq 'name') {
            #create a temporary CimSession
            $sessParams.Computername = $Computername
            if ($Credential) {
                $sessParams.Credential = $credential
            }
            #if localhost use DCOM - it will be faster to create the session
            if ($Computername -eq $env:computername) {
                Write-Verbose "[$((Get-Date).TimeOfDay)] Creating a local session using DCOM"
                $sessParams.Add("SessionOption", (New-CimSessionOption -Protocol DCOM))
            }
            Try {
                Write-Verbose "[$((Get-Date).TimeOfDay)] $computername"
                $CimSession = New-CimSession @sessParams
                $tempSession = $True
            }
            catch {
                Write-Error $_
                #bail out
                return
            }
        }

        if ($CimSession) {
            $hash = [ordered]@{
                PSTypename   = "ServerStatus"
                Computername = $CimSession.computername.toUpper()
            }
            Try {
                $cimParams.classname = 'Win32_OperatingSystem'
                $cimParams.CimSession = $CimSession
                Write-Verbose "[$((Get-Date).TimeOfDay)] Using class $($cimParams.classname)"
                $OS = Get-CimInstance @cimParams
                $uptime = (Get-Date) - $OS.lastBootUpTime
                $hash.Add("Uptime", $uptime)

                $pctFreeMem = [math]::Round(($os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 2)
                if ($AsInt) {
                    $pctFreeMem = $pctFreeMem -as [int]
                }
                $hash.Add("PctFreeMem", $pctFreeMem)

                $cimParams.classname = 'Win32_Logicaldisk'
                $cimParams.filter = "deviceid='C:'"

                Write-Verbose "[$((Get-Date).TimeOfDay)] Using class $($cimParams.classname)"
                Get-CimInstance @cimParams | ForEach-Object {
                    $name = "PctFree{0}" -f $_.deviceid.substring(0, 1)
                    $pctFree = [math]::Round(($_.FreeSpace / $_.size) * 100, 2)
                    if ($AsInt) {
                        $pctFree = $pctFree -as [int]
                    }
                    $hash.add($name, $pctFree)
                }

                New-Object PSObject -Property $hash
            }
            catch {
                Write-Error $_
            }

            #only remove the CimSession if it was created in this function
            if ($tempSession) {
                Write-Verbose "[$((Get-Date).TimeOfDay)] Removing temporary CimSession"
                Remove-CimSession -CimSession $CimSession
            }
        } #if CimSession
    } #process

    End {
        Write-Verbose "[$((Get-Date).TimeOfDay)] Ending $($MyInvocation.MyCommand)"
    } #end
} #close function

# Type Extensions$s
<#
Update-TypeData -TypeName ServerStatus -MemberType NoteProperty -MemberName Audit -Value (Get-Date) -Force
Update-TypeData -TypeName ServerStatus -MemberType AliasProperty -MemberName Name -Value Computername -Force
Update-TypeData -TypeName ServerStatus -MemberType ScriptMethod -MemberName Ping -Value {
    Test-Connection -TargetName $this.Computername -IPv4
} -Force
#>

# Update-FormatData $PSScriptRoot\serverstatus.format.ps1xml