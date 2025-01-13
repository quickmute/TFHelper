function tf-run-do-apply{
    <#
    .Description
    Run an apply on a single run-id. Useful if you know the specific run-id. 
    Will only run against pending run. 
    #>
        param(
            $run_id,
            $comment = "Apply from TFHelper"
        )
        $body = @{
            "comment" = $comment
        }
    
        $json_body = $body | convertto-json
        $endpoint = "/runs/$run_id/actions/apply"
        
        $current_status = tf-run-get-status -run_id $run_id
        if ($current_status -eq "policy_checked"){
            $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
        }
    
        return $response
    }
    
    function tf-run-do-discard{
    <#
    .Description
    Discard a single run-id. Useful if you know the specific run-id. This is useful when it is waiting for user action such as override or apply. 
    #>
        param(
            $run_id,
            $comment = "Discarded from TFHelper"
        )
        $body = @{
            "comment" = $comment
        }
    
        $json_body = $body | convertto-json
        $endpoint = "/runs/$run_id/actions/discard"
        $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
        return $response
    }
    
    function tf-run-do-cancel{
    <#
    .Description
    Cancel a single run-id. Useful if you know the specific run-id. This is for when a run is queued.
    #>
        param(
            $run_id,
            $comment = "Cancelled from TFHelper"
        )
        $body = @{
            "comment" = $comment
        }
    
        $json_body = $body | convertto-json
        $endpoint = "/runs/$run_id/actions/cancel"
        $response = tf-custom-invoke -endpoint $endpoint -Method Post -body $json_body
        return $response
    }
    function tf-run-get-status{
    <#
    .Description
    Get status of a single run-id. Returns a string. 
    #>
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]
            $run_id
        )
        if ($run_id -ne ""){
            $endpoint = "/runs/$run_id"
            $response = tf-custom-invoke -endpoint $endpoint -Method Get
            return  $response.data.attributes.status
        }else{
            return "None"
        }
    }
    
    function tf-run-get-policy-check{
    <#
    .Description
    Get policy check object of a run
    https://developer.hashicorp.com/terraform/cloud-docs/api-docs/policy-checks#list-policy-checks
    #>
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]
            $run_id
        )
        $endpoint = "/runs/$run_id/policy-checks"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get
        return  $response
    }
    
    function tf-run-override-soft-policy{
    <#
    .Description
    Override policy on a run
    #>
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]
            $policy_check_id
        )
        $endpoint = "/policy-checks/$policy_check_id/actions/override"
        $response = tf-custom-invoke -endpoint $endpoint -Method Post
        return  $response
    }
    function tf-run-get-plan-id{
    <#
    .Description
    Get plan id of single run-id. Returns a string. 
    #>
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]
            $run_id
        )
        $endpoint = "/runs/$run_id"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get
        return  $response.data.relationships.plan.data.id
    }
    function tf-run-get-plan-url{
    <#
    .Description
    Get plan url of single plan id. Returns a string. 
    #>
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]
            $plan_id
        )
        $endpoint = "/plans/$plan_id"
        $response = tf-custom-invoke -endpoint $endpoint -Method Get
        return  $response.data.attributes.'log-read-url'
    }
    
    function tf-run-get-plan-content{
    <#
    .Description
    Get plan output of a single plan url. Returns a string. 
    #>
        param(
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            [string]
            $plan_url,
            [string]
            $filename
        )
        write-host $plan_url
        write-host $filename
        $file = Invoke-RestMethod -Method Get -uri $plan_url
        $CleanOutput = $file -replace '\x1b\[[0-9;]*[a-z]', ''
        $CleanOutput | out-file -FilePath $filename
    }