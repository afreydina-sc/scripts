<#
Run the scipt by command:
    ./resize_vm.ps1 file_with_data.txt
#>

$SRC_FILE = $args[0]

if ( !$SRC_FILE ){
    Write-Host "You must set a source as parameter. Exiting.." 
    exit
}

New-Item -Path ./logs -ItemType Directory -Force


$block = {
    Param( $line,
           $log_f)

    
    function Get-VM-PowerStatus {
        param (
            $vm_nm,
            $res_grp
        )
        $vm_pw_st = (az vm get-instance-view --name $vm_nm --resource-group $res_grp --query instanceView.statuses[1].displayStatus) -replace '"', ''
        return $vm_pw_st
    }
    

    $old_size = $line.Split()[0]
    $new_size = $old_size.Split("_")[1..3] -join '_'
    $vm_id = $line.Split()[1] 
    $subscr_id = $vm_id.Split("/")[2]
    $resource_grp = $vm_id.Split("/")[4]
    $vm_name = $vm_id.Split("/")[8]
    
    Get-Date -Format "yyyy-MM-ddTHH:mm:ss" > $log_f
    "Trying to resize vm " >> $log_f
    "Subscription id: $subscr_id" >> $log_f
    "Resource group: $resource_grp" >> $log_f
    "VM name: $vm_name" >> $log_f
    "VM id: $vm_id" >> $log_f
    "VM current size: $old_size" >> $log_f
    "VM new size: $new_size" >> $log_f

    az account set -s $subscr_id  >> $log_f 2>&1
    "Stopping virnual machine"  >> $log_f
    az vm stop --ids $vm_id >> $log_f 2>&1
    
    $vm_power_status = Get-VM-PowerStatus $vm_name $resource_grp
    
    if ($vm_power_status -eq "VM stopped"){
        "VM has stopped" >> $log_f

        "Resizing virnual machine" >> $log_f
        az vm resize --size $new_size --ids $vm_id >> $log_f 2>&1
        
       "Starting virnual machine" >> $log_f
        az vm start --ids $vm_id >> $log_f 2>&1
            
        $vm_power_status = Get-VM-PowerStatus $vm_name $resource_grp
        
        if ($vm_power_status -eq "VM running"){
            "VM has started" >> $log_f
        }
        else {
            "VM could not start"  >> $log_f

            "Trying to resize it back" >> $log_f
            az vm resize --size $old_size --ids $vm_id >> $log_f 2>&1

            "Starting virnual machine after resizing back" >> $log_f
            az vm start --ids $vm_id >> $log_f 2>&1
            
            $vm_power_status = Get-VM-PowerStatus $vm_name $resource_grp
            if ($vm_power_status -eq "VM running"){
            "VM has started" >> $log_f
            }
        }

    }   
    else {
        "Not able to stop the vm. Exiting."  >> $log_f
    }
}


$MaxThreads = 2
$cnt = 1
Get-Content $SRC_FILE | ForEach-Object {
    $log_f = "./logs/resize_vm_$cnt.log"
    While ($(Get-Job -state running).count -ge $MaxThreads){
        Start-Sleep -s 5
    }
    Start-Job -Scriptblock $Block -ArgumentList ($_,$log_f)
    $cnt ++
}

#Wait for all jobs to finish.
While ($(Get-Job -State Running).count -gt 0){
    start-sleep -s 10
}

#Remove all jobs created.
Get-Job | Remove-Job


