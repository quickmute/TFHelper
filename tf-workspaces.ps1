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
    
function tf-workspaces-update-bin{
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
    $ignore_states = @("policy_checked")
    foreach ($workspace in $workspaces){
        ## do not update bin on any pending workspace. If you do that pending apply will error out. 
        $workspace_name = $workspace.attributes.name
        $run_id = $workspace.relationships.'current-run'.data.id
        $current_status = tf-run-get-status -run_id $run_id

        if ($current_status -notin $ignore_states){
            $endpoint = "/organizations/:orgName/workspaces/$workspace_name"
            $response = tf-custom-invoke -endpoint $endpoint -Method Patch -Body $json_body
            write-host "Done: ", $workspace_name, $response.data.attributes.'terraform-version'
        }
    }
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
    ##if id is not provided, but name is
    if ($workspaceName.Length -gt 0 -and $workspaceID.Length -eq 0){
        $endpoint2 = "/organizations/:orgName/workspaces/$workspaceName"
        $response2 = tf-custom-invoke -endpoint $endpoint2 -method Get
        $workspaceID = $response2.data.id
    }
    
    $ws_outputs = New-Object PSObject
    ##if id given or found
    if ($workspaceID.Length -gt 10){
        $endpoint = "/workspaces/$workspaceID/current-state-version"
        $response = tf-custom-invoke -endpoint $endpoint -method Get
        # keep this array to collect all the outputs
        

        # Each output is contained within its own api call via workspace state version output id
        foreach ($item in $response.data.relationships.outputs.data){
            # get the workspace state version id
            $wsout = $item.id
            # use the above id to make a new query string
            $getOutputInfo = "/state-version-outputs/$wsout"
            # make API call to get actual content of this output
            $outputInfo = tf-custom-invoke -endpoint $getOutputInfo -method Get
            # append this to the array to build the complete output
            $ws_outputs | add-member Noteproperty "$($outputInfo.data.attributes.name)" $outputInfo.data.attributes.value 
        }   
    }
    return $ws_outputs
}

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
        $run_id = $current_workspace.relationships.'current-run'.data.id      
        $response = tf-run-do-apply -run_id $run_id -comment $comment
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
        $ignore_errored_states,
        $comment = "Run from TFHelper"
    )


    $ignore_states = @()
    if ($ignore_errored_states){
        $ignore_states += "errored"
    }
    $ignore_states += "policy_checked"
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
        if ($current_status -notin $ignore_states){
            $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
        }
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
