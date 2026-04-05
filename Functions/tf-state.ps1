function tf-state-migration{
    <#
    .Description
    Migrate a single workspace's state. 
    - If target name is not provided then it will use the same name as source
    - If domains are not provided then it uses the default domain

    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $source_workspaceName,
        $target_workspaceName,
        $source_domain,
        $source_token,
        $source_org,
        $target_domain,
        $target_token,
        $target_org,
        [switch]
        $source_lock,
        [switch]
        $target_lock
    )
    if(!$target_workspaceName){
        $target_workspaceName = $source_workspaceName
    }
    ###################################################################
    ## convert name to id of SOURCE workspace
    $endpoint_source_workspace = "/organizations/:orgName/workspaces/$source_workspaceName"
    $response_source_workspace = tf-custom-invoke -endpoint $endpoint_source_workspace -method Get -this_domain $source_domain -this_token $source_token -this_org $source_org
    $source_workspaceID = $response_source_workspace.data.id
    $source_workspaceLocked = $response_source_workspace.data.attributes.locked ## this is True or False boolean
    ###################################################################
    # Don't bother if the state is locked
    if ($source_workspaceLocked -eq $true){
        write-host "Source workspace is locked. Skipping"
        return $null
    }
    ###################################################################
    ## convert name to id of TARGET workspace
    $endpoint_target_workspace = "/organizations/:orgName/workspaces/$target_workspaceName"
    $response_target_workspace = tf-custom-invoke -endpoint $endpoint_target_workspace -method Get -this_domain $target_domain -this_token $target_token -this_org $target_org
    $target_workspaceID = $response_target_workspace.data.id
    $target_workspaceLocked = $response_target_workspace.data.attributes.locked ## this is True or False boolean
    # Don't bother if the state is locked
    if ($target_workspaceLocked -eq $true){
        write-host "Target workspace is locked. Skipping"
        return $null
    }
    ###################################################################
    ## Get current state of source workspace
    $endpoint_source_state = "/workspaces/$source_workspaceID/current-state-version"
    $response_source_state = tf-custom-invoke -endpoint $endpoint_source_state -method Get -this_domain $source_domain -this_token $source_token -this_org $source_org
    if ($response_source_state -eq $null){
        write-host "No State Found"
        return $null
    }
    ## get timestamp of source state
    $source_state_timestamp = [datetime]$response_source_state.data.attributes.'created-at'
    write-host "Source State timestamp: $($source_state_timestamp)"
    ###################################################################
    ## Get current state of TARGET workspace
    $endpoint_target_state = "/workspaces/$target_workspaceID/current-state-version"
    $response_target_state = tf-custom-invoke -endpoint $endpoint_target_state -method Get -this_domain $target_domain -this_token $target_token -this_org $target_org
    ## check if there is a state
    if ($response_target_state -eq $null){
        ## target doesn't have a state, so just make it look like its state is old
        write-host "Target Host does not have any state"
        $target_state_timestamp = $source_state_timestamp.AddDays(-1)
    }else{
        ## get the timestamp of target state
        $target_state_timestamp = [datetime]$response_target_state.data.attributes.'created-at'
        write-host "Current State timestamp: $($target_state_timestamp)"
    }
    ###################################################################
    ## migrate only if the target's state is OLDER than the source
    if($source_state_timestamp -lt $target_state_timestamp){
        write-host "Target State is Newer, will not override"
        return $null
    }
    ###################################################################
    ## Get the download URL of the current state of the source workspace
    $downloadURL = $response_source_state.data.attributes."hosted-state-download-url"
    if ($downloadURL -eq $null){
       write-host "Could not retrive download URL for state, please check logs"
        return $null
    }
    ###################################################################
    ## try to use the download link from above, this is the state file of source workspace
    $state_request = tf-custom-webrequest -URL $downloadURL -this_token $source_token
    ## just grab the content, this will be in byte
    $state_content_byte = $state_request.content
    if ($state_content_byte.GetType() -eq [byte[]]){
       write-host "Convert byte to string"
        $state_content_string = [System.Text.Encoding]::ASCII.GetString($state_content_byte)
    }else{
        write-host "Content is not a byte type"
        return $null
    }
    $header = ($state_content_string -split "`r?`n" )[0..4]
    $header[4] = $header[4].TrimEnd(",") + "}"
    ## conver this from json to object
    $state_header_obj = $header | ConvertFrom-Json
    try{
        ## get the original serial and lineage
        [int]$serial = $state_header_obj.serial
    }catch{
        return $null
    }
    ## create a body for the state upload
    $hash_byte = (Get-FileHash -InputStream ([System.IO.MemoryStream] ([byte[]] $state_content_byte)) -Algorithm MD5).Hash.ToLower()

    $body = [PSCustomObject]@{
        data = [PSCustomObject]@{
            type = "state-versions"
            attributes = [PSCustomObject]@{
                serial = [int]$serial
                md5 = $hash_byte
            }
        }
    }
    $json_body = $body | ConvertTo-Json -Depth 5
    
    if ($json_body -eq $null){
        write-host "Could not create state upload body"
        return $null
    }
    ###################################################################
    ###################################################################
    ## The target workspace MUST not be in pending apply state, discard or cancel it
    ## get latest run
    $run_id = $response_target_workspace.data.relationships.'current-run'.data.id
    ## get current status of run
    $endpoint_run = "/runs/$run_id"
    $response_run = tf-custom-invoke -endpoint $endpoint_run -Method Get -this_domain $target_domain -this_token $target_token -this_org $target_org
    $run_status = $response_run.data.attributes.status
    $comment_body = @{
        "comment" = "for migration"
    }
    $json_comment_body = $comment_body | convertto-json
    if ($run_status -in ('policy_checked','pending','policy_override')){
        #discard
        $endpoint_discard = "/runs/$run_id/actions/discard"
        tf-custom-invoke -endpoint $endpoint_discard -Method Post -body $json_comment_body -this_domain $target_domain -this_token $target_token -this_org $target_org        
    }elseif($run_status -in ('plan_queued')){
        #cancel
        $endpoint_cancel = "/runs/$run_id/actions/cancel"
        tf-custom-invoke -endpoint $endpoint_cancel -Method Post -body $json_comment_body -this_domain $target_domain -this_token $target_token -this_org $target_org
    }
    ###################################################################
    ## Lock the target workspace so that we can upload to it, this workspace cannot be being used
    $endpoint_lock = "/workspaces/$target_workspaceID/actions/lock"
    $body_lock = @{
        "comment" = "State Migration Lock"
    }
    $json_body_lock = $body_lock | convertto-json
    tf-custom-invoke -endpoint $endpoint_lock -Method Post -body $json_body_lock -this_domain $target_domain -this_token $target_token -this_org $target_org
    ###################################################################
    ##This is the URL that we need to use to post a placeholder for the new state to target workspace
    $endpoint_target_post_state = "/workspaces/$target_workspaceID/state-versions"
    $state_placer_response = tf-custom-invoke -endpoint $endpoint_target_post_state -method POST -body $json_body -this_domain $target_domain -this_token $target_token -this_org $target_org
    ###################################################################
    ##Now we actually upload the payload or the state to the above link
    $state_upload_url = $state_placer_response.data.attributes.'hosted-state-upload-url'
    if ($state_upload_url -ne $null){
        ## create a new header, no authentication required here
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Content-Type","application/octet-stream")
        Invoke-RestMethod -Uri $state_upload_url -Headers $headers -Method PUT -Body $state_content_byte
        ## don't unlock the target workspace if we have a toggle in place
        if(!$target_lock){
            $endpoint_unlock = "/workspaces/$target_workspaceID/actions/unlock"
            $body_unlock = @{
                "comment" = "State Migration unLock"
            }
            $json_body_unlock = $body_unlock | convertto-json
            tf-custom-invoke -endpoint $endpoint_unlock -Method Post -body $json_body_unlock -this_domain $target_domain -this_token $target_token -this_org $target_org
        }
        ###################################################################
        ###################################################################
        ## Lock the source workspace if we say so
        if($source_lock){
            $endpoint_lock_source = "/workspaces/$source_workspaceID/actions/lock"
            tf-custom-invoke -endpoint $endpoint_lock_source -Method Post -body $json_body_lock -this_domain $source_domain -this_token $source_token -this_org $source_org
        }
        ###################################################################
    }else{
        write-host "Upload URL not returned. Abort state upload."
        $ans = read-host "Press any key to continue"
        $endpoint_unlock = "/workspaces/$target_workspaceID/actions/unlock"
        $body_unlock = @{
            "comment" = "State Migration unLock"
        }
        $json_body_unlock = $body_unlock | convertto-json
        tf-custom-invoke -endpoint $endpoint_unlock -Method Post -body $json_body_unlock -this_domain $target_domain -this_token $target_token -this_org $target_org
    }
}

function tf-state-get-list{
    <#
    .Description
    Get a list of all state backups for a given single workspace
    #>
    param(
        [string]
        $workspaceName,
        $this_domain,
        $this_token,
        $this_org
    )
    $pageSize = "100"
    $pageNum = 1
    $orgFilter = "filter%5Bworkspace%5D%5Bname%5D=$($workspaceName)"
    $workspaceFilter = "filter%5Borganization%5D%5Bname%5D=:orgName"

    $states = @()
    do{ 
        $endpoint = "/state-versions?$($orgFilter)&$($workspaceFilter)&page%5Bnumber%5D=$pageNum&page%5Bsize%5D=$pageSize"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
        $states += $response.data
        $pageNum += 1
    }while ($response.data.count -eq $pageSize)
    return $states 
}

function tf-state-clean-up{
    <#
    .Description
    Move a state version to recycle bin, it hides it from view and will permanently delete after X number of days
    THIS ONLY WORKS IN TFE
    #>
    param(
        [string]
        $workspaceName,
        $age_in_days=365,
        $this_domain,
        $this_token,
        $this_org
    )
    $threshold = (Get-Date).AddDays($age_in_days*-1)
    
    ## convert name to id of workspace
    $endpoint3 = "/organizations/:orgName/workspaces/$workspaceName"
    $response3 = tf-custom-invoke -endpoint $endpoint3 -method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
    $workspaceID = $response3.data.id
    ## get current state id 
    $endpoint4 = "/workspaces/$workspaceID/current-state-version"
    $response4 = tf-custom-invoke -endpoint $endpoint4 -method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
    $currentStateVersionId = $response4.data.id
    write-host "Current State Id: $($currentStateVersionId)"
    $states = tf-state-get-list -workspaceName $workspaceName -this_domain $this_domain -this_token $this_token -this_org $this_org
    foreach ($state in $states){
        if([datetime]$state.attributes.'created-at' -lt $threshold){
            if ($currentStateVersionId -ne $state.id){
                write-host "Delete old state version created at $([datetime]$state.attributes.'created-at') - $($state.id)"
                $endpoint = "/state-versions/$($state.id)/actions/soft_delete_backing_data"
                $response = tf-custom-invoke -endpoint $endpoint -Method POST -this_domain $this_domain -this_token $this_token -this_org $this_org
            }else{
                write-host "Will NOT delete current state created at $([datetime]$state.attributes.'created-at') - $($state.id)"
            }
        }
    }
}

function tf-state-recover{
 <#
    .Description
    Recover a single state version id that is in recycling bin
 #>
    param(
        [string]
        $stateId,
        $this_domain,
        $this_token,
        $this_org
    )
    $endpoint = "/state-versions/$($stateId)/actions/restore_backing_data"
    $response = tf-custom-invoke -endpoint $endpoint -Method POST -this_domain $this_domain -this_token $this_token -this_org $this_org
}
