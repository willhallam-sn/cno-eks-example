#!/bin/python3

# parse our JSON list of clusters, build any which are missing and deploy CNO to them

import boto3
from botocore.exceptions import ClientError
import json
import os
import subprocess


f=open("clusters.json")
clusterDict=json.loads(f.read())

# create an eks inventory 
eksInv={}

secret_name = "cno-secret-1"
region_name = "us-east-1"

# Create a Secrets Manager client
session = boto3.session.Session()
client = session.client(
    service_name='secretsmanager',
    region_name=region_name
)

try:
    get_secret_value_response = client.get_secret_value( SecretId=secret_name)
except ClientError as e:
    # For a list of exceptions thrown, see
    # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
    raise e

# Decrypts secret using the associated KMS key.
secret = json.loads(get_secret_value_response['SecretString'])

# define env vars based on secrets
os.environ["INSTANCE_PASSWORD"]=secret["instance_password"]
os.environ["API_KEY"]=secret["api_key"]
os.environ["INSTANCE"]=secret["instance"]

# use eksctl to list all clusters
stream = os.popen('eksctl get cluster -o json')
eksDict=json.loads(stream.read())
for eks in eksDict:
    print("EKS cluster found: "+eks["Name"])
    eksInv[eks["Name"]]=eks["Name"]

for cluster in clusterDict["clusters"]:

    print("Cluster is "+cluster["name"])
    if not (cluster["name"] in eksInv):
        # cluster does not exist, run build script
        print("Building cluster "+cluster["name"])
        process = subprocess.Popen(['./eks-cluster.sh', cluster["name"]], stdout=subprocess.PIPE, universal_newlines=True)
        #process = subprocess.Popen(['/bin/true'], stdout=subprocess.PIPE, universal_newlines=True)

        while True:
            output = process.stdout.readline()
            print(output.strip())
            # Do something else
            return_code = process.poll()
            if return_code is not None:
                print('RETURN CODE', return_code)
                # Process has finished, read rest of the output 
                for output in process.stdout.readlines():
                    print(output.strip())
                break
    
        # add federated admin role
        if return_code==0:
            print("Adding federated admin role to "+cluster["name"])
            process = subprocess.Popen(['eksctl','create','iamidentitymapping','--cluster',cluster["name"],"--arn","arn:aws:iam::<account id>:role/<federated role name>","--username","fed-admin"], stdout=subprocess.PIPE, universal_newlines=True)
            #process = subprocess.Popen(['/bin/true'], stdout=subprocess.PIPE, universal_newlines=True)

            while True:
                output = process.stdout.readline()
                print(output.strip())
                # Do something else
                return_code = process.poll()
                if return_code is not None:
                    print('RETURN CODE', return_code)
                    # Process has finished, read rest of the output 
                    for output in process.stdout.readlines():
                        print(output.strip())
                    break

        # add IAM admin role
        if return_code==0:
            print("Adding iam admin role to "+cluster["name"])
            process = subprocess.Popen(['eksctl','create','iamidentitymapping','--cluster',cluster["name"],"--arn","arn:aws:iam::<account id>:user/<my user>","--username","local-admin"], stdout=subprocess.PIPE, universal_newlines=True)
            #process = subprocess.Popen(['/bin/true'], stdout=subprocess.PIPE, universal_newlines=True)

            while True:
                output = process.stdout.readline()
                print(output.strip())
                # Do something else
                return_code = process.poll()
                if return_code is not None:
                    print('RETURN CODE', return_code)
                    # Process has finished, read rest of the output 
                    for output in process.stdout.readlines():
                        print(output.strip())
                    break

        # add role bindings
        if return_code==0:
            print("Adding federated admin role to "+cluster["name"])
            process = subprocess.Popen(['kubectl','apply','-f','admin-clusterrolebinding.yml'], stdout=subprocess.PIPE, universal_newlines=True)
            #process = subprocess.Popen(['/bin/true'], stdout=subprocess.PIPE, universal_newlines=True)

            while True:
                output = process.stdout.readline()
                print(output.strip())
                # Do something else
                return_code = process.poll()
                if return_code is not None:
                    print('RETURN CODE', return_code)
                    # Process has finished, read rest of the output 
                    for output in process.stdout.readlines():
                        print(output.strip())
                    break

        # add EBS role
        if return_code==0:
            print("Adding EBS addon role to "+cluster["name"])
            process = subprocess.Popen(['eksctl','create','iamserviceaccount','--name','ebs-csi-controller-sa','--namespace','kube-system','--cluster',cluster["name"],'--attach-policy-arn','arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy','--approve','--role-only','--role-name', 'AmazonEKS_EBS_CSI_DriverRole-'+cluster["name"]], stdout=subprocess.PIPE, universal_newlines=True)
            #process = subprocess.Popen(['/bin/true'], stdout=subprocess.PIPE, universal_newlines=True)

            while True:
                output = process.stdout.readline()
                print(output.strip())
                # Do something else
                return_code = process.poll()
                if return_code is not None:
                    print('RETURN CODE', return_code)
                    # Process has finished, read rest of the output 
                    for output in process.stdout.readlines():
                        print(output.strip())
                    break


        # add EBS addon
        if return_code==0:
            print("Adding EBS addon to "+cluster["name"])
            process = subprocess.Popen(['eksctl','create','addon','--name','aws-ebs-csi-driver','--cluster',cluster["name"],'--service-account-role-arn','arn:aws:iam::<account id>:role/AmazonEKS_EBS_CSI_DriverRole-'+cluster["name"],'--force'], stdout=subprocess.PIPE, universal_newlines=True)
            #process = subprocess.Popen(['/bin/true'], stdout=subprocess.PIPE, universal_newlines=True)

            while True:
                output = process.stdout.readline()
                print(output.strip())
                # Do something else
                return_code = process.poll()
                if return_code is not None:
                    print('RETURN CODE', return_code)
                    # Process has finished, read rest of the output 
                    for output in process.stdout.readlines():
                        print(output.strip())
                    break

        # invoke CNO deploy script if eksctl succeeds
        if return_code==0:
            print("Enrolling cluster "+cluster["name"])
            process = subprocess.Popen(['./sn_app_deploy.sh'], stdout=subprocess.PIPE, universal_newlines=True)

            while True:
                output = process.stdout.readline()
                print(output.strip())
                # Do something else
                return_code = process.poll()
                if return_code is not None:
                    print('RETURN CODE', return_code)
                    # Process has finished, read rest of the output 
                    for output in process.stdout.readlines():
                        print(output.strip())
                    break
