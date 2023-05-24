# puppet-jupyterhub

The module installs, configures, and manages the JupyterHub service
with [batchspawner](https://github.com/jupyterhub/batchspawner) as a
spawner and in conjunction with the job scheduler [Slurm](https://slurm.schedmd.com/).

## Requirements

- CentOS 7, 8
- Slurm >= 17.x

### Hub

- The hub ports 80 and 443 need to be opened to the users incoming network (i.e: Internet).
- The hub needs to allow authentication of users through pam and sssd.
- The hub needs `Service['sssd']` to be defined by an external authentication module.
- The hub must be able to talk to `slurmctld` to submit jobs on the users' behalf.
- The hub port `8081` needs to be accessible from the compute node network.
- The slurm binaries needs to be installed and accessible from `PATH` for the user `jupyterhub`,
mainly : `squeue`, `sbatch`, `sinfo`, `sacctmgr` and `scontrol`.
- The hub does not need the users to have SSH access.
- The hub does not need access to the cluster filesystem.

### Compute Node

- The compute nodes' tcp ephemeral port range needs to be accessible from the hub.
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

### General options

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::jupyterhub::version` | String | JupyterHub package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::pip::version` | String | pip package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::notebook::version` | String | notebook package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::batchspawner::url` | String | Url to batchspawner source code release file | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::slurmformspawner::version` | String | slurmformspawner package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::pammfauthenticator::url` | String |  Url to pammfauthenticator source code release file | refer to [data/common.yaml](data/common.yaml) |

### Hub options

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::prefix` | Stdlib::Absolutepath | Absolute path where JupyterHub will be installed | `/opt/jupyterhub` |
| `jupyterhub::bind_url` | String | Public facing URL of the whole JupyterHub application | `https://127.0.0.1:8000` |
| `jupyterhub::slurm_home` | Stdlib::Absolutepath | Path to Slurm installation folder | `/opt/software/slurm` |
| `jupyterhub::allow_named_servers` | Boolean | Allow user to launch multiple notebook servers | `true` |
| `jupyterhub::admin_groups` | Array[String] | List of user groups that can act as JupyterHub admin | `[]` |
| `jupyterhub::named_server_limit_per_user` | Integer | Number of notebooks servers per user | `0` (unlimited) |
| `jupyterhub::idle_timeout` | Integer | Time in seconds after which an inactive notebook is culled | `0 (no timeout)` |
| `jupyterhub::authenticator` | Enum['PAM', 'OIDC'] | Type of authenticator JupyterHub will use | `PAM` |
| `jupyterhub::enable_otp_auth` | Boolean | Enable one-time password field on the login page | `true` |
| `jupyterhub::jupyterhub_config_hash` | Hash | Custom hash merged to JupyterHub JSON main hash  | `{}` |
| `jupyterhub::slurm_partitions` | List[String] | Name of the partitions for the ressource allocation of JupyterHub jobs  | `[]` |
| `jupyterhub::blocked_users` | List[String] | List of users that cannot login | `['root', 'toor', 'admin', 'centos', 'slurm']` |
| `jupyterhub::prometheus_token` | String | Token that Prometheus can use to scrape JupyterHub's metrics | `undef` |

### Announcement options

puppet-jupyterhub installs the service [jupyterhub-announcement](https://github.com/rcthomas/jupyterhub-announcement) to broadcast messages for the users once connected to the hub.

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::announcement::port` | Integer | Localhost port the service will listen on | 8888 |
| `jupyterhub::announcement::fixed_message` | String | Message that will always be displayed | '' |
| `jupyterhub::announcement::lifetime_days `| Integer | Announcement duration in days | 7 |
| `jupyterhub::announcement::persist_path` | String | File where current and past annoucements are stored | /var/run/jupyterhub/announcements.json |


### Compute node options

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::node::prefix` | Stdlib::Absolutepath | Absolute path where Jupyter Notebook and jupyterhub-singleuser will be installed | `/opt/jupyterhub` |
| `jupyterhub::kernel::setup` | Enum['venv', 'module'] | Determine if the Python kernel is provided by a local virtual environment or a module | `module` |
| `jupyterhub::kernel::venv::prefix` | Stdlib::Absolutepath | Absolute path where the IPython kernel virtual environment will be installed | `/opt/ipython-kernel` |
| `jupyterhub::kernel::venv::python` | Stdlib::Absolutepath | Absolute path to the Python binary that will be used as the default kernel | `/usr/bin/python3` |
| `jupyterhub::kernel::venv::pip_environment`| Hash[String, String] | Hash of environment variables configured before calling installing `venv::packages` | `{}` |
| `jupyterhub::kernel::venv::packages` | Array[String] | Python packages to install in the default kernel | `[]` |

### Reverse proxy options

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::reverse_proxy::domain_name` | Variant[String, Array[String]] | Domain name(s) that will be used to access JupyterHub. | |
| `jupyterhub::reverse_proxy::ssl_certificate_path` | Stdlib::Absolutepath | Path to SSL certificate fullchain PEM file when letsencrypt::enable is false. | `''` |
| `jupyterhub::reverse_proxy::ssl_certificate_key_path` | Stdlib::Absolutepath | Path to SSL certificate key PEM file when letsencrypt::enable is false. | `''` |
| `jupyterhub::reverse_proxy::letsencrypt::enable` | Boolean | Use Let's Encrypt to issue and renew SSL certificate for JupyterHub | `true` |
| `jupyterhub::reverse_proxy::letsencrypt::renew_cron_ensure` | Enum['present', 'absent'] | Enable cron to renew SSL certificate | `present` |
| `jupyterhub::reverse_proxy::letsencrypt::unsafe_registration` | Boolean | Disable registration of SSL certificate with email | `true` |
| `jupyterhub::reverse_proxy::letsencrypt::email` | String | Registration email if `unsafe_registration` is false | `null` |
| `jupyterhub::reverse_proxy::letsencrypt::certonly::plugin` | String | Letsencrypt plugin that should be used when issuing and renewing the certicifate | `standalone` |

### SlurmFormSpawner's options

To control SlurmFormSpawner options, use `jupyterhub::jupyterhub_config_hash` like this:

```
jupyterhub::jupyterhub_config_hash:
  SbatchForm:
    account:
      def: 'def-account'
    runtime:
      min: 1.0
      def: 2.0
      max: 5.0
    nprocs:
      min: 1
      def: 2
      max: 8
    memory:
      min: 1024
      max: 2048
    gpus:
      def: 'gpu:0'
      choices: ['gpu:0', 'gpu:k20:1', 'gpu:k80:1']
    oversubscribe:
      def: false
      lock: true
    ui:
      def: 'lab'
      choices: ['lab', 'notebook', 'terminal', 'rstudio', 'code-server', 'desktop']
  SlurmFormSpawner:
    ui_args:
      notebook:
        name: Jupyter Notebook
        args: ['--SingleUserNotebookApp.default_url=/tree']
        modules: ['ipython-kernel/3.7']
      lab:
        name: JupyterLab
        modules: ['ipython-kernel/3.7']
      terminal:
        name: Terminal
        args: ['--SingleUserNotebookApp.default_url=/terminals/1']
      rstudio:
        name: RStudio
        args: ['--SingleUserNotebookApp.default_url=/rstudio']
        modules: ['gcc', 'rstudio-server']
      code-server:
        name: VS Code
        args: ['--SingleUserNotebookApp.default_url=/code-server']
        modules: ['code-server']
      desktop:
        name: Desktop
        args: ['--SingleUserNotebookApp.default_url=/Desktop']
  SlurmAPI:
    info_cache_ttl: 3600 # refresh sinfo cache at most every hour
    acct_cache_ttl: 3600 # refresh account cache at most every hour
    res_cache_ttl: 3600  # refresh reservation cache at most every hour
```

Refer to [slurmformspawner documentation](https://github.com/cmd-ntrf/slurmformspawner) for more details on each parameter.

### Jupyter Notebook options

To control options and traitlets of Jupyter Notebook and its extensions, use `jupyterhub::jupyter_notebook_config_hash` like this:
```
jupyterhub::jupyter_notebook_config_hash:
  ServerProxy:
    servers:
      rstudio:
        command: ["rserver", "--www-port={port}", "--www-frame=same", "--www-address=127.0.0.1"]
        timeout: 30
        launcher_entry:
          title: RStudio
      code-server:
        command: ["code-server", "--auth=none", "--disable-telemetry", "--host=127.0.0.1", "--port={port}"]
        timeout: 30
        launcher_entry:
          title: VS Code
      openrefine:
        command: ["refine"]
        timeout: 30
        launcher_entry:
          title: OpenRefine
```
### OIDC authentication options
*set `jupyterhub::authenticator` to `OIDC`
| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::oauthenticator::client_id` | String | OIDC client ID | |
| `jupyterhub::oauthenticator::client_secret` | String | OIDC client secret | |
| `jupyterhub::oauthenticator::authorize_url` | String | OIDC authorize URL | |
| `jupyterhub::oauthenticator::token_url` | String | OIDC token URL | |
| `jupyterhub::oauthenticator::userdata_url` | String | OIDC userdata URL | |
| `jupyterhub::oauthenticator::userdata_params` | Hash | OIDC userdata params | {'state' => 'state'} |
| `jupyterhub::oauthenticator::oauth_callback_url` | String | OIDC oauth callback URL | |
| `jupyterhub::oauthenticator::username_key` | String | OIDC username key | |
| `jupyterhub::oauthenticator::scope` | Array[String] | OIDC scope | |
| `jupyterhub::oauthenticator::allowed_groups` | Array[String] | List of groups who should be allowed to connect. Empty list = any group | [] |
| `jupyterhub::oauthenticator::claim_groups_key` | String | Userdata groups claim key from returned  OIDC json | 'affiliation' |

### Submit addition option
| Variable | Type | Description |
| -------- | :----| :-----------|
| `jupyterhub::submit::additions` | String | bash command(s) that should be added to submit.sh |

Adds the following by default:
```sh
unset XDG_RUNTIME_DIR

# Disable variable export with sbatch
export SBATCH_EXPORT=NONE
# Avoid steps inheriting environment export
# settings from the sbatch command
unset SLURM_EXPORT_ENV

# Setup user pip install folder
export PIP_PREFIX=${SLURM_TMPDIR}
export PATH="${PIP_PREFIX}/bin":${PATH}
export PYTHONPATH=${PYTHONPATH}:"/opt/jupyterhub/lib/usercustomize"

# Make sure the environment-level directories does not
# have priority over user-level directories for config and data.
# Jupyter core is trying to be smart with virtual environments
# and it is not doing the right thing in our case.
export JUPYTER_PREFER_ENV_PATH=0
```
