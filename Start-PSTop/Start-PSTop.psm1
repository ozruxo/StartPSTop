<#
.SYNOPSIS
	Resource monitor with PowerShell.

.DESCRIPTION
    Resource monitor with PowerShell.

.PARAMETER Processes
    Enter the number of process's to be displayed.

.EXAMPLE
    Start-PSTop

.EXAMPLE
    Start-PSTop -Processes 20

.NOTES
    Get-Counter -ListSet
    Any improvements welcome.
#>

function Start-PSTop {

    param(
    [int]$Processes=10
    )

    #region FUNCTION

        function Set-Bar {
            
            param(
                [Int]$Percent,
                [Switch]$Memory,
                [Switch]$CPU
            )
            if($Percent -gt 1){
            
                $LineNumber = [Math]::Ceiling([int]$Percent/5)
            }
            else{
            
                $LineNumber = [Math]::Ceiling([Int]$Percent)
            }
                        
            $DrawLine = "|" * $LineNumber
            if ($LineNumber -ne 20){
            
                if($Memory){
                
                    $DrawDot  = "." * (20 - $LineNumber)
                }
                elseif($CPU){

                    $DrawDot = " " * (20 - $LineNumber)
                }
                else{

                    Write-Error "Error on bar"
                }
            }
            else{
            
                $DrawDot = $null
            }
        
            $DrawBar = $DrawLine + $DrawDot
        
            return $DrawBar
        }

        function Set-BarColor {

            param(
                [String]$Bar,
                [Switch]$CPU,
                [Switch]$Memory
            )

            if ($PSVersionTable.PSVersion.Major -ge 7){
                
                if ($CPU){
                    
                    $n=0
                    for($i=0;$i -lt 20;$i++){
                        
                        if ($Bar[$i] -eq '|'){
                            
                            $n++
                        }
                    }
                    $BarCount = $n
                    
                    switch($BarCount){

                        {$PSItem -le 10}{($PSStyle.Foreground.Green, $Bar, $PSStyle.Reset)}
                        {$PSItem -gt 10 -and $PSITem -le 15}{($PSStyle.Foreground.Green, ' ||||||||||', $PSStyle.Foreground.Yellow, ('|' * ($BarCount - 10)), $PSStyle.Reset -join "")}
                        {$PSItem -gt 15 -and $PSItem -le 20}{($PSStyle.Foreground.Green, ' ||||||||||', $PSStyle.Foreground.Yellow, '|||||', $PSStyle.Foreground.BrightRed, ('|' * ($BarCount - 15)), $PSStyle.Reset -join "")}
                    }
                }
                elseif($Memory){

                    $PSStyle.Foreground.BrightBlue, $Bar, $PSStyle.Reset -join ""
                }
                else{

                    Write-Error "Error on bar color"
                }
            }
            else{

                $Bar
            }
        }

    #endregion

    #region SCRIPT

    while(1){

        #region SET VARIABLES

            # Get default variables for cleanup at the end
            $DefaultVariables = $(Get-Variable).Name 
            
            #Network Activity
            #$Net = Get-Counter -ListSet 'Network Interface'
            
            $NetReceived = Get-Counter '\Network Interface(*)\Bytes Received/sec'
            $NetSent = Get-Counter '\Network Interface(*)\Bytes Sent/sec'
            $NetCount = $NetReceived.CounterSamples.cookedvalue.Count

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
            $ProcPercent = Get-Counter '\Processor(*)\% Processor Time'
            $ProcCount   = ($ProcPercent.CounterSamples.Count)-1

            #create a variable for each processor
            for ($i=0;$i -lt $ProcCount;$i++){
            
                New-Variable -Name "proc$i" -Value (($ProcPercent.CounterSamples | Where-Object {$_.path -match "processor\($i\)"}).cookedValue)
                $InProcSwitch = [Math]::Round((Get-Variable -Name "proc$i" -ValueOnly))
                New-Variable -Name "BarProc$i" -Value (Set-BarColor -Bar (Set-Bar -Percent $InProcSwitch -CPU) -CPU)
            }

            # Memory information
            # $MemSample      = Get-Counter -ListSet Memory #| ? {$_.countersetname -match "^memory$"}
            $MemAvail       = Get-Counter '\Memory\Available MBytes'
            #$MemCommit      = Get-Counter '\Memory\Committed Bytes'
            $MemPercent     = Get-Counter '\Memory\% Committed Bytes In Use'
            $MemCommitLimit = Get-Counter '\memory\commit limit'

            if($MemAvail){
                $AvailableMemory = $MemAvail.CounterSamples.CookedValue
                $MemLimit  = [Math]::Round($MemCommitLimit.CounterSamples.CookedValue / 1GB)
                $InMemSwitch = [Math]::Round($MemPercent.CounterSamples.cookedvalue)
                $BarMem = Set-BarColor -Bar(Set-Bar -Percent $InMemSwitch -Memory) -Memory
            }

            # C:\ drive stats
            $FreeSpace  = [Math]::Round(((Get-PSDrive C).Free)/1GB,2)
            $TotalSpace = [Math]::Round(((Get-PSDrive C).Free)/1GB+((Get-PSDrive c).Used)/1GB,2)
            $CDriveFriendlyName = (Get-PhysicalDisk | Where-Object {$_.DeviceID -eq 0}).FriendlyName

            # Task Information sort by CPU Process
            $tasks = Get-Process | Sort-Object -Descending CPU | Select-Object -First $Processes

        #endregion
    
        # Needed to "refresh" shell 
        Clear-Host

        #region PRINT
           
            Write-Host "PSTop 1.0  PSVersion: $($PSVersionTable.PSVersion)  User: $env:USERNAME"
            Write-Host "`0"

            # Maths for CPU bars
            $LeftNums  = [System.Collections.ArrayList]::New()
            $RightNums = [System.Collections.ArrayList]::New()
            $LeftTotalBarNumbers = [Math]::Ceiling($ProcCount / 2)
            for($LBN=0; $LBN -lt $LeftTotalBarNumbers; $LBN++){

                $LeftNums.Add($LBN) | Out-Null
            }
            
            $RightStartNumber = [Math]::Ceiling($ProcCount / 2)
            $RightTotalBarNumbers =  [Math]::Floor($ProcCount - $ProcCount / 2)
            for($RBN=$RightStartNumber; $RBN -lt $ProcCount; $RBN++){
            
                $RightNums.Add($RBN) | Out-Null
            }

            # Print CPU bars
            if (($ProcCount % 2) -ne 0){

                $LoopUntil = 0
                do{
                    for($P=0; $P -lt ([Math]::Floor($ProcCount/2)) ; $P++){

                        Write-Host "Proc $($LeftNums[$P])    : $(Get-Variable -Name "BarProc$($LeftNums[$P])" -ValueOnly)`tProc $($RightNums[$P])    : $(Get-Variable -Name "BarProc$($RightNums[$P])" -ValueOnly -ErrorAction SilentlyContinue)"
                        
                    }
                }until($LoopUntil -lt $RightTotalBarNumbers)
                Write-Host "Proc $($LeftNums[$P])    : $(Get-Variable -Name "BarProc$($LeftNums[$P])" -ValueOnly)"
            }
            else{
                
                for($P=0; $P -lt ($ProcCount/2) ; $P++){

                    Write-Host "Proc $($LeftNums[$P])    : $(Get-Variable -Name "BarProc$($LeftNums[$P])" -ValueOnly)`tProc $($RightNums[$P])    : $(Get-Variable -Name "BarProc$($RightNums[$P])" -ValueOnly -ErrorAction SilentlyContinue)"
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
            $tasks

        #endregion
    
        # Allows for recreating variables
        ((Compare-Object -ReferenceObject (Get-Variable).Name -DifferenceObject $DefaultVariables).InputObject).foreach{Remove-Variable -Name $_ -ErrorAction SilentlyContinue}

    }
    #endregion
}
