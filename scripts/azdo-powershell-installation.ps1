#This script is in charge of uploading the repository devsecops_global_configuration to your azure devops organization
#AzDo API information https://learn.microsoft.com/en-us/rest/api/azure/devops/git/import-requests/create?view=azure-devops-rest-6.0&tabs=HTTP
#Azdo PAT information https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=Windows

#--> Read input section
$organization = (Read-Host "Enter your name AzDo Organization").ToLower()
$projectName = (Read-Host "Enter Azdo Project Name").ToLower()
$userMailPat = Read-Host "Enter azDo Email User"
$pat = Read-Host "Enter your AzDo PAT" -AsSecureString
$githubPat = Read-Host "Enter Github Global Client PAT token" -AsSecureString
$repoNameOption = Read-Host "Enter DevSecOps Global repo name (enter for Default)" 

#--> Functions
function getIndex {
    param(
        $value = "",
        $valueToFind = ""
    )

    $value = $value.Replace('"',"").Replace(",","")
    $getIndex = $value.IndexOf("$valueToFind") + 1
    $lengthString = $value.length
    $getEqualLastIndex = ($lengthString - $getIndex)
    $extractValue = $value.Substring($getIndex, $getEqualLastIndex)
        
    return $extractValue
}
function replaceTokens {
    param (
        $jsonTemplate = ""
    )
    
    foreach($value in $jsonTemplate){
        $getIndexVariable = $value.IndexOf("$");
        if ($value -match "$" -and $getIndexVariable -gt 0){
    
            $getVariable = getIndex -value $value -valueToFind "$"
            $getValue = (Get-Variable $getVariable).Value
            $jsonTemplate = $jsonTemplate.Replace("$" + $getVariable, $getValue)
        }
    }

    return $jsonTemplate
}

#--> Security PAT
function getPat($pat){
    $getPat = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($pat)
    $resultGetPat = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($getPat)

    return $resultGetPat
}

#--> Successfully/Error message
function messageOutput {
    param (
        [bool] $result,
        [string] $service
    )

    if($result){
        Write-Host "The $service was created successfully."
    }else{
        Write-Error "There was an error creating the $service - Check with the administrator."
    }
    
}

#--> Import body json template
$getRepoTemplate = (Get-Content .\json_files\azdo_create_repository.json)
$getVariableGroupTemplate = (Get-Content .\json_files\azdo_create_variable_group.json)
$getGithubTemplate = (Get-Content .\json_files\azdo_create_github_endpoint.json)
$getEndpointPermissionsTemplate = (Get-Content .\json_files\azdo_patch_endpoint_permission.json)
$getPushRepoFilesArray = (Get-Content .\json_files\azdo_push_file_array.json)
$getPushRepoFiles = (Get-Content .\json_files\azdo_push_files_repo.json)

#--> Vars
if(!$repoNameOption){
    $repoName = "devsecops_global_config"
    Write-Host "Repo name by default is $repoName"
}else{
    $repoName = $repoNameOption
    Write-Host "Repo name by default is $repoName"
}

#--> Header vars
$azdoPAT = getPat($pat)
$githubPat = getPat($githubPat)
$headerAuthorization = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$azdoPAT")) }

#--> Uri vars
$repoValidationUri = "https://dev.azure.com/$organization/$projectName/_apis/git/repositories?api-version=6.0"
$getProjectUri = "https://dev.azure.com/$organization/_apis/projects?api-version=6.0"
$createRepoUri = "https://dev.azure.com/$organization/$projectName/_apis/git/repositories?api-version=6.0"
$createVariableGroupUri = "https://dev.azure.com/$organization/$projectName/_apis/distributedtask/variablegroups?api-version=5.1-preview.1"
$createGithubServiceConnectionUri = "https://dev.azure.com/$organization/$projectName/_apis/serviceendpoint/endpoints?api-version=5.1-preview.2"
$createBuildDefinition = "https://dev.azure.com/$organization/$projectName/_apis/build/definitions?api-version=7.1-preview.7"

#--> Repo validation
#--> Validates if the repo global configuration exists
$getResult = Invoke-RestMethod -Uri $repoValidationUri -Headers $headerAuthorization
$getResult = $getResult.value.name

if($getResult -match $repoName){
    Write-Error "The repo $repoName exists - please validate with the administrator"
}else{
    Write-Host "Repo $repoName not exists continue..."
    #--> Get Project ID
    $getProjectResult = Invoke-RestMethod -Uri $getProjectUri -Headers $headerAuthorization
    $projectId = ($getProjectResult.value | Where-Object -FilterScript { $_.name -eq "$projectName" }).id

    #--> Repo creation
    $body = replaceTokens -jsonTemplate $getRepoTemplate
    $createRepoResult = Invoke-RestMethod -Uri $createRepoUri -Headers $headerAuthorization -ContentType "application/json" -Method Post -Body $body

    #--> Push repo yaml master pipeline configuration
    #--> Get files names and create the json that will be injected in the push to repo
    $getYamlMasterFiles = (dir .\yml_files).Name
    $joinedFiles=@()
    $getContentClean=@()
    forEach ($value in $getYamlMasterFiles){
        $outputNameFile = $value
        $getFileContent = (Get-Content .\yml_files\$outputNameFile)

        #--> Add spaces \n for azure devops YML
        foreach ($lines in $getFileContent){
            $getContentClean += $lines + "\n"
        }

        $getFileContent = $getContentClean
        $array = replaceTokens -jsonTemplate $getPushRepoFilesArray
        $joinedFiles += $array + ","
    }

    #Remove last comma
    $joinedFiles[$joinedFiles.Length-1] = $joinedFiles[$joinedFiles.Length-1].Remove(0,1)
    #--> Generates the final json to be consumed by the api to upload the files to the repo.
    $body = replaceTokens -jsonTemplate $getPushRepoFiles
    $repositoryId = $createRepoResult.id
    $pushMasterFilesUri = "https://dev.azure.com/$organization/$projectName/_apis/git/repositories/$repositoryId/pushes?api-version=7.0"
    $pushMasterFiles.refUpdates.Count = Invoke-RestMethod -Uri $pushMasterFilesUri -Headers $headerAuthorization -ContentType "application/json" -Method Post -Body $body

    if($pushMasterFiles.refUpdates.Count){
        #--> Create Global Vars Variable Group
        $body = replaceTokens -jsonTemplate $getVariableGroupTemplate
        $createGlobalVarsVariableGroup = Invoke-RestMethod -Uri $createVariableGroupUri -Headers $headerAuthorization -ContentType "application/json" -Method Post -Body $body

        If($createGlobalVarsVariableGroup){
            #--> Output
            messageOutput -result 1 -service "DevSecOps Global Vars"

            #--> Create Github Service Connection
            $body = replaceTokens -jsonTemplate $getGithubTemplate
            $createGithubServiceConnectionResult = Invoke-RestMethod -Uri $createGithubServiceConnectionUri -Headers $headerAuthorization -ContentType "application/json" -Method Post -Body $body
            $endpointId = $createGithubServiceConnectionResult.id
            $endpointName = $createGithubServiceConnectionResult.name

            if($endpointId){
                #--> Output
                messageOutput -result 1 -service "Github Service Connection"

                #--> Grant service connection permission over the pipelines
                $body = replaceTokens -jsonTemplate $getEndpointPermissionsTemplate
                $patchEndpointPermissionsUri = "https://dev.azure.com/$organization/$projectName/_apis/pipelines/pipelinePermissions/endpoint/${endpointId}?api-version=5.1-preview.1"
                $patchGithubEndpointPermissionsResult = Invoke-RestMethod -Uri $patchEndpointPermissionsUri -Headers $headerAuthorization -ContentType "application/json" -Method Patch -Body $body

                if ($patchGithubEndpointPermissionsResult) {
                    #--> Output
                    messageOutput -result 1 -service "Grant Permission Github Service Connect"
                }else{
                    #--> Output
                    messageOutput -result 0 -service "Grant Permission Github Service Connect"
                }
            }else{
                #--> Output
                messageOutput -result 0 -service "Github Service Connection"
            }
        }else{
            #--> Output
            messageOutput -result 0 -service "DevSecOps Global Vars"
        }
    }
}