### Terraform basic setup
* Input file
* Main file
* Variable file

### AzureRM provider
* Versioning

### Resource group

### Data Lake Storage Gen 2 + filesystem
* Firewall
* Diagnostic logging with local-exec provider

### State file contents

### Remote backend

### --> Slides - Azure Databricks

### Networks for Databricks:
* Databricks requires 2 subnets:
    * Public, for connections out from clusters
    * Private, for connections within the clusters
* Both subnets are required to be delegated to Databricks
* Databricks Network Security Group rules are managed also by Databricks, the rules are populated when you deploy Azure Databricks with VNET injection
* All cluster nodes are connected to both subnets
* Connections to other resources are done via the public subnet

### Databricks Workspace with VNET injection

### Key Vault
* Firewall settings
    * Current IP
    * Databricks control plane IP
* Access Control List entry
* Add ADLS primary key as secret

### Add Key Vault to Databricks as Secret Scope

### Authenticate to ADLS with primary key

### Authentication with Service Principal (for more fine-grained access control)
* _Provider - Azure AD_
* Azure AD Application
* _Provider - Random_
* Create random password
* Create application
* Add secrets to Key Vault
    * Service Principal client ID
    * Service Principal secret
* Add role assignment to ADLS 
* Authenticate as Service Principal