class jupyterhub (
  Stdlib::Absolutepath $prefix = '/opt/jupyterhub',
  Stdlib::Absolutepath $slurm_home = '/opt/software/slurm',
  String $bind_url = 'https://127.0.0.1:8000',
  Boolean $allow_named_servers = true,
  Integer $named_server_limit_per_user = 0,
  Enum['PAM', 'OIDC'] $authenticator = 'PAM',
  Boolean $enable_otp_auth = true,
  Integer $idle_timeout = 0,
  Optional[Array[String]] $admin_groups = [],
  Optional[Array[String]] $blocked_users = ['root', 'toor', 'admin', 'centos', 'slurm'],
  Optional[Hash] $jupyterhub_config_hash = {},
  Optional[Array[String]] $slurm_partitions = [],
) {

  class { 'jupyterhub::base':
    prefix => $prefix
  }

  user { 'jupyterhub':
    ensure  => 'present',
    groups  => 'jupyterhub',
    comment => 'JupyterHub',
    home    => '/run/jupyterhub',
    shell   => '/sbin/nologin',
    system  => true
  }
  group { 'jupyterhub':
    ensure => 'present'
  }

  package { 'configurable-http-proxy':
    ensure   => 'installed',
    provider => 'npm'
  }

  file { 'jupyterhub.service':
    ensure => 'present',
    path   => '/lib/systemd/system/jupyterhub.service',
    source => 'puppet:///modules/jupyterhub/jupyterhub.service'
  }

  file { '/etc/sudoers.d/99-jupyterhub-user':
    ensure  => 'present',
    mode    => '0440',
    content => epp('jupyterhub/99-jupyterhub-user', {
      'blocked_users' => $blocked_users,
      'hostname'      => $facts['hostname'],
      'slurm_home'    => $slurm_home,
    })
  }

  file { 'jupyterhub-auth':
    ensure => 'present',
    path   => '/etc/pam.d/jupyterhub-auth',
    source => 'puppet:///modules/jupyterhub/jupyterhub-auth',
    mode   => '0644'
  }

  file { 'jupyterhub-login':
    ensure  => 'present',
    path    => '/etc/pam.d/jupyterhub-login',
    source  => 'puppet:///modules/jupyterhub/jupyterhub-login',
    mode    => '0644',
    require => File['jupyterhub-auth']
  }

  file { ['/etc/jupyterhub', '/etc/jupyterhub/ssl', '/etc/jupyterhub/templates']:
    ensure => directory
  }

  file { '/run/jupyterhub':
    ensure => directory,
    owner  => 'jupyterhub',
    group  => 'jupyterhub',
    mode   => '0755'
  }

  file { '/usr/lib/tmpfiles.d/jupyterhub.conf':
    ensure => 'present',
    source => 'puppet:///modules/jupyterhub/jupyterhub.conf',
    mode   => '0644',
  }

  $idle_culler_version = lookup('jupyterhub::idle_culler::version')
  $slurmformspawner_version = lookup('jupyterhub::slurmformspawner::version')

  if $authenticator == 'PAM' {
    $authenticator_config = {
      'PAMAuthenticator' => {
          'open_sessions' => false,
          'service'       => 'jupyterhub-login',
          'admin_groups'  => $admin_groups,
      }
    }
    if $enable_otp_auth {
      $authenticator_class = 'pammfauthenticator'
    } else {
      $authenticator_class = 'pam'
    }
  } elsif $authenticator == 'OIDC' {
    $authenticator_class = 'oauthenticator.generic.GenericOAuthenticator'
    $authenticator_config = {
      'GenericOAuthenticator' => {
        'client_id'          => lookup('jupyterhub::oauthenticator::client_id'),
        'client_secret'      => lookup('jupyterhub::oauthenticator::client_secret'),
        'authorize_url'      => lookup('jupyterhub::oauthenticator::authorize_url'),
        'token_url'          => lookup('jupyterhub::oauthenticator::token_url'),
        'userdata_url'       => lookup('jupyterhub::oauthenticator::userdata_url'),
        'userdata_params'    => lookup('jupyterhub::oauthenticator::userdata_params'),
        'oauth_callback_url' => lookup('jupyterhub::oauthenticator::oauth_callback_url'),
        'username_key'       => lookup('jupyterhub::oauthenticator::username_key'),
        'scope'              => lookup('jupyterhub::oauthenticator::scope'),
      }
    }
  }

  $node_prefix = lookup('jupyterhub::node::prefix', String, undef, $prefix)
  $jupyterhub_config_base = parsejson(file('jupyterhub/jupyterhub_config.json'))
  $jupyterhub_config_params = {
    'JupyterHub' => {
      'bind_url'                    => $bind_url,
      'allow_named_servers'         => $allow_named_servers,
      'named_server_limit_per_user' => $named_server_limit_per_user,
      'authenticator_class'         => $authenticator_class,
      'admin_access'                => Boolean(size($admin_groups) > 0),
      'services'                    => Boolean($idle_timeout > 0) ? {
        true => [{
          'name'    => 'jupyterhub-idle-culler-service',
          'command' => [
            "${prefix}/bin/python3",
            '-m',
            'jupyterhub_idle_culler',
            "--timeout=${idle_timeout}"
          ],
        }],
        false => [],
      },
      'load_roles'                  => Boolean($idle_timeout > 0) ? {
        true  => [{
          'name'    => 'jupyterhub-idle-culler-role',
          'scopes'  => ['list:users', 'read:users:activity', 'read:servers', 'delete:servers'],
          'services'=> ['jupyterhub-idle-culler-service'],
        }],
        false =>  [],
      }
    },
    'Authenticator' => {
      'blocked_users' => $blocked_users,
      'auto_login'    => $authenticator ? {
        'OIDC'  => true,
        default => false,
      },
    },
    'SlurmFormSpawner' => {
      'batchspawner_singleuser_cmd' => "${node_prefix}/bin/batchspawner-singleuser",
      'cmd'                         => "${node_prefix}/bin/jupyterhub-singleuser",
      'slurm_bin_path'              => "${slurm_home}/bin",
    }
  }

  $jupyterhub_config = deep_merge(
    $jupyterhub_config_base,
    $jupyterhub_config_params,
    $jupyterhub_config_hash,
    $authenticator_config,
  )

  file { 'jupyterhub_config.json':
    ensure  => 'present',
    path    => '/etc/jupyterhub/jupyterhub_config.json',
    content => to_json_pretty($jupyterhub_config, true),
    mode    => '0644',
  }

  $kernel_setup = lookup('jupyterhub::kernel::setup', Enum['venv', 'module'], undef, 'venv')
  $module_list = lookup('jupyterhub::kernel::module::list', Array[String], undef, [])
  $venv_prefix = lookup('jupyterhub::kernel::venv::prefix', String, undef, '/opt/ipython-kernel')
  file { 'submit.sh':
    ensure  => 'present',
    path    => '/etc/jupyterhub/submit.sh',
    content => epp('jupyterhub/submit.sh', {
      'kernel_setup'     => $kernel_setup,
      'module_list'      => join($module_list, ' '),
      'node_prefix'      => $node_prefix,
      'venv_prefix'      => $venv_prefix,
      'slurm_partitions' => join($slurm_partitions, ','),
    }),
    mode    => '0644'
  }

  $python3_version = lookup('jupyterhub::python3::version')
  # JupyterHub virtual environment
  exec { 'pip_idle_culler':
    command => "${prefix}/bin/pip install --no-cache-dir jupyterhub-idle-culler==${idle_culler_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/jupyterhub_idle_culler-${idle_culler_version}.dist-info/",
    require => Exec['pip_jupyterhub']
  }

  exec { 'pip_slurmformspawner':
    command => "${prefix}/bin/pip install --no-cache-dir slurmformspawner==${slurmformspawner_version}",
    creates => "${prefix}/lib/python${python3_version}/site-packages/slurmformspawner-${slurmformspawner_version}.dist-info/",
    require => Exec['pip_batchspawner']
  }

  if $authenticator == 'PAM' {
    exec { 'pip_pamela':
      command => "${prefix}/bin/pip install --no-cache-dir https://github.com/minrk/pamela/archive/master.zip",
      creates => "${prefix}/lib/python${python3_version}/site-packages/pamela-1.0.1.dev0-py${python3_version}.egg-info/",
      require => Exec['pip_jupyterhub']
    }
    if $enable_otp_auth {
      $pammfauthenticator_url = lookup('jupyterhub::pammfauthenticator::url')
      exec { 'pip_pammfauthenticator':
        command => "${prefix}/bin/pip install --no-cache-dir ${pammfauthenticator_url}",
        creates => "${prefix}/lib/python${python3_version}/site-packages/pammfauthenticator/",
        require => [Exec['pip_jupyterhub'], Exec['pip_pamela']],
        notify  => Service['jupyterhub']
      }
    }
  } elsif $authenticator == 'OIDC' {
    $oauthenticator_url = lookup('jupyterhub::oauthenticator::url')
    $git_tag = lookup('jupyterhub::oauthenticator::version')
    exec { 'pip_oauthenticator':
      command => "${prefix}/bin/pip install --no-cache-dir git+${oauthenticator_url}@${git_tag}",
      creates => "${prefix}/lib/python${python3_version}/site-packages/oauthenticator-${git_tag}.dist-info/",
      require => Exec['pip_jupyterhub']
    }
  }

  exec {'create_self_signed_sslcert':
    command => "openssl req -newkey rsa:4096 -nodes -keyout key.pem -x509 -days 3650 -out cert.pem -subj '/CN=${::fqdn}'",
    cwd     => '/etc/jupyterhub/ssl',
    creates => ['/etc/jupyterhub/ssl/key.pem', '/etc/jupyterhub/ssl/cert.pem'],
    path    => ['/usr/bin', '/usr/sbin'],
    umask   => '037'
  }

  file { '/etc/jupyterhub/ssl/cert.pem':
    mode    => '0644',
    require => [Exec['create_self_signed_sslcert']]
  }

  file { '/etc/jupyterhub/ssl/key.pem':
    mode    => '0640',
    group   => 'jupyterhub',
    require => [Exec['create_self_signed_sslcert']]
  }

  if $facts['os']['release']['major'] == '7' {
    $pycurl_package_name = lookup('jupyterhub::pycurl::package_name')
    ensure_packages ($pycurl_package_name)
    $jupyterhub_require = [
      File['submit.sh'],
      Package[$pycurl_package_name],
    ]
  } else  {
    $jupyterhub_require = [
      File['submit.sh'],
    ]
  }

  service { 'jupyterhub':
    ensure    => running,
    enable    => true,
    require   => $jupyterhub_require,
    subscribe => [
      Service['sssd'],
      Exec['pip_jupyterhub'],
      Exec['pip_idle_culler'],
      Exec['pip_batchspawner'],
      Exec['pip_slurmformspawner'],
      File['jupyterhub-login'],
      File['jupyterhub.service'],
      File['jupyterhub_config.json'],
      File['/etc/jupyterhub/ssl/cert.pem'],
      File['/etc/jupyterhub/ssl/key.pem'],
    ],
  }
}
