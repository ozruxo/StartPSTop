<#
.SYNOPSIS
Resource monitor with PowerShell.

.DESCRIPTION
Resource monitor with PowerShell.

.PARAMETER Processes
Enter the number of process's to be displayed.

.PARAMETER NoPrint
Specify to not print anything to screen/terminal. Designed to be paired with the Log parameter.

.PARAMETER Log
Allows for logging the counters for processor, memory, and networking.

.PARAMETER LogDirectory
Specify a different location for the logging directory. Default will be C:\Logs\PSTop.

.PARAMETER KeepLogsDays
Specify when this script should clean up old logs. Default duration is 7 days. So if you have logs that are older than 7 days and it's been a while since you ran this. They will be deleted, when running the Log parameter.

.EXAMPLE
Start-PSTop

.EXAMPLE
Start-PSTop -Processes 20

.EXAMPLE
Start-PSTop -NoPrint -Log

.NOTES
Get-Counter -ListSet
Any improvements welcome.
#>

function Start-PSTop {

    [CmdletBinding()]
    param(
        [Int]$Processes=8,
        [Switch]$NoPrint,
        [Switch]$Log,
        [String]$LogDirectory='C:\Logs\PSTop',
        [Int]$KeepLogsDays=7
    )

    #region INITIAL SETUP

        $DateTime     = Get-Date -Format yyyy-MM-dd-hh-mm-ss
        $LogFileName  = "$DateTime-TopUsage.log"
        $X = 0

    #endregion

    #region FUNCTIONS

        function Get-LiveUserCount {

            $sessions = cmd /c "query session"
            $i = 0
            foreach ($Line in $sessions){

                if($Line -match 'SESSIONNAME'){

                    continue
                }

                elseif($Line -match 'Services'){

                    continue
                }
                # This is not accounting for remote session such as powershell
                elseif($Line -match 'Console' -and $Line -match 'Active'){

                    $Trim = (($Line -split '\s+')[1]).Trim()
                    $Users.Add($Trim) | Out-Null
                    $i++
                    continue
                }
                elseif($Line -match 'Console' -and $Line -notmatch 'Active'){

                    continue
                }
                elseif($Line -match '65536'){

                    continue

                }
                elseif($Line -match '65537'){

                    continue
                }
                else{

                    $i++
                    $Trim = (($Line -split '\s+')[1]).Trim()
                    $Users.Add($Trim) | Out-Null
                }
            }

            return $i, $Users
        }

        function Invoke-Directory {

            param(
                [String]$Path
            )

            if(!(Test-Path -Path $Path)){

                Write-Verbose "Creating directory $Path"
                New-Item -Path $Path -ItemType Directory
            }
        }

        function Invoke-Logging {

            param(
            [String]$Infor,
            [String]$Warni,
            [String]$Broke,
            [Switch]$Clean
            )

            if(-not(Test-Path $LogDirectory)){

                New-Item -Path $LogDirectory -ItemType Directory
            }

            # Date and time for logging
            $LogDateTime = Get-Date -Format FileDateTime
            # Default cleanup for logs
            $DaysOldLogs = (Get-Date).AddDays(-$KeepLogsDays)
            # Parameter used
            $Keys     = $PSBoundParameters.Keys
            # Value of parameter
            $Values   = $PSBoundParameters.Values

            if ($keys -match "Infor|Warni|Broke"){

                Add-Content -Value "[ $Keys ] $LogDateTime $Values" -Path "$LogDirectory\$LogFileName"
            }
            elseif($Clean){

                Write-Verbose "Checking for any files to clean up"
                $Logs = Get-ChildItem $LogDirectory
                foreach ($Log in $Logs){

                    if($Log.CreationTime -lt $DaysOldLogs){

                        Write-Verbose "Removing file $($Log.Fullname)"
                        Remove-Item $Log.Fullname
                    }
                }
            }
            else{

                Write-Host "Parameter not specified"
            }
        }

        function Set-BarColor {

            param(
                [Switch]$CPU,
                [Switch]$Memory,
                [Int]$Percent
            )

            if($Percent -gt 1){

                $BarCount = [Math]::Ceiling([int]$Percent/5)
            }
            else{

                $BarCount = [Math]::Ceiling([Int]$Percent)
            }
            if ($CPU){

                if($BarCount -gt 15){

                    $DrawSpace = " " * (20 - $BarCount)
                    return "$($PSStyle.Foreground.Green)||||||||||$($PSStyle.Foreground.Yellow)|||||$($PSStyle.Foreground.BrightRed)$('|' * ($BarCount - 15))$($PSStyle.Reset)$DrawSpace" -join ""
                }
                elseif($BarCount -gt 10){

                    $DrawSpace = " " * (20 - $BarCount)
                    return "$($PSStyle.Foreground.Green)||||||||||$($PSStyle.Foreground.Yellow)$('|' * ($BarCount - 10))$($PSStyle.Reset)$DrawSpace" -join ""
                }
                else{

                    $Bar = '|' * $BarCount
                    $DrawSpace = " " * (20 - $BarCount)
                    return "$($PSStyle.Foreground.Green)$Bar$($PSStyle.Reset)$DrawSpace"
                }
            }
            elseif($Memory){

                $DrawLine = "|" * $BarCount
                if ($BarCount -ne 20){

                    $DrawDot  = "." * (20 - $BarCount)
                    $Bar = $DrawLine + $DrawDot
                }
                return "$($PSStyle.Foreground.BrightBlue)$Bar$($PSStyle.Reset)" -join ""
            }
            else{

                return "Error on bar color"
            }
        }

    #endregion

    #region SCRIPT

    while($X -ne 1){

        #region SET VARIABLES

            # Reset
            $Users = [System.Collections.Generic.HashSet[String]]@()
            # Parallelize setting variables
            $Object = @{
                "Properties" = @(
                    @{
                        "VariableName" = "NetReceived"
                        "String"       = '\Network Interface(*)\Bytes Received/sec'
                    },
                    @{
                        "VariableName" = 'NetSent'
                        "String"       = '\Network Interface(*)\Bytes Sent/sec'
                    },
                    @{
                        "VariableName" = 'ProcPercent'
                        "String"       = '\Processor(*)\% Processor Time'
                    },
                    @{
                        "VariableName" = 'MemAvail'
                        "String"       = '\Memory\Available MBytes'
                    },
                    @{
                        "VariableName" = 'MemPercent'
                        "String"       = '\Memory\% Committed Bytes In Use'
                    },
                    @{
                        "VariableName" = 'MemCommitLimit'
                        "String"       = '\memory\commit limit'
                    }
                )
            }

            #Seems to be working, don't think its technically thread safe. Could error.
            #https://learn.microsoft.com/en-us/dotnet/api/system.collections.concurrent?view=net-10.0
            $Object.Properties | ForEach-Object -ThrottleLimit 6 -Parallel {

                $PSItem['Result'] = Get-Counter $PSItem.String
            }

            foreach($Property in $Object.Properties){

                Set-Variable -Name $Property.VariableName -Value $Property.Result
            }

            # Quite the function with the letter q
            if($Host.UI.RawUI.KeyAvailable -and ("q" -eq $Host.UI.RawUI.ReadKey("IncludeKeyup,NoEcho").Character)) {
                break
            }

            # Get default variables for cleanup at the end
            $DefaultVariables = $(Get-Variable).Name

            #Network Activity
            #$Net = Get-Counter -ListSet 'Network Interface'
            $NetCount    = $NetReceived.CounterSamples.cookedvalue.Count
            # If there are multiple NIC's
            if ($NetCount -ge 2){

                # Received
                $AddNR = $NetReceived.CounterSamples.CookedValue
                $NR = $AddNR[0]

                for($i=1;$i-lt$NetCount;$i++){

                    $NR = $NR + $AddNR[$i]
                }
                $NReceived = [int]$NR*1024/1KB

                # Sent
                $AddNS = $NetSent.CounterSamples.CookedValue
                $NS = $AddNS[0]

                for($i=1;$i-lt$NetCount;$i++){

                    $NS = $NS + $AddNS[$i]
                }
                $NSent = [int]$NS*1024/1KB

            }
            else{

                $NR = $NetReceived.CounterSamples.cookedvalue | Where-Object {$_ -gt 0}
                $NS = $NetSent.CounterSamples.cookedvalue | Where-Object {$_ -gt 0}
            }

            if($NetReceived){

                $NReceived = [int]$NR*1024/1KB
                $NSent     = [int]$NS*1024/1KB
            }

            # Idividual Processor information
            #$ProcessorSample = Get-Counter -ListSet Processor #| ? {$_.countersetname -match "^Processor$"}
            $ProcCount   = ($ProcPercent.CounterSamples.Count)-1

            #create a variable for each processor
            for ($i=0;$i -lt $ProcCount;$i++){

                New-Variable -Name "proc$i" -Value (($ProcPercent.CounterSamples | Where-Object {$_.path -match "processor\($i\)"}).cookedValue)
                $InProcRoundPercent      = [Math]::Round((Get-Variable -Name "proc$i" -ValueOnly))
                New-Variable -Name "BarProc$i" -Value (Set-BarColor -CPU -Percent $InProcRoundPercent)
            }

            # Memory
            if($MemAvail){
                $AvailableMemory         = $MemAvail.CounterSamples.CookedValue
                $MemLimit                = [Math]::Round($MemCommitLimit.CounterSamples.CookedValue / 1GB)
                $InMemSwitch             = [Math]::Round($MemPercent.CounterSamples.cookedvalue)
                $BarMem                  = Set-BarColor -Memory -Percent $InMemSwitch
            }

            # C:\ drive stats
            $FreeSpace          = [Math]::Round(((Get-PSDrive C).Free)/1GB,2)
            $TotalSpace         = [Math]::Round(((Get-PSDrive C).Free)/1GB+((Get-PSDrive c).Used)/1GB,2)
            $CDriveFriendlyName = (Get-PhysicalDisk | Where-Object {$_.DeviceID -eq 0}).FriendlyName

            # Task Information sort by CPU Process
            $Tasks = Get-Process | Sort-Object -Descending CPU | Select-Object -First $Processes | Format-Table -HideTableHeaders

            $UserSessionCount, $Users = Get-LiveUserCount
            if($Null -eq $Users){$Users = '-'}

        #endregion

        #region PRINT

        if(-not $NoPrint){

            # Needed to "refresh" shell
            Clear-Host

            Write-Host "PSTop 2.0  PSVersion: $($PSVersionTable.PSVersion)  User: $env:USERNAME Users Sessions: $UserSessionCount"
            Write-Host "Users: $([String]::Join(' ', $Users))"
            Write-Host "`0"

            # Maths for CPU bars
            $LeftNums            = [System.Collections.ArrayList]::New()
            $RightNums           = [System.Collections.ArrayList]::New()
            $LeftTotalBarNumbers = [Math]::Ceiling($ProcCount / 2)
            for($LBN=0; $LBN -lt $LeftTotalBarNumbers; $LBN++){

                $LeftNums.Add($LBN) | Out-Null
            }

            $RightStartNumber     = [Math]::Ceiling($ProcCount / 2)
            $RightTotalBarNumbers = [Math]::Floor($ProcCount - $ProcCount / 2)
            for($RBN=$RightStartNumber; $RBN -lt $ProcCount; $RBN++){

                $RightNums.Add($RBN) | Out-Null
            }

            # Print CPU bars
            if (($ProcCount % 2) -ne 0){

                $LoopUntil = 0
                do{
                    for($P=0; $P -lt ([Math]::Floor($ProcCount/2)) ; $P++){

                        Write-Host "Proc $($LeftNums[$P]) : $(Get-Variable -Name "BarProc$($LeftNums[$P])" -ValueOnly) Proc $($RightNums[$P]) : $(Get-Variable -Name "BarProc$($RightNums[$P])" -ValueOnly -ErrorAction SilentlyContinue)"
                    }
                }until($LoopUntil -lt $RightTotalBarNumbers)
                #Write-Host "Proc $($LeftNums[$P])    : $(Get-Variable -Name "BarProc$($LeftNums[$P])" -ValueOnly)"
            }
            else{

                for($P=0; $P -lt ($ProcCount/2) ; $P++){

                    Write-Host "Proc $($LeftNums[$P]) : $(Get-Variable -Name "BarProc$($LeftNums[$P])" -ValueOnly) Proc $($RightNums[$P]) : $(Get-Variable -Name "BarProc$($RightNums[$P])" -ValueOnly -ErrorAction SilentlyContinue)"
                }
            }

            Write-Host "`0"
            Write-Host "RAM Usage : $BarMem Percent: $InMemSwitch%"
            Write-Host "`0"

            if ($PSVersionTable.PSVersion.Major -ge 7){

                Write-Host ('Network S :',$PSStyle.Foreground.BrightWhite," $NSent", $PSStyle.Reset, ' KB' -join "")
                Write-Host ('Network R :',$PSStyle.Foreground.BrightWhite," $NReceived", $PSStyle.Reset, ' KB' -join "")
            }
            else{

                Write-Host "Network S : $NReceived KB"
                Write-Host "Network R : $NReceived KB"
            }
            Write-Host "Memory    : Available: $AvailableMemory MB Commit Limit: $MemLimit GB"
            Write-Host "Storage   : $CDriveFriendlyName"
            Write-Host "        C : $FreeSpace GB  \ $TotalSpace GB"
            Write-Host "`0"
            Write-Host "NPM(K)    PM(M)      WS(M)     CPU(s)      Id  SI ProcessName"
            Write-Host "------    -----      -----     ------      --  -- -----------"
            $Tasks
        }
        else{$X = 1}

        #endregion

        #region LOG

            if($Log){

                Invoke-Directory -Path $LogDirectory
                Invoke-Logging -Infor "Logging all data as Json"

                $RenameLogFileName = $LogFileName -replace '.log','.json'
                Set-Content -Value ($NetReceived | ConvertTo-Json) -Path "$LogDirectory\NetR-$RenameLogFileName"
                Set-Content -Value ($NetSent | ConvertTo-Json) -Path "$LogDirectory\NetS-$RenameLogFileName"
                Set-Content -Value ($ProcPercent | ConvertTo-Json) -Path "$LogDirectory\Proc-$RenameLogFileName"
                Set-Content -Value ($MemAvail | ConvertTo-Json) -Path "$LogDirectory\MemA-$RenameLogFileName"
                Set-Content -Value ($MemPercent | ConvertTo-Json) -Path "$LogDirectory\MemP-$RenameLogFileName"
                Set-Content -Value ($MemCommitLimit | ConvertTo-Json) -Path "$LogDirectory\MemC-$RenameLogFileName"

                Invoke-Logging -Warni "Checking if logs need to be removed"
                Invoke-Logging -Clean
            }

        #endregion

        # Allows for recreating variables
        ((Compare-Object -ReferenceObject (Get-Variable).Name -DifferenceObject $DefaultVariables).InputObject).foreach{Remove-Variable -Name $_ -ErrorAction SilentlyContinue}

    }
    #endregion
}
