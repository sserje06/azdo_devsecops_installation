#This script is in charge of uploading the repository devsecops_global_configuration to your azure devops organization
#AzDo API information https://learn.microsoft.com/en-us/rest/api/azure/devops/git/import-requests/create?view=azure-devops-rest-6.0&tabs=HTTP
#Azdo PAT information https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=Windows

#--> Read input section
$organization = Read-Host "Enter your name AzDo Organization"
$projectName = Read-Host "Enter Azdo Project Name"
$userMailPat = Read-Host "Enter azDo Email User"
$pat = Read-Host "Enter your AzDo PAT" -AsSecureString
$githubPat = Read-Host "Enter Github Global Client PAT token"
$repoNameOption = Read-Host "Enter DevSecOps Global repo name (enter for Default)" 

#--> Vars
if(!$repoNameOption){
    $repoName = $projectName + "_devsecops_global_config"
    Write-Host "Repo name by default is $repoName"
}else{
    $repoName = $repoNameOption + "_devsecops_global_config"
    Write-Host "Repo name by default is $repoName"
}

#--> Security PAT
$getPat = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($pat)
$resultGetPat = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($getPat)

#--> Header vars
$headerAuthorization = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$resultGetPat")) }

#--> Uri vars
$repoValidationUri = "https://dev.azure.com/$organization/$projectName/_apis/git/repositories?api-version=6.0"
$getProjectUri = "https://dev.azure.com/$organization/_apis/projects?api-version=6.0"
$createRepoUri = "https://dev.azure.com/$organization/$projectName/_apis/git/repositories?api-version=6.0"
$createVariableGroupUri = "https://dev.azure.com/$organization/$projectName/_apis/distributedtask/variablegroups?api-version=5.1-preview.1"

#--> Repo validation
try
{
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
        $body = "{
            `n  `"name`": `"$repoName`",
            `n  `"project`": {
            `n   `"id`": `"$projectId`"
            `n  }
            `n}"    
        $createRepoResult = Invoke-RestMethod -Uri $createRepoUri -Headers $headerAuthorization -ContentType "application/json" -Method Post -Body $body

        #--> Import DevSecOps Global Skeleton
        #---> Repo Import Body creation
        $body = "{
            `n   `"parameters`": {
            `n     `"gitSource`": {
            `n       `"url`": `"https://github.com/sserje06/devsecops_global_configuration.git`"
                }
            `n   }
            `n }"
        $repositoryId = $createRepoResult.id
        $importGitRepoUri = "https://dev.azure.com/$organization/$projectName/_apis/git/repositories/$repositoryId/importRequests?api-version=6.0-preview.1"
        $importGitRepoResult = Invoke-RestMethod -Uri $importGitRepoUri -Headers $headerAuthorization -ContentType "application/json" -Method Post -Body $body

        If($importGitRepoResult.status -eq "queued"){
            Write-Host "The DevSecOps Global Skeleton was uploaded successfully."
        }else{
            Write-Error "There was an error loading the DevSecOps Global Skeleton - Check with the administrator."
        }
    }
    
    #--> Create Global Vars Variable Group
    $body = "{
        `n    `"variables`": {
        `n        `"glbAllowSourceBranchName`": {
        `n            `"value`": `"main,develop,feature,bugfix,release`"
        `n        },
        `n        `"gblPAT`": {
        `n            `"value`": `"$resultGetPat`",
        `n            `"isSecret`": `"true`"
        `n        },
        `n        `"gblUserPAT`": {
        `n            `"value`": `"$userMailPat`"
        `n        },
        `n        `"glbDevSecOpsRepoName`": {
        `n            `"value`": `"devsecops_global_configuration`"
        `n        },
        `n        `"glbAzDoOrganizationName`": {
        `n            `"value`": `"$organization`"
        `n        },
        `n        `"glbAzDoProjectName`": {
        `n            `"value`": `"$projectName`"
        `n        }
        `n        },
        `n        `"type`": `"Vsts`",
        `n        `"name`": `"global_vars`",
        `n        `"description`": `"DevSecOps Global Vars`"
        `n}"
    $createGlobalVarsVariableGroup = Invoke-RestMethod -Uri $createVariableGroupUri -Headers $headerAuthorization -ContentType "application/json" -Method Post -Body $body
    
    If($createGlobalVarsVariableGroup){
        Write-Host "The DevSecOps Global Vars was created successfully."
    }else{
        Write-Error "There was an error creating the DevSecOps Global Vars - Check with the administrator."
    }
}   
catch
{
    Write-Output "There was an error in the execution"
    Write-Output $_
}