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