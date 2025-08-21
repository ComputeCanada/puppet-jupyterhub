class jupyterhub::base::install (
  Stdlib::Absolutepath $prefix,
  String $uv_version = '0.4.22',
) {
  ensure_resource('file', '/opt/uv', { 'ensure' => 'directory' })
  ensure_resource('file', '/opt/uv/bin', { 'ensure' => 'directory', require => File['/opt/uv'] })
  $arch = $::facts['os']['architecture']
  archive { 'jh_install_uv':
    path            => '/tmp/uv',
    source          => "https://github.com/astral-sh/uv/releases/download/${uv_version}/uv-${arch}-unknown-linux-gnu.tar.gz",
    extract         => true,
    extract_path    => '/opt/uv/bin',
    extract_command => 'tar xfz %s --strip-components=1',
    creates         => '/opt/uv/bin/uv',
    cleanup         => true,
    require         => File['/opt/uv/bin'],
  }

  $python3_version = lookup('jupyterhub::python3::version')

  exec { 'jupyterhub_venv':
    command     => "uv venv -p ${python3_version} ${prefix}",
    creates     => "${prefix}/bin/python",
    require     => Archive['jh_install_uv'],
    path        => ['/opt/uv/bin'],
    environment => ['XDG_DATA_HOME=/opt/uv/share'],
  }
}
