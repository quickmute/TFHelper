############################################
# Users and Teams
############################################
function tf-user-whoami{
<#
.Description
Displays the information about current user
#>
    param(
        $this_domain,
        $this_token,
        $this_org
    )
    $endpoint = "/account/details"
    $response = tf-custom-invoke -endpoint $endpoint -Method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
    return $response.data
}

function tf-teams-get-list{
<#
.Description
Returns all teams in the current organization
#>
    param(
        [Parameter(Mandatory = $false)]
        [switch]
        $includeUsers,
        $this_domain,
        $this_token,
        $this_org
    )
    ##https://www.terraform.io/docs/cloud/api/index.html#inclusion-of-related-resources
    ##extra argument if you want to include user data
    $extra= ""
    if ($includeUsers){
        $extra = "&include=users"
    }

    ## may need to adjust this if this takes too long to return single batch
    $pageSize = "20"
    $pageNum = 1
    $allTeams = @()
    $allUsers = @()
    do{ 
        $endpoint = "/organizations/:orgName/teams?page%5Bnumber%5D=$pageNum&page%5Bsize%5D=$pageSize$extra"
        write-host $endpoint
        $response = tf-custom-invoke -endpoint $endpoint -Method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
        $allTeams += $response.data
        $allUsers += $response.included
        $pageNum += 1
    }while ($response.data.count -eq $pageSize)
    $hash = @{
        teams       = $allTeams
        users       = $allUsers
    }
    $Object = New-Object PSObject -Property $hash
    return $Object
}

function tf-teams-get-team{
<#
.Description
Returns a specific team information using given team id. Can also be used to return list of users in the team. 
When requesting list of users, there will be a new key "Users" that can be used to display userid and username
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $teamId,
        [Parameter(Mandatory = $false)]
        [switch]
        $includeUsers,
        $this_domain,
        $this_token,
        $this_org
    )
    $extra= ""
    if ($includeUsers){
        $extra = "?include=users"
    }
    $endpoint = "/teams/$teamId$extra"
    $response = tf-custom-invoke -endpoint $endpoint -Method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
    if ($includeUsers){
        $response | Add-Member -NotePropertyName Users -NotePropertyValue ($response.included | select-object -Property id, @{Name='Username'; Expression={$_.attributes.username}})
    }
    return $response
}

function tf-teams-filter-by-name{
<#
.Description
Takes an array of teams and filters the name. Use "*" as wildcard in the searchString
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject]
        $teams,
        [string]
        $searchString
    )
    $result = $teams | ?{$_.attributes.name -like $searchString}
    return $result
}


function tf-user-get-user{
<#
.Description
Returns a details about a specific user. You cannot resolve a name to get id, so you have to use tf-teams-get-team with IncludeUser flag to get list of UserIds
#>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]
        $userId,
        $this_domain,
        $this_token,
        $this_org
    )
    $endpoint = "/users/$teamId$userId"
    $response = tf-custom-invoke -endpoint $endpoint -Method Get -this_domain $this_domain -this_token $this_token -this_org $this_org
    
    return $response
}
