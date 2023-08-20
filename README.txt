# tezos-node Terraform template

Get the latest rolling block hash from https://xtz-shots.io/mainnet/
Put SSH public key stanza in a text file (e.g. ssh-public-key.txt)

To start stack:

$ terraform init
$ terraform apply -var block=<latest block hash> -var public_key_file=<path to key file> [-var size=c5a.large]

The process will output the public IP address.

Tezos is installed, latest snapshot is downloaded and applied and server launched towards bootstrap.

