function tf-workspace-get-id{
    param(
        [string]
        $workspaceName
    )
    $endpoint2 = "/organizations/:orgName/workspaces/$workspaceName"
    $response2 = tf-custom-invoke -endpoint $endpoint2 -method Get
    $workspaceID = $response2.data.id
    
    return $workspaceID
}

function tf-workspaces-get-list{
<#
.Description
Return ALL workspaces
#>
    ## may need to adjust this if this takes too long to return single batch
    $pageSize = "100"
    $pageNum = 1
    $workspaces = @()
    do{ 
        $endpoint = "/organizations/:orgName/workspaces?page%5Bnumber%5D=$pageNum&page%5Bsize%5D=$pageSize"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get
        $workspaces += $response.data
        $pageNum += 1
    }while ($response.data.count -eq $pageSize)

    ## Notes (use $workspaces[X] as a prefix to below dots)
    # If .attributes.locked is True then you can look up who locked it by .relationships.'locked-by'
    
    # .terraform-version is the bin version

    # .attributes.'vcs-repo'.branch will give you which branch it's using to trigger. It may be empty (.attributes.'vcs-repo'.branch.Length == 0)

    # You can use .relationships.'current-state-version'.data.id to retrieve the latest state file id
    # You can use .relationships.'current-run'.data.id to retrieve the current run id
    
    # You can filter the output of below workspace by name like this: $test = $workspaces | ?{$_.attributes.name -eq "baseline-*"}

    return $workspaces   
}
    
function tf-workspaces-get-workspace{
<#
.Description
Return just a single workspace, but must know the exact name or id
#>
    param(
        [string]
        $name,
        [string]
        $id
    )
    $response = @{}
    if($name){
        $endpoint = "/organizations/:orgName/workspaces/$name"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get
    }elseif ($id){
        $endpoint = "/workspaces/$id"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get
    }else{
        write-host "No Name or ID provided"
    }
    return $response.data
}
function tf-workspaces-get-plan-content{
<#
.Description
Returns plan output. Need to provide a list of workspaces. 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $false)]
        [string]
        $folder = $pwd
    )
    foreach ($workspace in $workspaces){
        ## do not update bin on any pending workspace. If you do that pending apply will error out. 
        $workspace_name = $workspace.attributes.name
        $run_id = $workspace.relationships.'current-run'.data.id
        $plan_id = tf-run-get-plan-id -run_id $run_id
        $plan_url = tf-run-get-plan-url -plan_id $plan_id
        $filename = "$folder\$($workspace_name).txt"
        tf-run-get-plan-content -plan_url $plan_url -filename $filename
    }
}
    
function tf-workspaces-update-version{
<#
.Description
You can use this function to Update Terraform binary of workspaces that you feed into this. 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $true)]
        [string]
        $terraform_ver
    )
    $body = @{
        "data" = @{
            "attributes" = @{
                "terraform_version" = $terraform_ver
            }
        "type" = "workspaces"
        }
    }

    $json_body = $body | convertto-json
    $ignore_status_list = @("policy_checked")
    foreach ($workspace in $workspaces){
        ## do not update bin on any pending workspace. If you do that pending apply will error out. 
        $workspace_name = $workspace.attributes.name
        $run_id = $workspace.relationships.'current-run'.data.id
        $current_status = tf-run-get-status -run_id $run_id

        if ($current_status -notin $ignore_status_list){
            $endpoint = "/organizations/:orgName/workspaces/$workspace_name"
            $response = tf-custom-invoke -endpoint $endpoint -Method Patch -Body $json_body
            write-host "Done: ", $workspace_name, $response.data.attributes.'terraform-version'
        }
    }
}

function tf-workspaces-get-version{
    <#
    .Description
    Get a report of Bin being used by a workspaces
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces
    )
    $versionList = @()
    
    foreach ($item in $workspaces){
        $hash = @{
            workspace = $item.attributes.name
            version   = $item.attributes.'terraform-version'
        }
        $Object = New-Object PSObject -Property $hash  
        $versionList += $Object
    }
    return $versionList
}
    
function tf-workspace-get-outputs{
<#
.Description
Get output of a single workspace. You can pass in ID or Name. 
#>
    param(
        [string]
        $workspaceName,
        [string]
        $workspaceID
    )
    $ws_outputs = New-Object PSObject
    $response = tf-workspace-get-current-state -workspaceName $workspaceName -workspaceID $workspaceID

    # Each output is contained within its own api call via workspace state version output id
    foreach ($item in $response.data.relationships.outputs.data){
        # get the workspace state version id
        $wsout = $item.id
        # use the above id to make a new query string
        $getOutputInfo = "/state-version-outputs/$wsout"
        # make API call to get actual content of this output
        $outputInfo = tf-custom-invoke -endpoint $getOutputInfo -method Get
        ## Handles empty string key property
        ## Cannot bind argument to parameter 'Name' because it is an empty string.
        if (($outputInfo.data.attributes.name).length -gt 0){
            # append this to the array to build the complete output
            $ws_outputs | add-member Noteproperty "$($outputInfo.data.attributes.name)" $outputInfo.data.attributes.value
        }
    }   
    
    return $ws_outputs
}

function tf-workspace-get-current-state{
    <#
    .Description
    Get current state from workspace. Current state is what's written to state. If it's pending, it's not this.

    GET /workspaces/:workspace_id/current-state-version
    #>
    param(
        [string]
        $workspaceName,
        [string]
        $workspaceID
    )
    ##if id is not provided, but name is
    if ($workspaceName.Length -gt 0 -and $workspaceID.Length -eq 0){
        $workspaceID = tf-workspace-get-id -workspaceName $workspaceName
    }
    
    $state_output = New-Object PSObject
    ##if id given or found
    if ($workspaceID.Length -gt 10){
        $endpoint = "/workspaces/$workspaceID/current-state-version"
        $state_output = tf-custom-invoke -endpoint $endpoint -method Get
    }
    return $state_output
}

function tf-workspace-roll-back-state{
    <#
    .Description
    Roll back to previous version of state
    #>
    param(
        [string]
        $workspaceID,
        [string]
        $previous_id
    )

$json_body = @"
{
    "data": {
        "type":"state-versions",
        "relationships": {
        "rollback-state-version": {
            "data": {
            "type": "state-versions",
            "id": "$previous_id"
            }
        }
        }
    }
}
"@
    write-host "Rolling back state should ONLY be done in emergency. Be careful"
    $ans = read-host "Are you sure?"
    $getOutputInfo = "/workspaces/$workspaceID/state-versions"
    ##Need to lock the workspace
    tf-workspaces-lock -workspaces @(@{id = $workspaceID}) -comment "Lock to upload state" -this_domain $this_domain -this_token $this_token -this_org $this_org
    # make API call to get actual content of this output
    tf-custom-invoke -endpoint $getOutputInfo -method POST -body $json_body -this_domain $this_domain -this_token $this_token -this_org $this_org
    ##Then we unlock the workspace
    tf-workspaces-unlock -workspaces @(@{id = $workspaceID}) -this_domain $this_domain -this_token $this_token -this_org $this_org
}

function tf-workspace-get-current-state-file{
    <#
    .Description
    Download the state json file, not including the metadata of the output
    #>
    param(
        [string]
        $workspaceName,
        [string]
        $workspaceID,
        [string]
        $outputfileName
    )
    $response = tf-workspace-get-current-state -workspaceName $workspaceName -workspaceID $workspaceID
    if ($outputfileName.length -eq 0){
        if ($workspaceName -eq 0){
            $outputfileName = $workspaceID + ".tfstate"
        }else{
            $outputfileName = $workspaceName + ".tfstate"
        }
    }

    $downloadURL = $response.data.attributes."hosted-state-download-url"
    try{
        invoke-webrequest -uri $downloadURL -OutFile $outputfileName -ErrorAction Stop
    }catch{
        write-host "Error retrieving state file"
    }        
    return $downloadURL
}

function tf-workspace-get-current-run{
    <#
    .Description
    With workspace, get current run
    #>
    param(
        [string]
        $workspaceName,
        [string]
        $workspaceID
    )
    $workspace = tf-workspaces-get-workspace -name $workspaceName -id $workspaceID
    
    $run_id = $workspace.relationships.'current-run'.data.id
    return $run_id
}
function tf-workspace-get-current-state-object{
    <#
    .Description
    get the current state in object format
    #>
    param(
        [string]
        $workspaceName,
        [string]
        $workspaceID
    )
    $result = New-Object PSObject
    ## Get current state
    $response = tf-workspace-get-current-state -workspaceName $workspaceName -workspaceID $workspaceID
    ## Get the download URL of the current state
    $downloadURL = $response.data.attributes."hosted-state-download-url"

    try{
        ## try to use the download link from above
        $request = invoke-webrequest -uri $downloadURL -ErrorAction Stop
        
        ## content is in BYTE, convert it to ASCII String so we can read the Serial and Lineage
        $ascii_content = [System.Text.Encoding]::ASCII.GetString($request.Content) | convertfrom-json
        $lineage = $ascii_content.lineage
        $serial = $ascii_content.serial

        ## Convert BYTE content into BASE64
        $base64 = [Convert]::ToBase64String($request.content)
        
        ## Get the MD5 Checksum of the BYTE -- notice this is slightly different for ASCII String
        $hash_byte = (Get-FileHash -InputStream ([System.IO.MemoryStream] ([byte[]] $request.Content)) -Algorithm MD5).Hash.ToLower()

        ## Create the output object
        $result | add-member Noteproperty downloadURL            $downloadURL
        $result | add-member Noteproperty state_raw              $request.content
        $result | add-member Noteproperty state_base64data       $base64
        $result | add-member Noteproperty state_hash             $hash_byte
        $result | add-member Noteproperty state_serial           $serial
        $result | add-member Noteproperty state_lineage          $lineage
        
    }catch{
        write-host "Error retrieving state file"
    }        

    return $result
}

function tf-workspace-put-state-version{
    <#
    .Description
    PUT the current state into workspace
    #>
    param(
        [string]
        $workspaceName,
        [string]
        $workspaceID,
        $payload_input
    )

    $serial = $payload_input.state_serial
    $md5_hash = $payload_input.state_hash
    $lineage = $payload_input.state_lineage
    $base64_data = $payload_input.state_base64data

$json_body = @"
{
"data": {
"type":"state-versions",
"attributes": {
"serial": $serial,
"md5": "$md5_hash",
"lineage": "$lineage",
"state": "$base64_data"
}
}
}
"@

    if ($workspaceName.Length -gt 0 -and $workspaceID.Length -eq 0){
        $workspaceID = tf-workspace-get-id -workspaceName $workspaceName
        write-host $workspaceID
    }
    ##This is the URL that we need to use
    $getOutputInfo = "/workspaces/$workspaceID/state-versions"
    ##Need to lock the workspace
    tf-workspaces-lock -workspaces @(@{id = $workspaceID}) -comment "Lock to upload state"
    # make API call to get actual content of this output
    tf-custom-invoke -endpoint $getOutputInfo -method POST -body $json_body
    ##Then we unlock the workspace
    tf-workspaces-unlock -workspaces @(@{id = $workspaceID})
}




    ###################################
function tf-workspaces-do-apply{
<#
.Description
Attempt to apply most recent run on a workspace. Will refresh to get the latest run first.
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        $comment = "Apply from TFHelper"
    )
    
    foreach ($workspace in $workspaces){
        ##Should update the workspace before doing next
        $workspace_id = $workspace.id
        $current_workspace = tf-workspaces-get-workspace -id $workspace_id
        ## get current run
        $run_id = $current_workspace.relationships.'current-run'.data.id      
        ## get current status
        $current_status = tf-run-get-status -run_id $run_id
        ## Apply will only apply for our case in following two status of current run
        if ($current_status -in ('policy_checked', 'planned')){
            $response = tf-run-do-apply -run_id $run_id -comment $comment
        }else{  
            write-host "Workspace will not apply in $current_status"
        }
    }
}

function tf-workspaces-do-discard{
<#
.Description
Discard run that is waiting for confirmation.  
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        $comment = "Discarded from TFHelper"
    )
    foreach ($workspace in $workspaces){
        ##Should update the workspace before doing next
        $workspace_id = $workspace.id
        $current_workspace = tf-workspaces-get-workspace -id $workspace_id
        $run_id = $current_workspace.relationships.'current-run'.data.id      
        $response = tf-run-do-discard -run_id $run_id -comment $comment
    }
}

function tf-workspaces-do-cancel{
<#
.Description
Cancel run that is waiting for queued.  
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        $comment = "Cancelled from TFHelper"
    )
    foreach ($workspace in $workspaces){
        ##Should update the workspace before doing next
        $workspace_id = $workspace.id
        $current_workspace = tf-workspaces-get-workspace -id $workspace_id
        $run_id = $current_workspace.relationships.'current-run'.data.id      
        $response = tf-run-do-cancel -run_id $run_id -comment $comment
    }
}

function tf-workspaces-do-escape{
<#
.Description
Cancel or discard run based on current state.  
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        $comment = "Escaped from TFHelper"
    )
    foreach ($workspace in $workspaces){
        ##Should update the workspace before doing next
        $workspace_id = $workspace.id
        $current_workspace = tf-workspaces-get-workspace -id $workspace_id
        $run_id = $current_workspace.relationships.'current-run'.data.id      
        $status = tf-run-get-status -run_id $run_id
        if ($status -in ('policy_checked','pending','policy_override')){
            #discard
            $response = tf-run-do-discard -run_id $run_id -comment $comment
        }elseif($status -in ('plan_queued')){
            #cancel
            $response = tf-run-do-cancel -run_id $run_id -comment $comment
        }
    }
}


function tf-workspaces-do-run{
<#
.Description
Create a new run. This is like pressing that 'Queue Plan' button on the web. 
If auto-apply is set, it'll also Apply. But for our workspaces, this is effectively doing a plan. 
Run this then wait before applying. It's possible to setup a loop where you periodically check status, if you really want. 
Cannot do this against pending workspace (404)
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $false)]
        [switch]
        $ignore_errored_status,
        $comment = "Run from TFHelper"
    )


    $ignore_status_list = @()
    if ($ignore_errored_status){
        $ignore_status_list += "errored"
    }
    ## Ignore workspaces with following status
    $ignore_status_list += "policy_checked"
    $ignore_status_list += "policy_override"
    $endpoint = "/runs"
    foreach ($workspace in $workspaces){
        $workspace_id = $workspace.id
        ##Should update the workspace before running
        $current_workspace = tf-workspaces-get-workspace -id $workspace_id
        $run_id = $current_workspace.relationships.'current-run'.data.id      
        
## attempted to use psobject then convert to json, but kept getting 505 error. 
$json_body = @"
{
"data": {
"attributes" : {
"message": "$comment"
},
"type":"runs",
"relationships":{
"workspace": {
"data":{
"type":"workspaces",
"id": "$workspace_id"
}
}
}
}
}
"@
        $current_status = tf-run-get-status -run_id $run_id
        if ($current_status -notin $ignore_status_list){
            $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
        }else {
            write-host "Won't run on workspace in $current_status"
        }
    }
}


function tf-workspaces-do-policy-override{
<#
.Description
Like clicking on Override & Continue button on console. 
This only works on workspace plan in policy_override status. 

Takes a list of workspaces as input.
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces
    )
    
    foreach ($workspace in $workspaces){
        $workspace_id = $workspace.id
        $current_workspace = tf-workspaces-get-workspace -id $workspace_id
        ## get current run
        $run_id = $current_workspace.relationships.'current-run'.data.id 
        ## get current status
        $current_status = tf-run-get-status -run_id $run_id
        if ($current_status -in ('policy_override')){
            $policy_response = tf-run-get-policy-check -run_id $run_id
            ## this will return true (boolean) if you have permission to do this
            if ($policy_response.data.attributes.permissions.'can-override'){
                $response = tf-run-override-soft-policy -policy_check_id $policy_response.data.id
            }else{  
                write-host "You do not have permission to override policy"
            }
        }else{  
            write-host "Workspace is not in policy_override status"
        }
    }
}

function tf-workspaces-do-destroy {
    <#
    .Description
    Run a destroy plan with the most current configuration version.  
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $true)]
        [string[]]$filter_status_list,
        $comment = "Run from TFHelper"
    )

        $endpoint = "/runs"
        
        foreach ($workspace in $workspaces){
            $workspace_id = $workspace.id
            $current_workspace = tf-workspaces-get-workspace -id $workspace_id
            $run_id = $current_workspace.relationships.'current-run'.data.id      
            
$json_body = @"
{
"data": {
"attributes" : {
"message": "$comment",
"is-destroy": true
},
"type":"runs",
"relationships":{
"workspace": {
"data":{
"type":"workspaces",
"id": "$workspace_id"
}
}
}
}
}
"@
        $current_status = tf-run-get-status -run_id $run_id
        if ($current_status -in $filter_status_list){
            $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
        }
    }
}

function tf-workspaces-lock{
    <#
    .Description
    Lock a workspace. 
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        $comment = "Run from TFHelper"
    )

    $body = @{
        "comment" = $comment
    }
    $json_body = $body | convertto-json

    foreach ($workspace in $workspaces){
        $workspace_id = $workspace.id
        $endpoint = "/workspaces/$workspace_id/actions/lock"
        $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
    }
}
function tf-workspaces-unlock{
    <#
    .Description
    unLock a workspace. This DOES NOT force unlock. If a workspace is locked, this will not unlock it.  
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces
    )
    $body = @{
        "comment" = "no comment"
    }
    $json_body = $body | convertto-json
    
    foreach ($workspace in $workspaces){
        $workspace_id = $workspace.id
        $endpoint = "/workspaces/$workspace_id/actions/unlock"
        $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
    }
}

function tf-workspaces-filter-by-status{
<#
.Description
Filters all workspaces by status filter. You can toggle as many as you want. 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $false)]
        [switch]
        $applied,
        [Parameter(Mandatory = $false)]
        [switch]
        $discarded,
        [Parameter(Mandatory = $false)]
        [switch]
        $planned_and_finished,
        [Parameter(Mandatory = $false)]
        [switch]
        $policy_checked,
        [Parameter(Mandatory = $false)]
        [switch]
        $errored
    )
    $status_list = @()
    if($applied){
        $status_list += 'applied'
    }
    if($discarded){
        $status_list += 'discarded'
    }
    if($planned_and_finished){
        $status_list += 'planned_and_finished'
    }
    if($policy_checked){
        $status_list += 'policy_checked'
    }
    if($errored){
        $status_list += 'errored'
    }
    $result = @()
    foreach ($workspace in $workspaces){
        $run_id = $workspace.relationships.'current-run'.data.id
        $status = tf-run-get-status -run_id $run_id
        if ($status -in $status_list){
            $result += $workspace
        }
    }
    return $result
}
    
function tf-workspaces-filter-by-prefix{
<#
.Description
Filter given prefix by prefix of workspace name. Will return a new workspaces array.
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $true)]
        [string]
        $prefix
    )
    $search = $prefix + "*"
    return $workspaces | ?{$_.attributes.name -like $search}
}


function tf-workspaces-get-resource-count{
<#
.Description
Get resource counter
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces
    )
    $total_data_counter = 0
    $total_resource_counter = 0

    foreach ($workspace in $workspaces){
        $data_counter = 0
        $resource_counter = 0
        $workspace_id = $workspace.id
        $workspace_name = $workspace.attributes.name
        $output = tf-workspace-get-current-state -workspaceID $workspace_id
        
        foreach($item in $output.data.attributes.resources){
            if ($item.type.StartsWith("data.")) {
                $data_counter = $data_counter + 1
            }else{
                $resource_counter = $resource_counter + 1
            }
        }

        write-host "$workspace_name, $data_counter, $resource_counter"

        $total_data_counter = $total_data_counter + $data_counter 
        $total_resource_counter = $total_resource_counter + $resource_counter 
    }
    write-host "Total Data: $total_data_counter"
    write-host "Total Resource: $total_resource_counter"
}

function tf-workspaces-do-delete{
    <#

    .Description
    https://developer.hashicorp.com/terraform/cloud-docs/api-docs/workspaces#force-delete-a-workspace
    This force deletes a workspace. This DOES not delete the managed resources, this simply removes the WORKSPACE
    Suggest managing workspaces via orchestrator whenever possible instead to Delete a workspace.
    Suggest running do-destroy first to remove the underlying resources that this workspace is managing
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $workspaces,
        [Parameter(Mandatory = $false)]
        [switch]
        $force,
        $comment = "From TFHelper"
    )
    foreach ($workspace in $workspaces){
        $ans = "y"
        $workspace_id = $workspace.id
        $workspace_name = $workspace.attributes.name
        if(!$force){
            $ans = read-host "Are you sure you want to delete $workspace_name (y/n)"
        }
        if ($ans -eq "y"){
            $workspace_id = $workspace.id
            $endpoint = "/workspaces/$workspace_id"
            $response = tf-custom-invoke -endpoint $endpoint -Method Delete -this_domain $this_domain -this_token $this_token -this_org $this_org
            write-host "Deleted $workspace_name"
        }else{
            write-host "Skip Deleting $workspace_name"
        }
    }    

}