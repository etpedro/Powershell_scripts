New-VIProperty -Name 'BlueFolderPath' -ObjectType 'VirtualMachine' -Value {
    param($vm)

    function Get-ParentName{
        param($object)

        if($object.Folder){
            $blue = Get-ParentName $object.Folder
            $name = $object.Folder.Name
        }
        elseif($object.Parent -and $object.Parent.GetType().Name -like "Folder*"){
            $blue = Get-ParentName $object.Parent
            $name = $object.Parent.Name
        }
        elseif($object.ParentFolder){
            $blue = Get-ParentName $object.ParentFolder
            $name = $object.ParentFolder.Name
        }
        if("vm","Datacenters" -notcontains $name){
            $blue + "/" + $name
        }
        else{
            $blue
        }
    }

    (Get-ParentName $vm).Remove(0,1)
} -Force | Out-Null 
$dcName = "Alfragide"

Get-VM -Location (Get-Datacenter -Name $dcName) | 
Select Name,BlueFolderPath |
Export-Csv "C:\vm-folder-alfragide.csv" -NoTypeInformation -UseCulture 