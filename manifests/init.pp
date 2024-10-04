# @summary Class configuring a JupyterHub server with SlurmFormSpawner
# @param prefix Absolute path where JupyterHub will be installed
# @param slurm_home Path to Slurm installation folder
# @param bind_url Public facing URL of the whole JupyterHub application
# @param allow_named_servers Allow user to launch multiple notebook servers
# @param named_server_limit_per_user Number of notebooks servers per user
# @param authenticator Type of authenticator JupyterHub will use
# @param enable_otp_auth Enable one-time password field on the login page
# @param idle_timeout Time in seconds after which an inactive notebook is culled
# @param traefik_version Version of traefik to install on the hub instance
# @param admin_groups List of user groups that can act as JupyterHub admin
# @param blocked_users List of users that cannot login
# @param jupyterhub_config_hash Custom hash merged to JupyterHub JSON main hash
# @param prometheus_token Token that Prometheus can use to scrape JupyterHub's metrics
class jupyterhub (
  Stdlib::Absolutepath $prefix = '/opt/jupyterhub',
  Stdlib::Absolutepath $slurm_home = '/opt/software/slurm',
  String $bind_url = 'https://127.0.0.1:8000',
  Boolean $allow_named_servers = true,
  Integer $named_server_limit_per_user = 0,
  Enum['PAM', 'OIDC'] $authenticator = 'PAM',
  Boolean $enable_otp_auth = true,
  Boolean $create_user = false,
  Integer $idle_timeout = 0,
  String $traefik_version = '2.10.4',
  Array[String] $admin_groups = [],
  Array[String] $blocked_users = ['root', 'toor', 'admin', 'centos', 'slurm'],
  Hash $jupyterhub_config_hash = {},
  Optional[String] $prometheus_token = undef,
) {
  ensure_resource('class', 'jupyterhub::base', { 'prefix' => $prefix })

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

  $python3_version = lookup('jupyterhub::python3::version')
  file { 'jupyterhub.service':
    path    => '/lib/systemd/system/jupyterhub.service',
    content => epp('jupyterhub/jupyterhub.service',
      {
        'python3_version' => $python3_version,
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

  $idle_culler_version = lookup('jupyterhub::idle_culler::version')
  $announcement_version = lookup('jupyterhub::announcement::version')
  $slurmformspawner_version = lookup('jupyterhub::slurmformspawner::version')

  if $authenticator == 'PAM' {
    $authenticator_config = {
      'PAMAuthenticator' => {
        'open_sessions' => false,
        'service'       => 'jupyterhub-login',
      },
    }
    if $enable_otp_auth {
      $authenticator_class = 'pammfauthenticator'
    } else {
      $authenticator_class = 'pam'
    }
  } elsif $authenticator == 'OIDC' {
    if $create_user {
      $authenticator_class = 'oauth2freeipa.LocalFreeIPAGenericOAuthenticator'
    } else {
      $authenticator_class = 'oauthenticator.generic.GenericOAuthenticator'
    }
    $authenticator_config = {
      'GenericOAuthenticator' => {
        'client_id'           => lookup('jupyterhub::oauthenticator::client_id'),
        'client_secret'       => lookup('jupyterhub::oauthenticator::client_secret'),
        'authorize_url'       => lookup('jupyterhub::oauthenticator::authorize_url'),
        'token_url'           => lookup('jupyterhub::oauthenticator::token_url'),
        'userdata_url'        => lookup('jupyterhub::oauthenticator::userdata_url'),
        'userdata_params'     => lookup('jupyterhub::oauthenticator::userdata_params', Hash, undef, { 'state' => 'state' }),
        'oauth_callback_url'  => lookup('jupyterhub::oauthenticator::oauth_callback_url'),
        'logout_redirect_url' => lookup('jupyterhub::oauthenticator::logout_redirect_url', String, undef, ''),
        'username_key'        => lookup('jupyterhub::oauthenticator::username_key'),
        'scope'               => lookup('jupyterhub::oauthenticator::scope'),
        'allowed_groups'      => lookup('jupyterhub::oauthenticator::allowed_groups', Array[String], undef, []),
        'claim_groups_key'    => lookup('jupyterhub::oauthenticator::claim_groups_key', String, undef, 'affiliation'),
      },
    }
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

  $node_prefix = lookup('jupyterhub::node::prefix', String, undef, $prefix)
  $jupyterhub_config_base = parsejson(file('jupyterhub/jupyterhub_config.json'))
  $jupyterhub_config_params = {
    'JupyterHub' => {
      'bind_url'                    => $bind_url,
      'allow_named_servers'         => $allow_named_servers,
      'named_server_limit_per_user' => $named_server_limit_per_user,
      'authenticator_class'         => $authenticator_class,
      'admin_access'                => Boolean(size($admin_groups) > 0),
      'services'                    => $services,
      'load_roles'                  => $roles,
    },
    'Authenticator' => {
      'admin_groups'  => $admin_groups,
      'blocked_users' => $blocked_users,
      'auto_login'    => $authenticator ? {
        'OIDC'  => true,
        default => false,
      },
    },
    'LocalAuthenticator' => {
      'create_system_users' => $create_user,
    },
    'SlurmFormSpawner' => {
      'batchspawner_singleuser_cmd' => "${node_prefix}/bin/batchspawner-singleuser",
      'cmd'                         => "${node_prefix}/bin/jupyterhub-singleuser",
      'slurm_bin_path'              => "${slurm_home}/bin",
    },
  }

  $jupyterhub_config = deep_merge(
    $jupyterhub_config_base,
    $jupyterhub_config_params,
    $jupyterhub_config_hash,
    $authenticator_config,
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

  $kernel_setup = lookup('jupyterhub::kernel::setup', Enum['venv', 'module'], undef, 'venv')
  $module_list = lookup('jupyterhub::kernel::module::list', Array[String], undef, [])
  $venv_prefix = lookup('jupyterhub::kernel::venv::prefix', String, undef, '/opt/ipython-kernel')
  $submit_additions = lookup('jupyterhub::submit::additions', String, undef, '')
  file { 'submit.sh':
    path    => '/etc/jupyterhub/submit.sh',
    content => epp('jupyterhub/submit.sh', {
        'kernel_setup' => $kernel_setup,
        'module_list'  => join($module_list, ' '),
        'node_prefix'  => $node_prefix,
        'venv_prefix'  => $venv_prefix,
        'additions'    => $submit_additions,
    }),
    mode    => '0644',
  }

  # JupyterHub virtual environment
  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_version = lookup('jupyterhub::batchspawner::version')
  $jupyterhub_traefik_proxy_version = lookup('jupyterhub::jupyterhub_traefik_proxy::version')

  file { "${prefix}/hub-requirements.txt":
    content => epp('jupyterhub/hub-requirements.txt', {
        'jupyterhub_version'               => $jupyterhub_version,
        'batchspawner_version'             => $batchspawner_version,
        'slurmformspawner_version'         => $slurmformspawner_version,
        'idle_culler_version'              => $idle_culler_version,
        'announcement_version'             => $announcement_version,
        'jupyterhub_traefik_proxy_version' => $jupyterhub_traefik_proxy_version,
    }),
    mode    => '0644',
  }

  exec { 'pip_install_venv':
    command     => "pip install -r ${prefix}/hub-requirements.txt",
    path        => ["${prefix}/bin", '/usr/bin', '/bin'],
    require     => Exec['jupyterhub_venv'],
    subscribe   => File["${prefix}/hub-requirements.txt"],
    refreshonly => true,
  }

  if $authenticator == 'PAM' {
    $pamela_version = lookup('jupyterhub::pamela::version')
    exec { 'pip_pamela':
      command => "${prefix}/bin/pip install --no-cache-dir pamela==${pamela_version}",
      creates => "${prefix}/lib/python${python3_version}/site-packages/pamela-${pamela_version}.dist-info/",
      require => Exec['pip_install_venv'],
    }
    if $enable_otp_auth {
      $pammfauthenticator_url = lookup('jupyterhub::pammfauthenticator::url')
      exec { 'pip_pammfauthenticator':
        command => "${prefix}/bin/pip install --no-cache-dir ${pammfauthenticator_url}",
        creates => "${prefix}/lib/python${python3_version}/site-packages/pammfauthenticator/",
        require => [Exec['pip_install_venv'], Exec['pip_pamela']],
        notify  => Service['jupyterhub'],
      }
    }
  } elsif $authenticator == 'OIDC' {
    $oauthenticator_version = lookup('jupyterhub::oauthenticator::version')
    exec { 'pip_oauthenticator':
      command => "${prefix}/bin/pip install --no-cache-dir oauthenticator==${oauthenticator_version}",
      creates => "${prefix}/lib/python${python3_version}/site-packages/oauthenticator-${oauthenticator_version}.dist-info/",
      require => Exec['pip_install_venv'],
    }
    if $create_user {
      exec { 'pip_oauth2freeipa':
        command => "${prefix}/bin/pip install https://github.com/MagicCastle/oauth2freeipa/archive/refs/tags/v1.0.0.zip",
        creates => "${prefix}/lib/python${python3_version}/site-packages/oauth2freeipa/",
        require => Exec['pip_install_venv'],
      }
    }
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

  if $facts['os']['release']['major'] == '7' {
    $pycurl_package_name = lookup('jupyterhub::pycurl::package_name')
    ensure_packages ($pycurl_package_name)
    $jupyterhub_require = [
      File['submit.sh'],
      Package[$pycurl_package_name],
    ]
  } else {
    $jupyterhub_require = [
      File['submit.sh'],
    ]
  }

  service { 'jupyterhub':
    ensure    => running,
    enable    => true,
    require   => $jupyterhub_require,
    subscribe => [
      Archive['traefik'],
      Exec['pip_install_venv'],
      File['jupyterhub-login'],
      File['jupyterhub.service'],
      File['jupyterhub_config.json'],
      File['announcement_config.json'],
      File['/etc/jupyterhub/ssl/cert.pem'],
      File['/etc/jupyterhub/ssl/key.pem'],
    ],
  }
}
