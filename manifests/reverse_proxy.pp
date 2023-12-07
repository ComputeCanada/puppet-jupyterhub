class jupyterhub::reverse_proxy (
  Variant[String, Array[String]] $domain_name,
  Boolean $config_firewall = true,
  String $ssl_certificate_path = '',
  String $ssl_certificate_key_path = '',
) {
  selinux::boolean { 'httpd_can_network_connect': }

  package { 'nginx':
    ensure => 'installed'
  }

  # https://wiki.mozilla.org/Security/Server_Side_TLS#ffdhe4096.pem
  file { 'ffdhe4096.pem':
    ensure => present,
    path   => '/etc/nginx/ffdhe4096.pem',
    source => 'puppet:///modules/jupyterhub/ffdhe4096.pem',
    mode   => '0644',
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

  if ($config_firewall) {
    firewall { '200 nginx public':
      chain  => 'INPUT',
      dport  => [80, 443],
      proto  => 'tcp',
      source => '0.0.0.0/0',
      action => 'accept'
    }
  }

  if $domain_name.is_a(String) {
    $certname = $domain_name
    $domains = [$domain_name]
  } else {
    $certname = $domain_name[0]
    $domains = $domain_name
  }

  $use_letsencrypt = lookup('jupyterhub::reverse_proxy::letsencrypt::enable', Boolean, undef, true)
  file { 'jupyterhub.conf':
    path    => '/etc/nginx/conf.d/jupyterhub.conf',
    content => epp('jupyterhub/jupyterhub.conf', {
        'domains'                  => $domains,
        'certname'                 => $certname,
        'use_letsencrypt'          => $use_letsencrypt,
        'ssl_certificate_path'     => $ssl_certificate_path,
        'ssl_certificate_key_path' => $ssl_certificate_key_path,
    }),
    mode    => '0644',
    notify  => Service['nginx'],
    require => File['ffdhe4096.pem'],
  }

  if ($use_letsencrypt) {
    class { '::letsencrypt':
      configure_epel      => lookup('jupyterhub::reverse_proxy::letsencrypt::configure_epel', Boolean, undef,  false),
      renew_cron_ensure   => lookup('jupyterhub::reverse_proxy::letsencrypt::renew_cron_ensure', String, undef, 'present'),
      unsafe_registration => lookup('jupyterhub::reverse_proxy::letsencrypt::unsafe_registration', Boolean, undef, true),
      email               => lookup('jupyterhub::reverse_proxy::letsencrypt::email', undef, undef, undef),
    }
    letsencrypt::certonly { $certname:
      domains              => $domains,
      plugin               => lookup('jupyterhub::reverse_proxy::letsencrypt::certonly::plugin', String, undef, 'standalone'),
      pre_hook_commands    => ['/bin/systemctl stop nginx'],
      deploy_hook_commands => ['/bin/systemctl start nginx'],
    }
  }
}
