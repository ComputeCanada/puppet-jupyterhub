class jupyterhub::base {
  class { 'nodejs':
    repo_url_suffix => '8.x',
  }

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
    command => "/opt/jupyterhub/bin/pip install --no-cache-dir ${batchspawner_url}",
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/batchspawner/',
    require => Exec['pip_jupyterhub']
  }
}

class jupyterhub (String $domain_name,
                  String $slurm_home = '/opt/software/slurm') {
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

  package { 'nginx':
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

  $slurmformspawner_url = lookup('jupyterhub::slurmformspawner::url')
  $pammfauthenticator_url = lookup('jupyterhub::pammfauthenticator::url')

  file { 'jupyterhub_config.py':
    ensure => 'present',
    path   => '/etc/jupyterhub/jupyterhub_config.py',
    source => 'puppet:///modules/jupyterhub/jupyterhub_config.py',
    mode   => '0644',
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
    command => "/opt/jupyterhub/bin/pip install --no-cache-dir ${slurmformspawner_url}",
    creates => '/opt/jupyterhub/lib/python3.6/site-packages/slurmformspawner/',
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

  service { 'jupyterhub':
    ensure  => running,
    enable  => true,
    require => [Exec['pip_slurmformspawner'],
                Exec['pip_pammfauthenticator'],
                File['jupyterhub-login'],
                File['jupyterhub.service'],
                File['jupyterhub_config.py'],
                File['submit.sh'],
                File['/etc/jupyterhub/ssl/cert.pem'],
                File['/etc/jupyterhub/ssl/key.pem']]
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

  if $facts['letsencrypt'][$domain_name] != '' {
    file { 'jupyterhub.conf':
      path    => '/etc/nginx/conf.d/jupyterhub.conf',
      content => epp('jupyterhub/jupyterhub.conf', {'domain_name' => $domain_name, 'puppet_managed_cert' => true}),
      mode    => '0644',
      notify  => Service['nginx'],
      require => File['ffdhe4096.pem']
    }
  }
  else {
    file { 'jupyterhub.conf':
      path    => '/etc/nginx/conf.d/jupyterhub.conf',
      content => epp('jupyterhub/jupyterhub.conf', {'domain_name' => $domain_name, 'puppet_managed_cert' => false}),
      mode    => '0644',
      replace => false,
      notify  => Service['nginx'],
      require => File['ffdhe4096.pem']
    }

    exec { 'certbot-nginx':
      command => "certbot --nginx --register-unsafely-without-email --noninteractive --agree-tos --domains ${domain_name}",
      unless  => 'grep -q ssl_certificate /etc/nginx/conf.d/jupyterhub.conf',
      require => [Package['certbot-nginx'],
                  File['certbot-nginx'],
                  Firewall['200 nginx public'],
                  Service['nginx']],
      path    => ['/usr/bin', '/usr/sbin'],
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

  # This makes sure the /opt/jupyterhub install does not provide the default kernel.
  # The kernel is provided by the local install in /opt/ipython-kernel.
  exec { 'pip_uninstall_ipykernel':
    command => '/opt/jupyterhub/bin/pip uninstall -y ipykernel ipython prompt-toolkit wcwidth pickleshare backcall pexpect jedi parso',
    onlyif  => '/usr/bin/test -f /opt/jupyterhub/lib/python3.6/site-packages/ipykernel_launcher.py',
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

  $kernel_python_bin = lookup({'name'          => 'jupyterhub::kernel::python',
                               'default_value' => '/usr/bin/python36'})
  exec { 'kernel_venv':
    command => "${kernel_python_bin} -m venv /opt/ipython-kernel",
    creates => '/opt/ipython-kernel/bin/python',
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

  $jupyterhub_path = @(END)
# Add JupyterHub path
[[ ":$PATH:" != *":/opt/jupyterhub/bin:"* ]] && export PATH="/opt/jupyterhub/bin:${PATH}"
END

  file { '/etc/profile.d/z-01-jupyterhub.sh':
    ensure  => 'present',
    content => $jupyterhub_path
  }
}
