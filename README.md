# puppet-jupyterhub

The module installs, configures, and manages the JupyterHub service
with [batchspawner](https://github.com/jupyterhub/batchspawner) as a
spawner and in conjunction with the job scheduler [Slurm](https://slurm.schedmd.com/).

## Requirements

- Linux
- Slurm >= 17.x

### Hub

- The hub ports 80 and 443 need to be opened to the users incoming network (i.e: Internet).
- The hub needs to allow authentication of users through pam.
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

### compute

To install the Jupyter notebook component on the compute node:

```
include jupyterhub::node
```

If the compute nodes cannot access Internet, configure the puppet agent to use
[`http_proxy_host`](https://www.puppet.com/docs/puppet/8/configuration.html#http-proxy-host).

## Hieradata Configuration

### General options

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::jupyterhub::version` | String | JupyterHub package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::pip::version` | String | pip package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::notebook::version` | String | notebook package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::batchspawner::version` | String | Url to batchspawner source code release file | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::slurmformspawner::version` | String | slurmformspawner package version to install | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::pammfauthenticator::url` | String |  Url to pammfauthenticator source code release file | refer to [data/common.yaml](data/common.yaml) |
| `jupyterhub::jupyterhub_traefik_proxy::version` | String |  jupyterhub-traefik-proxy package version to install | refer to [data/common.yaml](data/common.yaml) |

### Hub options

| Variable | Type | Description | Default |
| -------- | :----| :-----------| ------- |
| `jupyterhub::prefix` | Stdlib::Absolutepath | Absolute path where JupyterHub will be installed | `/opt/jupyterhub` |
| `jupyterhub::bind_url` | String | Public facing URL of the whole JupyterHub application | `https://127.0.0.1:8000` |
| `jupyterhub::slurm_home` | Stdlib::Absolutepath | Path to Slurm installation folder | `/opt/software/slurm` |
| `jupyterhub::admin_groups` | Array[String] | List of user groups that can act as JupyterHub admin | `[]` |
| `jupyterhub::idle_timeout` | Integer | Time in seconds after which an inactive notebook is culled | `0 (no timeout)` |
| `jupyterhub::traefik_version` | String | Version of traefik to install on the hub instance | '2.10.4' |
| `jupyterhub::authenticator_class` | String | Class name of the authenticator JupyterHub will use | `pam` |
| `jupyterhub::jupyterhub_config_hash` | Hash | Custom hash merged to JupyterHub JSON main hash  | `{}` |
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
    partition:
      def: 'partition1'
      choices: ['partition1', 'partition2', 'partition3']
  SlurmFormSpawner:
    ui_args:
      notebook:
        name: Jupyter Notebook
        args: '/tree'
        modules: ['ipython-kernel/3.7']
      lab:
        name: JupyterLab
        modules: ['ipython-kernel/3.7']
      terminal:
        name: Terminal
        args: '/terminals/1'
      rstudio:
        name: RStudio
        args: '/rstudio'
        modules: ['gcc', 'rstudio-server']
      code-server:
        name: VS Code
        args: '/code-server'
        modules: ['code-server']
      desktop:
        name: Desktop
        url: '/Desktop'
  SlurmAPI:
    info_cache_ttl: 3600 # refresh sinfo cache at most every hour
    acct_cache_ttl: 3600 # refresh account cache at most every hour
    res_cache_ttl: 3600  # refresh reservation cache at most every hour
```

Refer to [slurmformspawner documentation](https://github.com/cmd-ntrf/slurmformspawner) for more details on each parameter.

### SlurmSpawner usage example

[`SlurmSpawner`](https://github.com/jupyterhub/batchspawner) can be used instead of SlurmFormSpawner
when job configuration with a form is not desirable:
```yaml
jupyterhub::spawner_class: "batchspawner.SlurmSpawner"
jupyterhub::jupyterhub_config_hash:
  SlurmSpawner:
    req_account: "def-sponsor00"
    req_memory: "256"
    req_nprocs: "1"
    req_runtime: "3600"
    req_options: "--oversubscribe"
    default_url: "/tree" # use nbclassic instead of lab
```

### OAuthenticator usage example

By default, puppet-jupyterhub configures the authentication with PAM, but the oauthenticator
package is readily installed.


In this example, we configure JupyterHub to authenticate with GitHub and create an account in FreeIPA.
```
jupyterhub::authenticator_class: "ipa-github"
jupyterhub::jupyterhub_config_hash:
  GitHubOAuthenticator:
    auto_login: true
    oauth_callback_url: "https://[your-domain]/hub/oauth_callback"
    client_id: "XYZ"
    client_secret: "DCBA-123-456"
```

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

### Submit addition option
| Variable | Type | Description |
| -------- | :----| :-----------|
| `jupyterhub::submit::additions` | String | bash command(s) that should be added to submit.sh |

Adds the following by default:
```sh
# Make sure Jupyter does not store its runtime in the home directory
export JUPYTER_RUNTIME_DIR=${SLURM_TMPDIR}/jupyter

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
