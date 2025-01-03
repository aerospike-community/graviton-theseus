## Getting Started

### Create an AWS Instance Profile

For AWS boxes first create an instance profile

```shell
aws iam create-role --role-name aerospike-par-eng-aerolab \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'
```

```shell
aws iam attach-role-policy --role-name aerospike-par-eng-aerolab \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-role-policy --role-name aerospike-par-eng-aerolab \
  --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess
aws iam attach-role-policy --role-name aerospike-par-eng-aerolab \
  --policy-arn arn:aws:iam::aws:policy/AWSPriceListServiceFullAccess
```

```shell
aws iam create-instance-profile --instance-profile-name aerospike-par-eng-aerolab
```

```shell
aws iam add-role-to-instance-profile --instance-profile-name aerospike-par-eng-aerolab \
  --role-name aerospike-par-eng-aerolab
```

Now, export the instance profile name so it will be used in the bootstrap script, as well as configure aerolab to use
your aws credentials

Make sure aws is configured to use `us-east-1`

```shell
aws configure
```


### Configure aerolab

```shell
export AWS_INSTANCE_PROFILE=aerospike-par-eng-aerolab
aerolab config backend -t aws -r us-east-1
```

# Jumpbox Setup and Operation

## Deploy the jumpbox

```bash
./project-scripts/jumpbox-bootstrap
```

You can then log into the cluster using the commands on the screen.

## One Time Setup

1. Move into the graviton-theseus folder
   ```bash
   cd /workspace/graviton-theseus
   ```
1. Configure project overrides
   ```bash
   vi ./project-ansible/overrides.yaml
   ```
1. Configure the jumpbox
   ```bash
   ./00-configure-jumpbox
   ```
1. Reboot the jumpbox

## Deploy the clusters

### Choose target cluster type

Graviton 2 cluster:

```bash
source project-config/g2_target
```

Graviton 4 cluster:

```bash
source project-config/g4_target
```

### Deploy an Aerospike cluster

```bash
./01-deploy-target-cluster
```

### Deploy a load generation server

```bash
./02-deploy-lgs-cluster
```

## Hydrate

```bash
./10-hydrate
```

## Start the workload

```bash
./11-run-workload
```

## Destroy the cluster

```bash
par-exec🔬 -- 99-destroy
```
