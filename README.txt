# tezos-node Terraform template

Get the latest rolling block hash from https://xtz-shots.io/mainnet/

To start stack:

$ terraform init
$ terraform apply -var block <latest block hash> -var ssh-public-key <path to key file> [-var size c5a.large]

The process will output the public IP address.

Tezos is installed, latest snapshot is downloaded and applied and server launched towards bootstrap.

