class jupyterhub::base {
  class { 'nodejs':
    repo_url_suffix => '12.x',
  }

  package { 'python3':
    ensure => 'installed'
  }

  file { ['/opt/jupyterhub', '/opt/jupyterhub/bin']:
    ensure => directory
  }

  exec { 'jupyterhub_venv':
    command => '/usr/bin/python3 -m venv /opt/jupyterhub',
    creates => '/opt/jupyterhub/bin/python',
    require => Package['python3']
  }

  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_url = lookup('jupyterhub::batchspawner::url')

  exec { 'pip_jupyterhub':
    command => "/opt/jupyterhub/bin/pip install --upgrade --no-cache-dir jupyterhub==${jupyterhub_version}",
    creates => "/opt/jupyterhub/lib/python3.6/site-packages/jupyterhub-${jupyterhub_version}.dist-info/",
    require => Exec['jupyterhub_venv']
  }

  exec { 'pip_batchspawner':
    command => "/opt/jupyterhub/bin/pip install --no-cache-dir ${batchspawner_url}",
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/batchspawner/',
    require => Exec['pip_jupyterhub']
  }
}

class jupyterhub (
  String $slurm_home = '/opt/software/slurm',
  Boolean $allow_named_servers = true,
  Integer $named_server_limit_per_user = 0,
  Boolean $enable_otp_auth = true,
  Boolean $skip_form = false,
  Optional[Array[String]] $admin_groups = undef,
  Optional[Integer] $idle_timeout = undef,
  ) {
  include jupyterhub::base

  user { 'jupyterhub':
    ensure  => 'present',
    groups  => 'jupyterhub',
    comment => 'JupyterHub',
    home    => '/var/run/jupyterhub',
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
    content => epp('jupyterhub/99-jupyterhub-user', {'slurm_home' => $slurm_home})
  }

  file_line { 'slurm_bin_sudo_secure_path':
    path  => '/etc/sudoers',
    line  => "Defaults    secure_path = /sbin:/bin:/usr/sbin:/usr/bin:${slurm_home}/bin",
    match => '^Defaults\ \ \ \ secure_path\ \=',
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

  file { ['/etc/jupyterhub', '/etc/jupyterhub/ssl']:
    ensure => directory
  }

  file { '/var/run/jupyterhub':
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

  $slurmformspawner_version = lookup('jupyterhub::slurmformspawner::version')
  $pammfauthenticator_url = lookup('jupyterhub::pammfauthenticator::url')
  $form_params = merge(
    {
      'core'          => {},
      'gpus'          => {},
      'mem'           => {},
      'oversubscribe' => {},
      'runtime'       => {},
      'ui'            => {},
    },
    lookup('jupyterhub::slurmformspawner::form_params', undef, undef, {})
  )

  file { 'jupyterhub_config.py':
    ensure  => 'present',
    path    => '/etc/jupyterhub/jupyterhub_config.py',
    content => epp('jupyterhub/jupyterhub_config.py', {
        'allow_named_servers'         => $allow_named_servers,
        'named_server_limit_per_user' => $named_server_limit_per_user,
        'enable_otp_auth'             => $enable_otp_auth,
        'admin_groups'                => $admin_groups,
        'idle_timeout'                => $idle_timeout,
        'skip_form'                   => $skip_form,
        'form_params'                 => $form_params,
      }),
    mode    => '0644',
  }

  file { 'submit.sh':
    ensure  => 'present',
    path    => '/etc/jupyterhub/submit.sh',
    content => epp('jupyterhub/submit.sh'),
    mode    => '0644',
    replace => false
  }

  # JupyterHub virtual environment
  exec { 'pip_slurmformspawner':
    command => "/opt/jupyterhub/bin/pip install --no-cache-dir slurmformspawner==${slurmformspawner_version}",
    creates => "/opt/jupyterhub/lib/python3.6/site-packages/slurmformspawner-${slurmformspawner_version}.dist-info/",
    require => Exec['pip_batchspawner']
  }

  exec { 'pip_pamela':
    command => '/opt/jupyterhub/bin/pip install --no-cache-dir https://github.com/minrk/pamela/archive/master.zip',
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/pamela-1.0.1.dev0-py3.6.egg-info/',
    require => Exec['pip_jupyterhub']
  }

  exec { 'pip_pammfauthenticator':
    command => "/opt/jupyterhub/bin/pip install --no-cache-dir ${pammfauthenticator_url}",
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/pammfauthenticator/',
    require => [Exec['pip_jupyterhub'], Exec['pip_pamela']]
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

  package { 'python36-pycurl':
    ensure => 'installed'
  }

  file { '/opt/jupyterhub/bin/cull_idle_servers.py':
    source => 'puppet:///modules/jupyterhub/cull_idle_servers.py',
    owner  => 'jupyterhub',
    group  => 'jupyterhub',
    mode   => '0755',
  }

  service { 'jupyterhub':
    ensure    => running,
    enable    => true,
    require   => [
      Package['python36-pycurl'],
      File['submit.sh'],
    ],
    subscribe => [
      Service['sssd'],
      Exec['pip_jupyterhub'],
      Exec['pip_batchspawner'],
      Exec['pip_slurmformspawner'],
      Exec['pip_pammfauthenticator'],
      File['jupyterhub-login'],
      File['jupyterhub.service'],
      File['jupyterhub_config.py'],
      File['/etc/jupyterhub/ssl/cert.pem'],
      File['/etc/jupyterhub/ssl/key.pem'],
      File['/opt/jupyterhub/bin/cull_idle_servers.py'],
    ],
  }
}

class jupyterhub::reverse_proxy(String $domain_name) {
  selinux::boolean { 'httpd_can_network_connect': }

  package { 'nginx':
    ensure => 'installed'
  }

  # https://wiki.mozilla.org/Security/Server_Side_TLS#ffdhe4096.pem
  file { 'ffdhe4096.pem':
    ensure => 'present',
    path   => '/etc/nginx/ffdhe4096.pem',
    source => 'puppet:///modules/jupyterhub/ffdhe4096.pem',
    mode   => '0644'
  }

  file_line { 'nginx_default_server_ipv4':
    ensure            => absent,
    path              => '/etc/nginx/nginx.conf',
    match             => 'listen       80 default_server;',
    match_for_absence => true,
    notify            => Service['nginx']
  }

  file_line { 'nginx_default_server_ipv6':
    ensure            => absent,
    path              => '/etc/nginx/nginx.conf',
    match             => 'listen       \[::\]:80 default_server;',
    match_for_absence => true,
    notify            => Service['nginx']
  }

  service { 'nginx':
    ensure => running,
    enable => true
  }

  firewall { '200 nginx public':
    chain  => 'INPUT',
    dport  => [80, 443],
    proto  => 'tcp',
    source => '0.0.0.0/0',
    action => 'accept'
  }

  package { 'certbot-nginx':
    ensure => 'installed'
  }

  if $facts['letsencrypt'] != undef and $facts['letsencrypt'][$domain_name] != '' {
    file { 'jupyterhub.conf':
      path    => '/etc/nginx/conf.d/jupyterhub.conf',
      content => epp('jupyterhub/jupyterhub.conf', {'domain_name' => $domain_name, 'puppet_managed_ssl' => true}),
      mode    => '0644',
      notify  => Service['nginx'],
      require => File['ffdhe4096.pem']
    }
  }
  else {
    file { 'jupyterhub.conf':
      path    => '/etc/nginx/conf.d/jupyterhub.conf',
      content => epp('jupyterhub/jupyterhub.conf', {'domain_name' => $domain_name, 'puppet_managed_ssl' => false}),
      mode    => '0644',
      replace => false,
      notify  => Service['nginx'],
      require => File['ffdhe4096.pem']
    }

    exec { 'certbot-nginx':
      command => "certbot --nginx --register-unsafely-without-email --noninteractive --agree-tos --domains ${domain_name}",
      unless  => 'grep -q ssl_certificate /etc/nginx/conf.d/jupyterhub.conf',
      require => [Package['certbot-nginx'],
                  File['jupyterhub.conf'],
                  Firewall['200 nginx public'],
                  Service['nginx']],
      path    => ['/usr/bin', '/usr/sbin'],
    }
  }
}

class jupyterhub::node (
  Optional[String] $http_proxy = undef,
  Optional[String] $https_proxy = undef,
) {
  include jupyterhub::base

  if ($http_proxy != undef and $https_proxy != undef){
    # Lets use a proxy for all the pip install
    Exec {
      environment => ["http_proxy=$http_proxy", "https_proxy=$https_proxy"],
    }
  }

  exec { 'pip_notebook':
    command => '/opt/jupyterhub/bin/pip install --no-cache-dir notebook',
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/notebook/',
    require => Exec['jupyterhub_venv']
  }

  exec { 'pip_jupyterlab':
    command => '/opt/jupyterhub/bin/pip install --no-cache-dir jupyterlab',
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/jupyterlab/',
    require => Exec['jupyterhub_venv']
  }

  exec { 'pip_jupyterlmod':
    command => '/opt/jupyterhub/bin/pip install --no-cache-dir jupyterlmod',
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/jupyterlmod/',
    require => Exec['pip_notebook']
  }

  exec { 'pip_nbserverproxy':
    command => '/opt/jupyterhub/bin/pip install --no-cache-dir nbserverproxy',
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/nbserverproxy/',
    require => Exec['pip_notebook']
  }

  exec { 'pip_nbrsessionproxy':
    command => '/opt/jupyterhub/bin/pip install --no-cache-dir https://github.com/jupyterhub/nbrsessionproxy/archive/v0.8.0.zip',
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/nbrsessionproxy/',
    require => Exec['pip_notebook']
  }

  exec { 'pip_nbzip':
    command => '/opt/jupyterhub/bin/pip install --no-cache-dir --no-deps nbzip',
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/nbzip',
    require => Exec['pip_notebook']
  }

  # This makes sure the /opt/jupyterhub install does not provide the default kernel.
  # The kernel is provided by the local install in /opt/ipython-kernel.
  exec { 'pip_uninstall_ipykernel':
    command => '/opt/jupyterhub/bin/pip uninstall -y ipykernel ipython prompt-toolkit wcwidth pickleshare backcall pexpect jedi parso',
    onlyif  => '/usr/bin/test -f /opt/jupyterhub/lib/python3.6/site-packages/ipykernel_launcher.py',
    require => Exec['pip_notebook']
  }

  exec { 'jupyter-labextension-lmod':
    command => '/opt/jupyterhub/bin/jupyter labextension install jupyterlab-lmod',
    creates => '/opt/jupyterhub/share/jupyter/lab/staging/node_modules/jupyterlab-lmod',
    timeout => 0,
    require => Exec['pip_jupyterlab'],
  }

  exec { 'enable_nbserverproxy_srv':
    command => '/opt/jupyterhub/bin/jupyter serverextension enable --py nbserverproxy --sys-prefix',
    unless  => '/usr/bin/grep -q nbserverproxy /opt/jupyterhub/etc/jupyter/jupyter_notebook_config.json',
    require => Exec['pip_nbserverproxy']
  }

  exec { 'enable_nbrsessionproxy_srv':
    command => '/opt/jupyterhub/bin/jupyter serverextension enable --py nbrsessionproxy --sys-prefix',
    unless  => '/usr/bin/grep -q nbrsessionproxy /opt/jupyterhub/etc/jupyter/jupyter_notebook_config.json',
    require => Exec['pip_nbrsessionproxy']
  }

  exec { 'install_nbrsessionproxy_nb':
    command => '/opt/jupyterhub/bin/jupyter nbextension install --py nbrsessionproxy --sys-prefix',
    creates => '/opt/jupyterhub/share/jupyter/nbextensions/nbrsessionproxy',
    require => Exec['pip_nbrsessionproxy']
  }

  exec { 'enable_nbrsessionproxy_nb':
    command => '/opt/jupyterhub/bin/jupyter nbextension enable --py nbrsessionproxy --sys-prefix',
    unless  => '/usr/bin/grep -q nbrsessionproxy/tree /opt/jupyterhub/etc/jupyter/nbconfig/tree.json',
    require => Exec['pip_nbrsessionproxy']
  }

  exec { 'enable_nbzip_srv':
    command => '/opt/jupyterhub/bin/jupyter serverextension enable --py nbzip --sys-prefix',
    unless  => '/usr/bin/grep -q nbzip /opt/jupyterhub/etc/jupyter/jupyter_notebook_config.json',
    require => Exec['pip_nbzip']
  }

  exec { 'install_nbzip_nb':
    command => '/opt/jupyterhub/bin/jupyter nbextension install --py nbzip --sys-prefix',
    creates => '/opt/jupyterhub/share/jupyter/nbextensions/nbzip',
    require => Exec['pip_nbzip']
  }

  exec { 'enable_nbzip_nb':
    command => '/opt/jupyterhub/bin/jupyter nbextension enable --py nbzip --sys-prefix',
    unless  => '/usr/bin/grep -q nbzip/tree /opt/jupyterhub/etc/jupyter/nbconfig/tree.json',
    require => Exec['pip_nbzip']
  }

  $kernel_python_bin = lookup({'name'          => 'jupyterhub::kernel::python',
                               'default_value' => '/usr/bin/python3'})
  exec { 'kernel_venv':
    command => "${kernel_python_bin} -m venv /opt/ipython-kernel",
    creates => '/opt/ipython-kernel/bin/python',
  }

  exec { 'upgrade_pip_setuptools':
    command     => '/opt/ipython-kernel/bin/pip install --no-cache-dir --upgrade pip setuptools',
    subscribe   => Exec['kernel_venv'],
    refreshonly => true,
  }

  exec { 'pip_ipykernel':
    command => '/opt/ipython-kernel/bin/pip install --no-cache-dir ipykernel',
    creates => '/opt/ipython-kernel/bin/ipython',
    require => Exec['kernel_venv']
  }

  exec { 'install_kernel':
    command => '/opt/ipython-kernel/bin/python -m ipykernel install --name "python3" --prefix /opt/jupyterhub',
    creates => '/opt/jupyterhub/share/jupyter/kernels/python3/kernel.json',
    require => [Exec['pip_ipykernel'], Exec['pip_uninstall_ipykernel']]
  }

  $requirements = lookup({'name' => 'jupyterhub::kernel::requirements', 'default_value' => []})
  $pip_environment = lookup({'name' => 'jupyterhub::kernel::pip_environment', 'default_value' => {}})
  $pip_env_list = $pip_environment.reduce([]) |Array $list, Array $value| {
    $list + ["${value[0]}=${value[1]}"]
  }
  if (!$requirements.empty) {
    $requirements_string = join($requirements, ' ')
    exec { 'install_kernel_requirements_nodeps':
      command     => "/opt/ipython-kernel/bin/pip install --no-deps --no-cache-dir --upgrade ${requirements_string}",
      subscribe   => Exec['upgrade_pip_setuptools'],
      refreshonly => true,
      environment => $pip_env_list,
      timeout     => 0,
    }
    exec { 'install_kernel_requirements_deps':
      command     => "/opt/ipython-kernel/bin/pip install --no-cache-dir --upgrade ${requirements_string}",
      subscribe   => Exec['install_kernel_requirements_nodeps'],
      refreshonly => true,
      environment => $pip_env_list,
      timeout     => 0,
    }
  }
}
