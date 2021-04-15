################################################
################################################
# This module only support single domain and org
################################################
$tf_domain = "app.terraform.io"
$tf_org    = "myOrg" 
################################################
# If this variable is missing the let's go find
################################################
if(!$tf_token){
    # Run `terraform import $domain` to populate this
    $credentialPath = "$($env:userprofile)\AppData\Roaming\terraform.d\credentials.tfrc.json"
    write-host "token not found. Searching..."
    if(test-path($credentialPath)){
        write-host $credentialPath, "found"
        $tf_token = ((get-content -Path $credentialPath) | convertfrom-json).credentials.$($tf_domain).token 
    }else{
        write-host $credentialPath, "not found."
        $tf_token = read-host "Please enter your token here"
    }
}

function tf-custom-invoke{
<#
.Description
This is a wrapper for invoke-restmethod. 
Put your custom outputs and errors here. 
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $endpoint,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Get","Patch","Post","Delete")]
        $method,
        $body
    )
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $tf_token")
    $headers.Add("Content-Type","application/vnd.api+json")
    $domain = [System.Uri] "https://$tf_domain"
    $api_version = "/api/v2"
    $orgName = $tf_org
    # Substitute :orgName with the above orgName variable
    $endpoint = $endpoint.Replace(":orgName",$orgName)
    # create the new uri using above domain and new endpoint after substitution
    $uri = "$($domain)$($api_version)$($endpoint)" 
    $response = $null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
    ## these are all the http actions we are expecting. Use the below block to define unique outputs and error catching. 
    write-host $method, $uri
    switch($method){
        "Get" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method
            }catch{
                write-host $_
            }
        }
        "Patch" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method -Body $json_body
                
            }catch{
                write-host $_
            }
        }
        "Post" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method -Body $json_body
                
                
            }catch{
                write-host $_
            }
        }
        "Delete" {
            try{
                $response = Invoke-RestMethod $uri -Headers $headers -Method $method -Body $json_body
                
                
            }catch{
                write-host $_
            }
        }
    }
    return $response
}

function tf-special-get-metadata{
<#
.Description
Gets output of our unique metadata workspace
#>
    $workspaceName = "my_org-metadata"
    return  tf-workspace-get-outputs -workspaceName $workspaceName
}

function tf-special-run{
<#
.Description
Runs baseline
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $prefix
    )
    $workspaces = tf-workspaces-get-list
    $special = tf-workspaces-filter-by-prefix -workspaces $workspaces -prefix $prefix
    if($special.count -gt 0){
        write-host "Queing new runs on all", $prefix  
        tf-workspaces-do-run -workspaces $special -ignore_errored_states -comment "Auto Plan"
        write-host "Waiting... please enter 'apply' when you are ready to Apply"
        $ans = read-host
        if($ans -eq "apply"){
            tf-workspaces-do-apply -workspaces $special -comment "Auto Apply"
        }
        elseif($ans -eq "discard"){
            tf-workspaces-do-discard -workspaces $special
        }
        else{
            write-host "Further action canceled"
        }
    }else{
        write-host "nothing found"
    }
}
