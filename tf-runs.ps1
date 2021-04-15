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
Discard a single run-id. Useful if you know the specific run-id. 
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
    $endpoint = "/runs/$run_id"
    $response = tf-custom-invoke -endpoint $endpoint -Method Get
    return  $response.data.attributes.status
}
