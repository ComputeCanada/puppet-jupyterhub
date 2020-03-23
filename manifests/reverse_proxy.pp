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
