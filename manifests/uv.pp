class jupyterhub::uv::install (
  String $prefix
  String $version = '0.4.22',
) {
  ensure_resource('file', $prefix, { 'ensure' => 'directory' })
  ensure_resource('file', "${prefix}/bin", { 'ensure' => 'directory', require => File[$prefix] })
  $arch = $::facts['os']['architecture']
  archive { 'jh_install_uv':
    path            => '/tmp/uv',
    source          => "https://github.com/astral-sh/uv/releases/download/${version}/uv-${arch}-unknown-linux-gnu.tar.gz",
    extract         => true,
    extract_path    => "${prefix}/bin",
    extract_command => 'tar xfz %s --strip-components=1',
    creates         => "${$prefix}/bin/uv",
    cleanup         => true,
    require         => File["${prefix}/bin"],
  }
}

define jupyterhub::uv::venv (
  String $prefix,
  String $version,
) {
  $uv_prefix = lookup('jupyterhub::uv::install::prefix')
  exec { 'jupyterhub_venv':
    command     => "uv venv -p ${version} ${prefix}",
    creates     => "${prefix}/bin/python",
    require     => Class['jupyterhub::uv::install'],
    path        => ["${uv_prefix}/bin"],
    environment => ["XDG_DATA_HOME=${uv_prefix}/share"],
  }
}
