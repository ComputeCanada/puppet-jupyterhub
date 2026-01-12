# @summary Class configuring a JupyterHub server with SlurmFormSpawner
# @param prefix Absolute path where JupyterHub will be installed
# @param python Python version to be installed by uv
# @param slurm_home Path to Slurm installation folder
# @param bind_url Public facing URL of the whole JupyterHub application
# @param spawner_class Class to use for spawning single-user servers
# @param authenticator_class Class name for authenticating users.
# @param idle_timeout Time in seconds after which an inactive notebook is culled
# @param traefik_version Version of traefik to install on the hub instance
# @param admin_groups List of user groups that can act as JupyterHub admin
# @param blocked_users List of users that cannot login and that jupyterhub can't sudo as
# @param jupyterhub_config_hash Custom hash merged to JupyterHub JSON main hash
# @param disable_user_config Disable per-user configuration of single-user servers
# @param packages List of extra packages to install in the hub virtual environment
# @param prometheus_token Token that Prometheus can use to scrape JupyterHub's metrics
class jupyterhub (
  Stdlib::Absolutepath $prefix,
  String $python,
  String $traefik_version,
  Stdlib::Absolutepath $slurm_home = '/opt/software/slurm',
  String $bind_url = 'https://127.0.0.1:8000',
  String $spawner_class = 'slurmformspawner.SlurmFormSpawner',
  String $authenticator_class = 'pam',
  Integer $idle_timeout = 0,
  Array[String] $admin_groups = [],
  Array[String] $blocked_users = ['root', 'toor', 'admin', 'centos', 'slurm'],
  Hash $jupyterhub_config_hash = {},
  Boolean $disable_user_config = false,
  Boolean $frozen_deps = true,
  Array[String] $packages = [],
  Optional[String] $prometheus_token = undef,
) {
  include uv::install

  user { 'jupyterhub':
    ensure  => 'present',
    groups  => 'jupyterhub',
    comment => 'JupyterHub',
    home    => '/run/jupyterhub',
    shell   => '/sbin/nologin',
    system  => true,
  }
  group { 'jupyterhub':
    ensure => 'present',
  }

  $traefik_arch = $::facts['os']['architecture'] ? {
    'x86_64' => 'amd64',
    'aarch64' => 'arm64',
  }
  archive { 'traefik':
    path            => "/opt/puppetlabs/puppet/cache/puppet-archive/traefik_v${traefik_version}_linux_${traefik_arch}.tar.gz",
    source          => "https://github.com/traefik/traefik/releases/download/v${traefik_version}/traefik_v${traefik_version}_linux_${traefik_arch}.tar.gz",
    extract         => true,
    extract_path    => '/usr/bin',
    creates         => '/usr/bin/traefik',
    extract_command => 'tar -xf %s traefik',
  }

  file { 'jupyterhub.service':
    path    => '/lib/systemd/system/jupyterhub.service',
    content => epp('jupyterhub/jupyterhub.service',
      {
        'python3_version' => $python,
        'prefix'          => $prefix,
        'slurm_home'      => $slurm_home,
      }
    ),
  }

  file { '/etc/sudoers.d/99-jupyterhub-user':
    mode    => '0440',
    content => epp('jupyterhub/99-jupyterhub-user',
      {
        'blocked_users' => $blocked_users,
        'hostname'      => $facts['networking']['hostname'],
        'slurm_home'    => $slurm_home,
      }
    ),
  }

  file { 'jupyterhub-auth':
    path   => '/etc/pam.d/jupyterhub-auth',
    source => 'puppet:///modules/jupyterhub/jupyterhub-auth',
    mode   => '0644',
  }

  file { 'jupyterhub-login':
    path    => '/etc/pam.d/jupyterhub-login',
    source  => 'puppet:///modules/jupyterhub/jupyterhub-login',
    mode    => '0644',
    require => File['jupyterhub-auth'],
  }

  file { ['/etc/jupyterhub', '/etc/jupyterhub/ssl', '/etc/jupyterhub/templates']:
    ensure => directory,
  }

  file { '/run/jupyterhub':
    ensure => directory,
    owner  => 'jupyterhub',
    group  => 'jupyterhub',
    mode   => '0755',
  }

  file { '/usr/lib/tmpfiles.d/jupyterhub.conf':
    source => 'puppet:///modules/jupyterhub/jupyterhub.conf',
    mode   => '0644',
  }

  file { '/etc/jupyterhub/templates/page.html':
    source  => 'puppet:///modules/jupyterhub/page.html',
    mode    => '0644',
    require => File['/etc/jupyterhub/templates/'],
    notify  => Service['jupyterhub'],
  }

  $announcement_port = lookup('jupyterhub::announcement::port')
  $announcement_service = {
    'name'    => 'announcement',
    # TODO: activate SSL
    # 'url'     => "https://127.0.0.1:${announcement_port}",
    'url'     => "http://127.0.0.1:${announcement_port}",
    'command' => [
      "${prefix}/bin/python",
      '-m', 'jupyterhub_announcement',
      '--AnnouncementService.config_file=/etc/jupyterhub/announcement_config.json',
    ],
    'oauth_no_confirm' => true,
  }
  $announcement_roles = [
    {
      'name'   => 'user',
      'scopes' => ['access:services', 'self']
    }
  ]

  if $idle_timeout > 0 {
    $idle_culler_services = [{
        'name'    => 'jupyterhub-idle-culler-service',
        'command' => [
          "${prefix}/bin/python3",
          '-m',
          'jupyterhub_idle_culler',
          "--timeout=${idle_timeout}",
        ],
    }]

    $idle_culler_roles = [{
        'name'    => 'jupyterhub-idle-culler-role',
        'scopes'  => ['list:users', 'read:users:activity', 'read:servers', 'delete:servers'],
        'services'=> ['jupyterhub-idle-culler-service'],
    }]
  } else {
    $idle_culler_services = []
    $idle_culler_roles = []
  }

  if $prometheus_token != undef {
    $prometheus_services = [{
        'name'      => 'prometheus',
        'api_token' => $prometheus_token,
    }]
    $prometheus_roles = [{
        'name'     => 'metrics',
        'scopes'   => ['read:metrics'],
        'services' => ['prometheus'],
    }]
  } else {
    $prometheus_services = []
    $prometheus_roles = []
  }

  $services = [$announcement_service] + $idle_culler_services + $prometheus_services
  $roles = $announcement_roles + $idle_culler_roles + $prometheus_roles

  $node_prefix = lookup('jupyterhub::node::prefix')
  $jupyterhub_config_base = parsejson(file('jupyterhub/jupyterhub_config.json'))
  $kernel_setup = lookup('jupyterhub::kernel::install_method')
  $kernel_prefix = lookup('jupyterhub::kernel::venv::prefix')
  $prologue = $kernel_setup ? {
    'venv'   => "export JUPYTER_PATH=${kernel_prefix}/puppet-jupyter:\${JUPYTER_PATH:-}; export VIRTUAL_ENV_DISABLE_PROMPT=1; source ${kernel_prefix}/bin/activate",
    'none' => '',
  }
  $jupyterhub_config_params = {
    'JupyterHub' => {
      'bind_url'                    => $bind_url,
      'authenticator_class'         => $authenticator_class,
      'spawner_class'               => $spawner_class,
      'admin_access'                => Boolean(size($admin_groups) > 0),
      'services'                    => $services,
      'load_roles'                  => $roles,
    },
    'Authenticator' => {
      'admin_groups'  => $admin_groups,
      'allow_all'     => true,
      'blocked_users' => $blocked_users,
    },
    'Spawner' => {
      'disable_user_config' => $disable_user_config,
      'cmd' => "${node_prefix}/bin/jupyterhub-singleuser",
    },
    'BatchSpawnerBase' => {
      'batchspawner_singleuser_cmd' => "${node_prefix}/bin/batchspawner-singleuser",
    },
    'SlurmSpawner' => {
      'exec_prefix'      => '',
      'env_keep'         => [],
      'batch_submit_cmd' => "sudo --preserve-env={keepvars} -u {username} ${slurm_home}/bin/sbatch --parsable",
      'batch_cancel_cmd' => "sudo -u {username} ${slurm_home}/bin/scancel {job_id}",
      'req_prologue'     => $prologue,
    },
    'SlurmFormSpawner' => {
      'slurm_bin_path' => "${slurm_home}/bin",
    },
  }

  $jupyterhub_config = deep_merge(
    $jupyterhub_config_base,
    $jupyterhub_config_params,
    $jupyterhub_config_hash,
  )

  $announcement_config = {
    'AnnouncementService' => {
      'fixed_message'      => lookup('jupyterhub::announcement::fixed_message'),
      'cookie_secret_file' => '/var/run/jupyterhub/jupyterhub_cookie_secret',
      'port'               => lookup('jupyterhub::announcement::port'),
    },
    'AnnouncementQueue' => {
      'lifetime_days' => lookup('jupyterhub::announcement::lifetime_days'),
      'persist_path'  => lookup('jupyterhub::announcement::persist_path'),
    },
    'SSLContext' => {
      # TODO: add missing SSL CA
      # 'certfile' => '/etc/jupyterhub/ssl/cert.pem',
      # 'keyfile' => '/etc/jupyterhub/ssl/key.pem'
    },
  }

  file { 'jupyterhub_config.json':
    path    => '/etc/jupyterhub/jupyterhub_config.json',
    content => to_json_pretty($jupyterhub_config, true),
    mode    => '0640',
    owner   => 'root',
    group   => 'jupyterhub',
    require => User['jupyterhub'],
  }

  file { 'announcement_config.json':
    path    => '/etc/jupyterhub/announcement_config.json',
    content => to_json_pretty($announcement_config, true),
    mode    => '0640',
    owner   => 'root',
    group   => 'jupyterhub',
    require => User['jupyterhub'],
  }

  $submit_additions = lookup('jupyterhub::submit::additions', String, undef, '')
  file { 'submit.sh':
    path    => '/etc/jupyterhub/submit.sh',
    content => epp('jupyterhub/submit.sh', {
        'prologue'  => $prologue,
        'additions' => $submit_additions,
    }),
    mode    => '0644',
  }

  # JupyterHub virtual environment
  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_version = lookup('jupyterhub::batchspawner::version')
  $jupyterhub_traefik_proxy_version = lookup('jupyterhub::jupyterhub_traefik_proxy::version')
  $oauthenticator_version = lookup('jupyterhub::oauthenticator::version')
  $ltiauthenticator_version = lookup('jupyterhub::ltiauthenticator::version')
  $pamela_version = lookup('jupyterhub::pamela::version')
  $pammfauthenticator_version = lookup('jupyterhub::pammfauthenticator::version')
  $oauth2freeipa_version = lookup('jupyterhub::oauth2freeipa::version')
  $idle_culler_version = lookup('jupyterhub::idle_culler::version')
  $announcement_version = lookup('jupyterhub::announcement::version')
  $slurmformspawner_version = lookup('jupyterhub::slurmformspawner::version')
  $wrapspawner_version = lookup('jupyterhub::wrapspawner::version')

  uv::venv { 'hub':
    prefix       => $prefix,
    python       => $python,
    requirements => epp('jupyterhub/hub-requirements.txt', {
        'jupyterhub_version'               => $jupyterhub_version,
        'batchspawner_version'             => $batchspawner_version,
        'slurmformspawner_version'         => $slurmformspawner_version,
        'wrapspawner_version'              => $wrapspawner_version,
        'oauthenticator_version'           => $oauthenticator_version,
        'ltiauthenticator_version'         => $ltiauthenticator_version,
        'oauth2freeipa_version'            => $oauth2freeipa_version,
        'pamela_version'                   => $pamela_version,
        'pammfauthenticator_version'       => $pammfauthenticator_version,
        'idle_culler_version'              => $idle_culler_version,
        'announcement_version'             => $announcement_version,
        'jupyterhub_traefik_proxy_version' => $jupyterhub_traefik_proxy_version,
        'frozen_deps'                      => $frozen_deps,
        'extra_packages'                   => $packages,
    }),
  }

  exec { 'create_self_signed_sslcert':
    command => "openssl req -newkey rsa:4096 -nodes -keyout key.pem -x509 -days 3650 -out cert.pem -subj '/CN=${facts['networking']['fqdn']}'",
    cwd     => '/etc/jupyterhub/ssl',
    creates => ['/etc/jupyterhub/ssl/key.pem', '/etc/jupyterhub/ssl/cert.pem'],
    path    => ['/usr/bin', '/usr/sbin'],
    umask   => '037',
  }

  file { '/etc/jupyterhub/ssl/cert.pem':
    mode    => '0644',
    require => [Exec['create_self_signed_sslcert']],
  }

  file { '/etc/jupyterhub/ssl/key.pem':
    mode    => '0640',
    group   => 'jupyterhub',
    require => [Exec['create_self_signed_sslcert']],
  }

  service { 'jupyterhub':
    ensure    => running,
    enable    => true,
    require   => File['submit.sh'],
    subscribe => [
      Archive['traefik'],
      Uv::Venv['hub'],
      File['jupyterhub-login'],
      File['jupyterhub.service'],
      File['jupyterhub_config.json'],
      File['announcement_config.json'],
      File['/etc/jupyterhub/ssl/cert.pem'],
      File['/etc/jupyterhub/ssl/key.pem'],
    ],
  }
}
