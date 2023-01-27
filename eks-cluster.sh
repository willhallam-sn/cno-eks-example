#!/bin/bash -x

eksctl create cluster --name $1 --region us-east-1 --zones us-east-1a,us-east-1c --with-oidc --managed
eksctl utils update-cluster-logging --enable-types=all --region=us-east-1 --cluster=$1 --approve
