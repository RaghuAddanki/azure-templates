# Create a resource group
az group create \
    --name GoCloudResourceGroupSLB \
    --location eastus

# Create a public IP address
az network public-ip create --resource-group GoCloudResourceGroupSLB --name GoCloudPublicIP --sku standard

# Create the load balancer
az network lb create \
    --resource-group GoCloudResourceGroupSLB \
    --name GoCloudLoadBalancer \
    --sku standard \
    --public-ip-address GoCloudPublicIP \
    --frontend-ip-name GoCloudFrontEnd \
    --backend-pool-name GoCloudBackEndPool

#Create the health probe
az network lb probe create \
    --resource-group GoCloudResourceGroupSLB \
    --lb-name GoCloudLoadBalancer \
    --name GoCloudHealthProbe \
    --protocol tcp \
    --port 80

#Create the load balancer rule
az network lb rule create \
    --resource-group GoCloudResourceGroupSLB \
    --lb-name GoCloudLoadBalancer \
    --name GoCloudHTTPRule \
    --protocol tcp \
    --frontend-port 80 \
    --backend-port 80 \
    --frontend-ip-name GoCloudFrontEnd \
    --backend-pool-name GoCloudBackEndPool \
    --probe-name GoCloudHealthProbe

#Create a virtual network
az network vnet create \
    --resource-group GoCloudResourceGroupSLB \
    --location eastus \
    --name GoCloudVnet \
    --subnet-name GoCloudSubnet

#Create a network security group	
az network nsg create \
    --resource-group GoCloudResourceGroupSLB \
    --name GoCloudNetworkSecurityGroup
	
#Create a network security group rule
az network nsg rule create \
    --resource-group GoCloudResourceGroupSLB \
    --nsg-name GoCloudNetworkSecurityGroup \
    --name GoCloudNetworkSecurityGroupRuleHTTP \
    --protocol tcp \
    --direction inbound \
    --source-address-prefix '*' \
    --source-port-range '*' \
    --destination-address-prefix '*' \
    --destination-port-range 80 \
    --access allow \
    --priority 200

#Create NICs
for i in `seq 1 2`; do
  az network nic create \
    --resource-group GoCloudResourceGroupSLB \
    --name GoCloudNic$i \
    --vnet-name GoCloudVnet \
    --subnet GoCloudSubnet \
    --network-security-group GoCloudNetworkSecurityGroup \
    --lb-name GoCloudLoadBalancer \
    --lb-address-pools GoCloudBackEndPool
done

#Create an Availability set
az vm availability-set create \
   --resource-group GoCloudResourceGroupSLB \
   --name GoCloudAvailabilitySet

#Create two virtual machines

#Create an file called cloud-init.txt
sensible-editor cloud-init.txt
#Then pick an editor and copy the below text in it:

#cloud-config
package_upgrade: true
packages:
  - nginx
  - nodejs
  - npm
write_files:
  - owner: www-data:www-data
  - path: /etc/nginx/sites-available/default
    content: |
      server {
        listen 80;
        location / {
          proxy_pass http://localhost:3000;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection keep-alive;
          proxy_set_header Host $host;
          proxy_cache_bypass $http_upgrade;
        }
      }
  - owner: azureuser:azureuser
  - path: /home/azureuser/myapp/index.js
    content: |
      var express = require('express')
      var app = express()
      var os = require('os');
      app.get('/', function (req, res) {
        res.send('Hello World from host ' + os.hostname() + '!')
      })
      app.listen(3000, function () {
        console.log('Hello world app listening on port 3000!')
      })
runcmd:
  - service nginx restart
  - cd "/home/azureuser/myapp"
  - npm init
  - npm install express -y
  - nodejs index.js

#Create two virtual machines  
for i in `seq 1 2`; do
 az vm create \
   --resource-group GoCloudResourceGroupSLB \
   --name myVM$i \
   --availability-set GoCloudAvailabilitySet \
   --nics GoCloudNic$i \
   --image UbuntuLTS \
   --generate-ssh-keys \
   --custom-data cloud-init.txt \
   --no-wait
done

#Test the load balancer
#Obtain public IP address
az network public-ip show \
    --resource-group GoCloudResourceGroupSLB \
    --name GoCloudPublicIP \
    --query [ipAddress] \
    --output tsv

