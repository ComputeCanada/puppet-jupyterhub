class jupyterhub::base {
  package { 'python36':
    ensure => 'installed'
  }

  file { ['/opt/jupyterhub', '/opt/jupyterhub/bin']:
    ensure => directory
  }

  exec { 'jupyterhub_venv':
    command => '/usr/bin/python36 -m venv /opt/jupyterhub',
    creates => '/opt/jupyterhub/bin/python',
    require => Package['python36']
  }

  $jupyterhub_version = lookup('jupyterhub::jupyterhub::version')
  $batchspawner_url = lookup('jupyterhub::batchspawner::url')

  exec { 'pip_jupyterhub':
    command => "/opt/jupyterhub/bin/pip install --upgrade --no-cache-dir jupyterhub==${jupyterhub_version}",
    creates => "/opt/jupyterhub/lib/python3.6/site-packages/jupyterhub-${jupyterhub_version}.dist-info/",
    require => Exec['jupyterhub_venv']
  }

  exec { 'pip_batchspawner':
    command => "/opt/jupyterhub/bin/pip install --no-cache-dir ${$batchspawner_url}",
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/batchspawner/',
    require => Exec['pip_jupyterhub']
  }
}

class jupyterhub (String $domain_name = '',
                  String $slurm_home = '/opt/software/slurm',
                  Boolean $use_ssl = true) {
  include jupyterhub::base

  selinux::boolean { 'httpd_can_network_connect': }

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

  class { 'nodejs':
    repo_url_suffix => '8.x',
  }

  package { 'nginx':
    ensure => 'installed'
  }
  package { 'certbot-nginx':
    ensure => 'installed'
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

  file { '/etc/jupyterhub':
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

  $slurmformspawner_url = lookup('jupyterhub::slurmformspawner::url')
  $tarball_path = lookup('jupyterhub::tarball::path')

  file { 'jupyterhub_config.py':
    ensure => 'present',
    path   => '/etc/jupyterhub/jupyterhub_config.py',
    source => 'puppet:///modules/jupyterhub/jupyterhub_config.py',
    mode   => '0644',
  }

  file { 'submit.sh':
    ensure  => 'present',
    path    => '/etc/jupyterhub/submit.sh',
    content => epp('jupyterhub/submit.sh', {'tarball_path' => $tarball_path}),
    mode    => '0644',
    replace => false
  }

  # JupyterHub virtual environment
  exec { 'pip_slurmformspawner':
    command => "/opt/jupyterhub/bin/pip install --no-cache-dir ${slurmformspawner_url}",
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/slurmformspawner/',
    require => Exec['pip_batchspawner']
  }

  service { 'jupyterhub':
    ensure  => running,
    enable  => true,
    require => [Exec['pip_slurmformspawner'],
                File['jupyterhub-login'],
                File['jupyterhub.service'],
                File['jupyterhub_config.py'],
                File['submit.sh']]
  }

  file { 'jupyterhub.conf':
    path    => '/etc/nginx/conf.d/jupyterhub.conf',
    content => epp('jupyterhub/jupyterhub.conf', {'domain_name' => $domain_name}),
    mode    => '0644',
    replace => ! $use_ssl,
    notify  => Service['nginx']
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

  if $domain_name != '' and $use_ssl {
    exec { 'certbot-nginx':
      command => "/usr/bin/certbot --nginx --register-unsafely-without-email --noninteractive --redirect --agree-tos --domains ${domain_name}",
      creates => "/etc/letsencrypt/live/${domain_name}/cert.pem",
      require => [Package['certbot-nginx'],
                  Firewall['200 nginx public'],
                  Service['nginx']]
    }

    cron { 'certbot':
      command => '/usr/bin/certbot renew --renew-hook "/usr/bin/systemctl reload nginx"',
      user    => 'root',
      minute  => 52,
      hour    => [0, 12],
      require => Exec['certbot-nginx']
    }
  }
}

class jupyterhub::node {
  include jupyterhub::base

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

  exec { 'pip_jupyterlab-hub':
    command => '/opt/jupyterhub/bin/jupyter labextension install @jupyterlab/hub-extension',
    creates => '/opt/jupyterhub/bin/jupyter-labhub',
    require => Exec['pip_jupyterlab']
  }

  exec { 'pip_jupyterlab-lmod':
    command => '/opt/jupyterhub/bin/jupyter labextension install jupyterlab-lmod',
    creates => '/opt/jupyterhub/share/jupyter/lab/staging/node_modules/jupyterlab-lmod',
    require => Exec['pip_jupyterlab']
  }

  exec { 'enable_nbserverproxy_srv':
    command => '/opt/jupyterhub/bin/jupyter serverextension enable --py nbserverproxy --sys-prefix',
    unless  => 'grep -q nbserverproxy /dev/shm/jupyter/etc/jupyter/jupyter_notebook_config.json',
    require => Exec['pip_nbserverproxy']
  }

  exec { 'enable_nbrsessionproxy_srv':
    command => '/opt/jupyterhub/bin/jupyter serverextension enable --py nbrsessionproxy --sys-prefix',
    unless  => 'grep -q nbrsessionproxy /dev/shm/jupyter/etc/jupyter/jupyter_notebook_config.json',
    require => Exec['pip_nbrsessionproxy']
  }

  exec { 'install_nbrsessionproxy_nb':
    command => '/opt/jupyterhub/bin/jupyter nbextension install --py nbrsessionproxy --sys-prefix',
    creates => '/dev/shm/jupyter/share/jupyter/nbextensions/nbrsessionproxy',
    require => Exec['pip_nbrsessionproxy']
  }

  exec { 'enable_nbrsessionproxy_nb':
    command => '/opt/jupyterhub/bin/jupyter nbextension enable --py nbrsessionproxy --sys-prefix',
    unless  => 'grep -q nbrsessionproxy/tree /dev/shm/jupyter/etc/jupyter/nbconfig/tree.json',
    require => Exec['pip_nbrsessionproxy']
  }
}

class jupyterhub::venv_builder {
  include jupyterhub::base

  $tarball_path = lookup('jupyterhub::tarball::path')
  $python_path = lookup('jupyterhub::tarball::python')

  file { 'build_venv_tarball.sh':
    ensure  => present,
    path    => '/opt/jupyterhub/bin/build_venv_tarball.sh',
    content => epp('jupyterhub/build_venv_tarball.sh', {'tarball_path' => $tarball_path,
                                                        'python_path'  => $python_path}),
    mode    => '0755',
    require => File['/opt/jupyterhub/bin']
  }

  exec { 'jupyter_tarball':
    command => '/opt/jupyterhub/bin/build_venv_tarball.sh',
    creates => $tarball_path,
    require => File['build_venv_tarball.sh']
  }
}
