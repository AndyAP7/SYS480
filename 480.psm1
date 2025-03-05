#Credits: Nick had helped me with some clarification as there were parts I was confused with. (Nick Rivera)


function 480Banner()
{
   $banner=@"
_  _    ___   ___              _   _ _    
| || |  ( _ ) / _ \       _   _| |_(_) |___
| || |_ / _ \| | | |_____| | | | __| | / __|
|__   _| (_) | |_| |_____| |_| | |_| | \__ \
  |_|  \___/ \___/       \__,_|\__|_|_|___/


"@
  Write-Host $banner
}
Function 480Connect([string] $server)
{
   $conn = $global:DefaultVIServer
   if ($conn){
       $msg = "Already Connected to: {0}" -f $conn


       Write-Host -ForegroundColor Green $msg
   } else
   {
       $conn = Connect-VIServer -Server $server
   }
}


Function Get-480Config([string] $config_path)
{
   $config=$null
   if (Test-Path $config_path)
   {
       $config = Get-Content -Raw -Path $config_path | ConvertFrom-Json
       $msg = "Using Configuration at {0}" -f $config_path
       Write-Host -ForegroundColor "Green" $msg
   } else
   {
       Write-Host -ForegroundColor "Yellow" "No Configuration"
   }
   return $config
}


Function ErrorHandling($index, $maxIndex)
{
   if ($index -ge 1 -and $index -le $maxIndex) {
       return $true
   }
   else {
       Write-Host "Invalid index. Please enter a valid index between 1 and $maxIndex" -ForegroundColor "Yellow"
       return $false
   }
}


Function Select-VM([string] $folder)
{
   Write-Host "Select your VM:"
   $selected_vm = $null
   try
   {
       $vms = Get-VM -Location $folder
       $index = 1


       if ($vms.Count -eq 0) {
           Write-Host "No VMs found in the specified folder." -ForegroundColor "Red"
           return $null
       }


       foreach ($vm in $vms)
       {
           Write-Host "[$index] $($vm.Name)"
           $index += 1
       }

       do
       {
           $pick_index = Read-Host "Please choose a VM"


           if ($pick_index -eq "") {
               Write-Host "Please enter a valid index." -ForegroundColor "Yellow"
               continue
           }


           if (ErrorHandling -index $pick_index -maxIndex $vms.Count)
           {
               $selected_vm = $vms[$pick_index - 1]
               Write-Host "You picked $($selected_vm.Name)"
           }
       } while (-not $selected_vm)

       return $selected_vm
   }
   catch
   {
       Write-Host "Invalid folder: $folder" -ForegroundColor "Red"
   }
}


Function Select-DB()
{
   Write-Host "Select your Datastore:"
   $chosen_db = $null


   $datastores = Get-Datastore
   $index = 1

   if ($datastores.Count -eq 0) {
       Write-Host "No Datastores found." -ForegroundColor "Red"
       return $null
   }


   foreach ($ds in $datastores) {
       Write-Host [$index] $ds.Name
       $index += 1
   }


   do {
       $choice = Read-Host "Please choose your datastore"
       if (ErrorHandling -index $choice -maxIndex $datastores.Count) {
           $chosen_db = $datastores[$choice - 1]
           Write-Host "You picked " $chosen_db.Name
       }
   } while ($chosen_db -eq $null)


   return $chosen_db
}
Function Select-Network([string] $esxi)
{
   $vmhost = Get-VMHost -Name $esxi
   Write-Host "Select your Network Adapter:"
   $chosen_net=$null
  
   $networks = $vmhost | Get-VirtualSwitch | Get-VirtualPortGroup
   $index=1


   if ($networks.Count -eq 0) {
       Write-Host "No VMs found in the specified folder." -ForegroundColor "Red"
       return $null
   }


   foreach($net in $networks)
   {
       Write-Host [$index] $net.Name
       $index+=1
   }


   do
   {
       $choice = Read-Host "Please choose a VM"
       if (ErrorHandling -index $choice -maxIndex $networks.Count){


           $chosen_net = $networks[$choice - 1].Name
           Write-Host "You picked:" $chosen_net
       }
   } while ($chosen_net -eq $null)
  
   return $chosen_net
}


Function FullClone([string] $vm, $snap, $vmhost, $ds, $network)
{
   $linkedName = "{0}.linked" -f $vm
   
   $linkedVM = New-VM -LinkedClone -Name $linkedName -VM $vm -ReferenceSnapshot $snap -VMHost $vmhost -Datastore $ds
   
   $newvmname = Read-Host -prompt "Enter the name for your New VM"
   
   $newVM = New-VM -Name $newvmname -VM $linkedVM -VMHost $vmhost -Datastore $ds
   
   $newVM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $network
   
   $newVM | New-Snapshot -Name "Base"
   
   $linkedVM | Remove-VM
   
   $powerOp = Read-Host "Would you like to power on" $newVM.Name "(Y/N)?"
   if ($powerOp -match "^[yY]$")
   {
       Start-VM -VM $newVM
       Write-Host $newVM.Name "has powered on!"
       return $newVM
   } else
   {
       return $newVM
   }
}


Function New-Network()
{
   $config = Get-480Config -config_path "/home/user/Documents/Github/SYS480/480.json"


   $vsName = Read-Host "Enter the name for your new Virtual Switch"
   $virtualSwitch = New-VirtualSwitch -VMHost $config.esxi_host -Name $vsName -Server $config.vcenter_server

   Write-Host "All Virtual Switches:"
   Get-VirtualSwitch | ForEach-Object { Write-Host $_.Name }


   $selectedSwitch = Read-Host "Enter the name of the Virtual Switch you want to use for creating a Port Group"


   $vsName = Get-VirtualSwitch -Name $selectedSwitch
   if ($vsName -eq $null) {
       Write-Host "Invalid Virtual Switch name. Please choose a valid Virtual Switch."
       return
   }

   $pgName = Read-Host "Enter the name for your new Port Group"
   $portGroup = New-VirtualPortGroup -VirtualSwitch $vsName -Name $pgName


   Write-Host "Virtual Switch: $($virtualSwitch.Name) and Port Group: $($portGroup.Name) have been created"

   $rmSwitch = Read-Host "Would you like to remove a Virtual Switch? (Y/N)"
   if ($rmSwitch -match "^[yY]$"){
       Get-VirtualSwitch | ForEach-Object { Write-Host $_.Name }
       $virSwitchChosen = Read-Host "Enter the name of the Virtual Switch you wish to remove"
       Remove-VirtualSwitch -VirtualSwitch $virSwitchChosen


       $rmPortGroup = Read-Host "Do you want to remove a virtual group? (Y/N)"
       if ($rmPortGroup -match "^[yY]$"){
           Get-VirtualPortGroup | ForEach-Object { Write-Host $_.Name }
           $virPGchosen = Read-Host "Enter the name of the group you want to remove"
           $portGroupToRemove = Get-VirtualPortGroup -Name $virPGchosen
           Remove-VirtualPortGroup -VirtualPortGroup $portGroupToRemove
       } elseif ($rmPortGroup -match "^[nN]$|^$"){
           Write-Host "No Virtual Port Group will be removed."
       } else {
           Write-Host "Invalid option for removing Virtual Port Group."
       }
   } elseif ($rmSwitch -match "^[nN]$|^$"){
       Write-Host "No Virtual Switch or Port Group will be removed."
   } else {
       Write-Host "Invalid option for removing Virtual Switch."
   }
   return $virtualSwitch
   return $portGroup
}


Function powerOn(){

   $vmList = Get-VM | Where-Object {$_.PowerState -eq "PoweredOff"}


   if ($vmList.Count -eq 0) {
       Write-Host "All VMs are Powered On or there are no VMs within your Inventory." -ForegroundColor "Red"
       return $null
   }


   for ($i = 0; $i -lt $vmList.Count; $i++)
   {
       Write-Host "[$($i + 1)] $($vmList[$i].Name)"
   }


   do{
       $choice = Read-Host "Which VM do you want to start? (Press 'Enter' for none)"
       if (ErrorHandling -index $choice -maxIndex $vmList.Count){


           $chosenVM = $vmList[$choice - 1].Name
           $powerOn = Start-VM -VM $chosenVM
           Write-Host "$($chosenVM.Name) has Powered On!"
       }
   } while ($chosenVM -eq $null)


   return $powerOn
}


Function powerOff(){
   $vmList = Get-VM | Where-Object {$_.PowerState -eq "PoweredOn"}


   if ($vmList.Count -eq 0) {
       Write-Host "All VMs are Powered Off or there are no VMs within your Inventory." -ForegroundColor "Red"
       return $null
   }


   for ($i = 0; $i -lt $vmList.Count; $i++)
   {
       Write-Host "[$($i + 1)] $($vmList[$i].Name)"
   }


   do {  
       $choice = Read-Host "Which VM do you want to stop? (Press 'Enter' for none)"
       if (ErrorHandling -index $choice -maxIndex $vmList.Count){


           $chosenVM = $vmList[$choice - 1].Name
           $powerOff = Stop-VM -VM $chosenVM
           Write-Host "$($chosenVM.Name) has Powered On!`n"
       }
   } while ($chosenVM -eq $null)


   return $powerOff
}


Function Get-IP($VM) {

   $config = Get-480Config -config_path "/home/user/Documents/Github/SYS480/480.json"
   480Connect -server $config.vcenter_server


   $vms = Get-VM -Name $VM


   foreach($vm in $vms){
       $mac=Get-NetworkAdapter -VM $vm | Select-Object -ExpandProperty MacAddress
       $ipaddr=$vm.Guest.IPAddress[0]
       $info="Name: $($VM)`nMAC Address: $($mac)`nIP Address: $($ipaddr)"
       Write-Host $info
   }
}


Function Set-Windows-IP($VM, $eth, $IP, $mask, $gate4, $nameserver) {

   $config = Get-480Config -config_path "/home/user/Documents/Github/SYS480/480.json"
   480Connect -server $config.vcenter_server
   
   $vm = Get-VM -Name $VM
   $Cred = Get-Credential -Message "Enter Username and Password for $vm"

   Invoke-VMScript -VM $vm -GuestCredential $Cred -ScriptText "netsh interface ipv4 set address name='$eth' static $IP $mask $gate4 "

   Invoke-VMScript -VM $vm -GuestCredential $Cred -ScriptText "netsh interface ipv4 add dns name='$eth' $nameserver index=1"
}










