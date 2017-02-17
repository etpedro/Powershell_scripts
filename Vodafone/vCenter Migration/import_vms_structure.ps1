$newDatacenter = "Boavista.OSS" 
$newFolder = "Folder1" 

$startFolder = New-Folder -Name $newFolder -Location (Get-Folder -Name vm -Location (Get-Datacenter -Name $newDatacenter))

Import-Csv "C:\vm-folder-boavista.csv" -UseCulture | %{
    $location = $startFolder
    $_.BlueFolderPath.TrimStart('/').Split('/') | %{
        $tgtFolder = Get-Folder -Name $_ -Location $location -ErrorAction SilentlyContinue
        if(!$tgtFolder){
            $location = New-Folder -Name $_ -Location $location
        }
        else{
            $location = $tgtFolder
        }
    }
    
    $vm = Get-VM -Name $_.Name -ErrorAction SilentlyContinue
    if($vm){
        Move-VM -VM $vm -Destination $location -Confirm:$false 
    }
}