#load Vmware Module
Add-PSSnapin VMware.VimAutomation.Core

#Change to multi-mode vcenter management
Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false

#Get vCenter Server Names
$sourceVI = Read-Host "Please enter the name of the source Server"; 
$destVI = Read-Host "Please enter the name of the destination Server"

$creds = get-credential

$datacenter = Read-Host "Please give the name of the datacenter you would like to run against"


#Connect to Source vCenter
connect-viserver -server $sourceVI -credential $creds
connect-viserver -server $destVI -credential $creds -NotDefault:$false


filter Get-FolderPath {
    $_ | Get-View | % {
        $row = "" | select Name, Path
        $row.Name = $_.Name

        $current = Get-View $_.Parent
        $path = $_.Name
        do {
            $parent = $current
            if($parent.Name -ne "vm"){$path = $parent.Name + "\" + $path}
            $current = Get-View $current.Parent
        } while ($current.Parent -ne $null)
        $row.Path = $path
        $row
    }
}

## Export all folders
$report = @()
$report = get-datacenter $datacenter -Server $sourceVI| Get-folder vm | get-folder | Get-Folderpath
        ##Replace the top level with vm
        foreach ($line in $report) {
        $line.Path = ($line.Path).Replace($datacenter + "\","vm\")
        }
$report | Export-Csv "c:\Folders-with-FolderPath-$($datacenter).csv" -NoTypeInformation

##Export all VM locations
$report = @()
$report = get-datacenter $datacenter -Server $sourceVI| get-vm | Get-Folderpath

$report | Export-Csv "c:\vms-with-FolderPath-$($datacenter).csv" -NoTypeInformation


#Get the Permissions  

$folderperms = get-datacenter $datacenter -Server $sourceVI | Get-Folder | Get-VIPermission
$vmperms = Get-Datacenter $datacenter -Server $sourceVI | get-vm | Get-VIPermission

$permissions = get-datacenter $datacenter -Server $sourceVI | Get-VIpermission
        
        $report = @()
              foreach($perm in $permissions){
                $row = "" | select EntityId, FolderName, Role, Principal, IsGroup, Propagate
                $row.EntityId = $perm.EntityId
                $Foldername = (Get-View -id $perm.EntityId).Name
                $row.FolderName = $foldername
                $row.Principal = $perm.Principal
                $row.Role = $perm.Role
                $row.IsGroup = $perm.IsGroup
                $row.Propagate = $perm.Propagate
                $report += $row
            }
    
            foreach($perm in $folderperms){
                $row = "" | select EntityId, FolderName, Role, Principal, IsGroup, Propagate
                $row.EntityId = $perm.EntityId
                $Foldername = (Get-View -id $perm.EntityId).Name
                $row.FolderName = $foldername
                $row.Principal = $perm.Principal
                $row.Role = $perm.Role
                $row.IsGroup = $perm.IsGroup
                $row.Propagate = $perm.Propagate
                $report += $row
            }

            foreach($perm in $vmerms){
                $row = "" | select EntityId, FolderName, Role, Principal, IsGroup, Propagate
                $row.EntityId = $perm.EntityId
                $Foldername = (Get-View -id $perm.EntityId).Name
                $row.FolderName = $foldername
                $row.Principal = $perm.Principal
                $row.Role = $perm.Role
                $row.IsGroup = $perm.IsGroup
                $row.Propagate = $perm.Propagate
                $report += $row
            }

        $report | export-csv "c:\perms-$($datacenter).csv" -NoTypeInformation

##Export VM Custom Attributes and notes

$vmlist = get-datacenter $datacenter -Server $sourceVI| get-vm 
$Report =@()
    foreach ($vm in $vmlist) {
        $row = "" | Select Name, Notes, Key, Value, Key1, Value1
        $row.name = $vm.Name
        $row.Notes = $vm | select -ExpandProperty Notes
        $customattribs = $vm | select -ExpandProperty CustomFields
        $row.Key = $customattribs[0].Key
        $row.Value = $customattribs[0].value
        $row.Key1 = $customattribs[1].Key
        $row.Value1 = $customattribs[1].value    
        $Report += $row
    }

$report | Export-Csv "c:\vms-with-notes-and-attributes-$($datacenter).csv" -NoTypeInformation
   
    
##Disconnect-VIServer -Server $sourceVI -force -confirm:$false


#connect to Destination Server
##connect-viserver -server $destVI -credential $creds -confirm:$false


##IMPORT FOLDERS
$vmfolder = Import-Csv "c:\Folders-with-FolderPath-$($datacenter).csv" | Sort-Object -Property Path

foreach($folder in $VMfolder){
    $key = @()
    $key =  ($folder.Path -split "\\")[-2]
    if ($key -eq "vm") {
        get-datacenter $datacenter -Server $destVI | get-folder vm | New-Folder -Name $folder.Name
        } else {
        get-datacenter $datacenter -Server $destVI | get-folder vm | get-folder $key | New-Folder -Name $folder.Name 
        }
}

##ESX host migration

#Switch off HA
Get-Cluster $datacenter -Server $sourceVI  | Set-Cluster -HAEnabled:$false -DrsEnabled:$false -Confirm:$false

#Remove ESX hosts from old vcenter
$Myvmhosts = get-datacenter $datacenter -Server $sourceVI | Get-VMHost 
foreach ($line in $Myvmhosts) {
Get-vmhost -Server $sourceVI -Name $line.Name | Set-VMHost -State "Disconnected" -Confirm:$false
Get-VMHost -server $sourceVI -Name $line.Name | Remove-VMHost -Confirm:$false
}
#add ESX hosts into new vcenter
foreach ($line in $Myvmhosts) {
    Add-VMHost -Name $line.name  -Location (Get-Datacenter $datacenter -server $destVI) -user root -Password a:123456 -Force
}

#Turn on HA and DRS on 
Set-Cluster -Server $destVI Cluster1 -DrsEnabled:$true -HAEnabled:$true -Confirm:$false

Disconnect-VIServer $sourceVI -Confirm:$false

##workaround for non working new-vipermissions
           
function New-VIAccount($principal) {
    $flags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::DeclaredOnly -bor [System.Reflection.BindingFlags]::Instance
    
    $method = $defaultviserver.GetType().GetMethods($flags) | where { $_.Name -eq "VMware.VimAutomation.Types.VIObjectCore.get_Client" }
    $client = $method.Invoke($global:DefaultVIServer, $null)
    Write-Output (New-Object VMware.VimAutomation.Client20.PermissionManagement.VCUserAccountImpl -ArgumentList $principal, "", $client)
}

##move the vm's to correct location
$VMfolder = @()
$VMfolder = import-csv "c:\VMs-with-FolderPath-$($datacenter).csv" | Sort-Object -Property Path
foreach($guest in $VMfolder){
    $key = @()
    $key =  Split-Path $guest.Path | split-path -leaf
    Move-VM (get-datacenter $datacenter -Server $destVI  | Get-VM $guest.Name) -Destination (get-datacenter $datacenter -Server $destVI | Get-folder $key) 
}


##Import VM Custom Attributes and Notes
$NewAttribs = Import-Csv "C:\vms-with-notes-and-attributes-$($datacenter).csv"

    foreach ($line in $NewAttribs) {
        set-vm -vm $line.Name -Description $line.Notes -Confirm:$false
        Set-CustomField -Entity (get-vm $line.Name) -Name $line.Key -Value $line.Value -confirm:$false
        Set-CustomField -Entity (get-vm $line.Name) -Name $line.Key1 -Value $line.Value1 -confirm:$false
    
    }
    

##Import Permissions
$permissions = @()
$permissions = Import-Csv "c:\perms-$($datacenter).csv"

foreach ($perm in $permissions) {
    $entity = ""
    $entity = New-Object VMware.Vim.ManagedObjectReference
    
    switch -wildcard ($perm.EntityId)
        {
             Folder* { 
             $entity.type = "Folder"
             $entity.value = ((get-datacenter $datacenter | get-folder $perm.Foldername).ID).Trimstart("Folder-")
             }
             VirtualMachine* { 
             $entity.Type = "VirtualMachine"
             $entity.value = ((get-datacenter $datacenter | Get-vm $perm.Foldername).Id).Trimstart("VirtualMachine-")             
            }
        }
    $setperm = New-Object VMware.Vim.Permission
    $setperm.principal = $perm.Principal
        if ($perm.isgroup -eq "True") {
            $setperm.group = $true
            } else {
            $setperm.group = $false
            }
    $setperm.roleId = (Get-virole $perm.Role).id
    if ($perm.propagate -eq "True") {
            $setperm.propagate = $true
            } else {
            $setperm.propagate = $false
            }
                
    $doactual = Get-View -Id 'AuthorizationManager-AuthorizationManager'
    $doactual.SetEntityPermissions($entity, $setperm)
}
    
##Error Checking
################

##Gather all info for New Vcenter        
##Export all folders
$report = @()
$report = Get-folder vm -server $destVI | get-folder | Get-Folderpath
        ##Replace the top level with vm
        foreach ($line in $report) {
        $line.Path = ($line.Path).Replace("DC1\","vm\")
        }
$report | Export-Csv "c:\Folders-with-FolderPath_dest.csv" -NoTypeInformation

##Export all VM locations
$report = @()
$report = get-vm -server $destVI | Get-Folderpath

$report | Export-Csv "c:\vms-with-FolderPath_dest.csv" -NoTypeInformation


#Get the Permissions    
$permissions = Get-VIpermission -Server $destVI
        
        $report = @()
              foreach($perm in $permissions){
                $row = "" | select EntityId, FolderName, Role, Principal, IsGroup, Propopgate
                $row.EntityId = $perm.EntityId
                $Foldername = (Get-View -id $perm.EntityId).Name
                $row.FolderName = $foldername
                $row.Principal = $perm.Principal
                $row.Role = $perm.Role
                $report += $row
            }
        $report | export-csv "c:\perms_dest.csv" -NoTypeInformation

##Export VM Custom Attributes and notes

$vmlist = get-vm -Server $destVI
$Report =@()
    foreach ($vm in $vmlist) {
        $row = "" | Select Name, Notes, Key, Value, Key1, Value1
        $row.name = $vm.Name
        $row.Notes = $vm | select -ExpandProperty Notes
        $customattribs = $vm | select -ExpandProperty CustomFields
        $row.Key = $customattribs[0].Key
        $row.Value = $customattribs[0].value
        $row.Key1 = $customattribs[1].Key
        $row.Value1 = $customattribs[1].value    
        $Report += $row
    }

$report | Export-Csv "c:\vms-with-notes-and attributes_dest.csv" -NoTypeInformation

##compare the source and destination - this part is not yet finished
write-output "Folder-paths"
Compare-Object -ReferenceObject (import-csv C:\vms-with-FolderPath.csv) (import-csv C:\vms-with-FolderPath_dest.csv) -IncludeEqual


write-output "Notes & Attributes"
Compare-Object -ReferenceObject (import-csv "C:\vms-with-notes-and attributes.csv") (import-csv "C:\vms-with-notes-and attributes_dest.csv") -IncludeEqual

write-output "Permissions"
Compare-Object -ReferenceObject (import-csv C:\perms.csv | select * -ExcludeProperty EntityId) (import-csv C:\perms_dest.csv | select * -ExcludeProperty EntityId) -IncludeEqual
Disconnect-VIServer -Server $destVI -Force -confirm:$false
    
