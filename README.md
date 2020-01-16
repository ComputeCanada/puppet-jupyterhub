# puppet-jupyterhub

The module installs, configures, and manages the JupyterHub service
with [batchspawner](https://github.com/jupyterhub/batchspawner) as a
spawner and in conjunction with the job scheduler [Slurm](https://slurm.schedmd.com/).

## Requirements

- CentOS 7
- Slurm >= 17.x

### Hub

- The hub ports 80 and 443 need to be opened to the users incoming network (i.e: Internet).
- The hub needs to allow authentication of users through pam and sssd.
- The hub needs `Service['sssd']` to be defined by external authentication module.
- The hub must be able to talk to `slurmctld` to submit jobs on the users' behalf.
- The hub port `8081` needs to be accessible from the compute node network.
- The slurm binaries needs to be installed and accessible from `PATH` for the user `jupyterhub`,
mainly : `squeue`, `sbatch`, `sinfo`, `sacctmgr` and `scontrol`.
- The hub does not need the users to have SSH access.
- The hub does not need access to the cluster filesystem.

### Compute Node

- The computes nodes tcp ephemeral port range need to be accessible from the hub.
- Optional: configure [Compute Canada Software Stack with CVMFS](https://docs.computecanada.ca/wiki/Accessing_CVMFS)


## Setup

### hub
To install JuptyerHub with the default options:

```
include jupyterhub
```

If you want to use NGINX as a reverse proxy for the hub and configure Let's Encrypt SSL certificate:
```
include jupyterhub::reverse_proxy
````
and in your hieradata, define the domain name:
```
jupyterhub::reverse_proxy::domain_name: 'jupyter.mydomain.tld'
```

### compute

To install the Jupyter notebook component on the compute node:

```
include jupyterhub::node
```

If the compute nodes cannot access Internet, consider defining the http proxy variables :

```
class { 'jupyterhub::node':
    http_proxy  => 'http://squid.yourdomain.tld:3128',
    https_proxy => 'http://squid.yourdomain.tld:3128'
}
```

or using hieradata:

```
jupyterhub::node::http_proxy: 'http://squid.yourdomain.tld:3128'
jupyterhub::node::https_proxy: 'http://squid.yourdomain.tld:3128'
```

### yumrepo management

The hub and node class installs and configure nodejs with [puppet/nodejs](https://forge.puppet.com/puppet/nodejs).
If you want to deactivate the management of node yum repo by the nodejs module, add the following line to your
hieradata:

```
nodejs::manage_package_repo: false
```

## Hieradata Configuration

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::jupyterhub::version` | String | JupyterHub package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::batchspawner::url` | String | Url to batchspawner source code release file | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::slurmformspawner::version` | String | slurmformspawner package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::pammfauthenticator::url` | String |  Url to pammfauthenticator source code release file | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::kernel::python` | String | Local path to the Python binary that will be used as the default kernel | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::slurm_home` | String | Path to Slurm installation folder | `/opt/software/slurm` |
| `jupyterhub::allow_named_servers` | Boolean | Allow user to launch multiple notebook servers | `true` |
| `jupyterhub::named_server_limit_per_user` | Integer | Number of notebooks servers per user | `0` (unlimited) |
| `jupyterhub::enable_otp_auth` | Boolean | Enable the OTP field in authentication | `true` |
| `jupyterhub::admin_groups` | Array[String] | List of user groups that can act as JupyterHub admin | `undef` |
| `jupyterhub::idle_timeout` | Integer | Time in seconds after which an inactive notebook is culled | `undef` |
| `jupyterhub::slurmformspawner::form_params` | Hash | Hash of parameters to configure the spawner form | `undef` |

### `jupyterhub::slurmformspawner::form_params` schema
```
jupyterhub::slurmformspawner::form_params:
  runtime:
    min: Float
    def: Float
    max: Float
    step: Float
    lock: Boolean
  core:
    min: Integer
    def: Integer
    max: Integer
    step: Integer
    lock: Boolean
  mem:
    min: Integer
    def: Integer
    max: Integer
    step: Integer
    lock: Boolean
  gpus:
    def: String
    choices: List(String)
    lock: Boolean
  oversubscribe:
    def: Boolean
    lock: Boolean
  ui:
    def: String
    lock: Boolean
```

Refer to [slurmformspawner documentation](https://github.com/cmd-ntrf/slurmformspawner) for more details on each parameter.

### `jupyterhub::slurmformspawner::form_params`  example
```
jupyterhub::slurmformspawner::form_params:
  runtime:
    min: 1.0
    def: 2.0
    max: 5.0
    step: 0.5
  core:
    min: 1
    def: 2
    max: 8
    step: 1
  mem:
    min: 1024
    def: 2048
    max: 4096
    step: 512
  gpus:
    def: 'gpu:0'
    choices: ['gpu:0', 'gpu:k20:1', 'gpu:k80:1']
  oversubscribe:
    def: false
    lock: true
  ui:
    def: 'lab'
```