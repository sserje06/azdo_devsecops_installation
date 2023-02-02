#This script is in charge of uploading the repository devsecops_global_configuration to your azure devops organization
#AzDo API information https://learn.microsoft.com/en-us/rest/api/azure/devops/git/import-requests/create?view=azure-devops-rest-6.0&tabs=HTTP
#Azdo PAT information https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=Windows

read -p "Enter your name AzDo Organization: " organization
read -p "Enter Azdo Project Name: " projectName
read -s -p "Enter your AzDo PAT: " pat

#Install aditional software
version=$(jq --version)
if [ -z $version ];
then
  echo "Instaling jq..."
  apt install jq

#uri vars
uriRepoValidation="https://dev.azure.com/$organization/$projectName/_apis/git/repositories?api-version=6.0"
createRepoUri="https://dev.azure.com/$organization/$projectName/_apis/git/repositories?api-version=6.0"
uri="https://dev.azure.com/$organization/$projectName/_apis/git/repositories/{repositoryId}/importRequests?api-version=6.0-preview.1"

#header request vars
patBase64=$(echo -n $pat | base64)
headerAutorization='Authorization: Basic '$patBase64
headerContentType='Content-Type: application/json'

#body
createRepoBody=''

#-->Get repo info
resultRepoInfo=$(curl --location --request GET $uriRepoValidation --header 'Authorization: Basic '$patBase64)

#TODO
#Implement method